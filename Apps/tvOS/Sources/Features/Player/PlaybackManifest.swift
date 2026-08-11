import Foundation
import JellyfinKit
import Network
import os

/// Sert au lecteur une playlist maître réécrite, depuis la boucle locale.
///
/// Jellyfin propose trois variantes pour un film HDR, toutes au même débit : la
/// première garde la plage d'origine et lui permet de **recopier** le flux, les
/// deux suivantes sont des replis convertis en SDR qu'il ne peut produire qu'en
/// réencodant l'image. Le lecteur ne suit pas cet ordre, et sur un film HDR10+
/// il écarte carrément la bonne : elle porte `SUPPLEMENTAL-CODECS="…/cdm4"`,
/// une surcouche qu'il ne connaît pas. Ne lui en laisser qu'une supprime le
/// choix — encore faut-il pouvoir lui remettre une playlist de notre façon.
///
/// `AVAssetResourceLoader` semblait fait pour ça, et échoue ici sans rien
/// expliquer (`AVFoundationErrorDomain -11868`, `CoreMediaErrorDomain -17223`)
/// même en lui répondant un type uniforme, une longueur et la plage demandée.
/// Passer par un serveur sur la boucle locale est la voie établie : le lecteur
/// charge une vraie ressource HTTP, sans schéma d'emprunt ni cas particulier.
///
/// Seule la playlist maître transite par ici — quelques centaines d'octets. Les
/// adresses qu'elle contient sont absolues, si bien que la variante, les
/// segments et les sous-titres repartent directement vers le serveur Jellyfin.
final class PlaybackManifestServer: @unchecked Sendable {

    private let queue = DispatchQueue(label: "fr.sofafin.manifeste")
    private var listener: NWListener?
    /// Ce que l'on sert, indexé par chemin. Protégé par `queue`.
    private var documents: [String: Data] = [:]
    private var nextIdentifier = 0

    // MARK: Publication

    /// Récupère la playlist maître, la réduit à sa bonne variante, et renvoie
    /// l'adresse locale à laquelle le lecteur la trouvera.
    ///
    /// Renvoie l'adresse d'origine si quoi que ce soit échoue : une lecture qui
    /// laisse le lecteur choisir sa variante vaut mieux qu'une lecture qui
    /// n'ouvre pas.
    func localURL(for master: URL) async -> URL {
        do {
            let (data, _) = try await URLSession.shared.data(from: master)
            guard let manifest = String(data: data, encoding: .utf8) else { return master }
            let rewritten = HLSManifest.keepingOnlyFirstVariant(of: manifest, relativeTo: master)
            let port = try await start()

            let path = queue.sync { () -> String in
                nextIdentifier += 1
                let path = "/\(nextIdentifier).m3u8"
                documents[path] = Data(rewritten.utf8)
                return path
            }
            guard let local = URL(string: "http://127.0.0.1:\(port)\(path)") else { return master }

            for line in rewritten.components(separatedBy: .newlines)
            where line.hasPrefix("#EXT-X-STREAM-INF") {
                jellyfinLog.debug("LECTURE · variante servie · \(line, privacy: .public)")
            }

            // Se relire soi-même : un serveur injoignable produit exactement la
            // même erreur d'ouverture qu'un flux illisible, et les distinguer
            // après coup demande de tout reprendre depuis le début.
            let (echo, response) = try await URLSession.shared.data(from: local)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            jellyfinLog.debug(
                "LECTURE · playlist locale · \(local.absoluteString, privacy: .public) · statut \(status, privacy: .public) · \(echo.count, privacy: .public) octets"
            )
            guard status == 200, echo.count == rewritten.utf8.count else { return master }

            return local
        } catch {
            jellyfinLog.error(
                "LECTURE · playlist non réécrite, le lecteur choisira seul : \(error.localizedDescription, privacy: .public)"
            )
            return master
        }
    }

    // MARK: Serveur

    /// Démarre à la première utilisation et reste en place : le lecteur recharge
    /// la playlist en cours de route, et un serveur fermé entre-temps
    /// interromprait la lecture.
    ///
    /// Le port n'est attribué qu'une fois le serveur prêt : le lire avant renvoie
    /// zéro, et l'adresse construite dessus n'est joignable par personne.
    private func start() async throws -> NWEndpoint.Port.IntegerLiteralType {
        if let listener, listener.state == .ready, let port = listener.port {
            return port.rawValue
        }

        let parameters = NWParameters.tcp
        // Rien d'autre que cet appareil ne doit joindre ce serveur.
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            // `stateUpdateHandler` est appelé plusieurs fois, et reprendre une
            // continuation deux fois arrête le programme.
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let resume: @Sendable (Result<NWEndpoint.Port.IntegerLiteralType, Error>) -> Void = { result in
                let alreadyResumed = resumed.withLock { done -> Bool in
                    defer { done = true }
                    return done
                }
                guard !alreadyResumed else { return }
                continuation.resume(with: result)
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        resume(.failure(URLError(.cannotConnectToHost)))
                        return
                    }
                    resume(.success(port.rawValue))
                case .failed(let error), .waiting(let error):
                    resume(.failure(error))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        serve(connection, pending: Data())
    }

    /// Sert les requêtes d'une connexion, l'une après l'autre.
    ///
    /// Ne lire qu'une fois suffisait à tout faire échouer : le lecteur ouvre une
    /// connexion, demande la playlist, puis en redemande sur la **même**
    /// connexion. Sans deuxième lecture, il attend indéfiniment une réponse qui
    /// ne vient pas, et l'élément n'est jamais ni prêt ni en échec.
    private func serve(_ connection: NWConnection, pending: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var buffer = pending
            if let data { buffer.append(data) }

            // Une requête peut arriver en plusieurs morceaux : on attend sa fin
            // d'en-têtes avant de répondre.
            let terminator = Data("\r\n\r\n".utf8)
            while let end = buffer.range(of: terminator) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                buffer.removeSubrange(..<end.upperBound)
                connection.send(content: self.response(to: head), completion: .idempotent)
            }

            if isComplete {
                connection.cancel()
            } else {
                self.serve(connection, pending: buffer)
            }
        }
    }

    /// Répond à une requête HTTP réduite à sa plus simple expression : le seul
    /// client est le lecteur du système, sur la boucle locale.
    private func response(to head: String) -> Data {
        let request = head.components(separatedBy: "\r\n").first?.components(separatedBy: " ") ?? []
        let method = request.first ?? "GET"
        let path = request.dropFirst().first ?? ""

        guard let document = documents[String(path)] else {
            return Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n".utf8)
        }

        var response = Data("""
        HTTP/1.1 200 OK\r
        Content-Type: application/vnd.apple.mpegurl\r
        Content-Length: \(document.count)\r
        Accept-Ranges: none\r
        Cache-Control: no-cache\r
        \r\n
        """.utf8)
        // Une réponse à HEAD porte les mêmes en-têtes et pas de corps.
        if method != "HEAD" { response.append(document) }
        return response
    }
}
