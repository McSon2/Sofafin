import AVFoundation
import AVKit
import JellyfinKit
import Foundation

/// Pourquoi une lecture ne démarre pas.
///
/// La négociation avec Jellyfin réussit presque toujours — le serveur répond, un
/// plan est construit, une URL est produite. Tout ce qui échoue ensuite se passe
/// **dans AVFoundation**, qui ne dit rien de lui-même : l'écran reste sur son
/// indicateur de chargement et le journal s'arrête sur la ligne `LECTURE`.
///
/// Trois sources, complémentaires et toutes silencieuses par défaut :
///
/// - `status == .failed` — l'échec franc, avec son `NSError` et souvent une erreur
///   sous-jacente autrement plus parlante (`NSUnderlyingError`) ;
/// - le **journal d'erreurs** de l'élément, qui porte les codes HTTP des segments
///   HLS refusés par le serveur : c'est là qu'apparaît un transcodage qui échoue
///   alors que la playlist, elle, s'est chargée ;
/// - `FailedToPlayToEndTime`, pour un flux qui démarre puis meurt en route.
/// Un échec, réduit à des valeurs transportables.
///
/// `Error` et `Notification` ne franchissent pas une frontière d'acteur : on en
/// extrait ce qui compte **là où l'objet arrive**, avant de le confier au fil
/// principal.
struct PlaybackFailure: Sendable {
    let description: String
    let domain: String
    let code: Int
    let underlying: String?

    init(_ error: Error?) {
        let nsError = error as NSError?
        description = error?.localizedDescription ?? "sans description"
        domain = nsError?.domain ?? "inconnu"
        code = nsError?.code ?? 0
        underlying = (nsError?.userInfo[NSUnderlyingErrorKey] as? NSError)?.description
    }
}

extension PlaybackEngine {

    /// Branche l'écoute des échecs. Appelée en même temps que les autres
    /// observateurs, libérée avec eux.
    func attachDiagnostics(to playerItem: AVPlayerItem) {
        // L'échec franc.
        failureObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let failure = PlaybackFailure(item.error)
            Task { @MainActor [weak self] in
                self?.reportPlaybackFailure(failure, origin: "statut de l'élément")
            }
        }

        // Les segments refusés. Le nom de la notification est trompeur : elle ne
        // signale pas une interruption, seulement une **entrée ajoutée au journal**.
        // La lecture peut continuer — ou, comme ici, ne jamais démarrer.
        errorLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let item = self?.player.currentItem else { return }
                self?.logErrorEntries(of: item)
            }
        }

        // Le flux qui meurt après avoir démarré.
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            let failure = PlaybackFailure(
                notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            )
            MainActor.assumeIsolated {
                self?.reportPlaybackFailure(failure, origin: "lecture interrompue")
            }
        }
    }

    func detachDiagnostics() {
        failureObserver = nil
        if let errorLogObserver { NotificationCenter.default.removeObserver(errorLogObserver) }
        errorLogObserver = nil
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        stallObserver = nil
    }

    // MARK: Journalisation

    /// Ce qu'il faut pour rejouer le problème à la main : l'URL exacte que le
    /// lecteur attaque, et la façon dont le serveur a décidé de la servir.
    func logPlaybackStart(_ plan: PlaybackPlan, resume: Double, segments: Int, chapters: Int, next: String?) {
        jellyfinLog.debug(
            "LECTURE · \(plan.method.rawValue, privacy: .public) · départ \(resume.timecode, privacy: .public) · \(segments) segments · \(chapters) chapitres · suite : \(next ?? "aucune", privacy: .public)"
        )
        // Journalisée en clair : c'est elle qu'on colle dans un navigateur ou dans
        // `ffplay` pour savoir en dix secondes si le problème vient du serveur ou
        // du lecteur. Le jeton qu'elle contient est révocable.
        jellyfinLog.debug("LECTURE · flux : \(plan.url.absoluteString, privacy: .public)")
    }

    /// Vide le journal d'erreurs de l'élément dans le nôtre.
    private func logErrorEntries(of item: AVPlayerItem) {
        guard let log = item.errorLog() else { return }
        for event in log.events.suffix(3) {
            jellyfinLog.error(
                """
                LECTURE · erreur de flux · statut \(event.errorStatusCode, privacy: .public) \
                · domaine \(event.errorDomain, privacy: .public) \
                · \(event.errorComment ?? "sans commentaire", privacy: .public) \
                · URI \(event.uri ?? "inconnue", privacy: .public)
                """
            )
        }
    }

    /// Consigne l'échec et le remonte à l'écran : un indicateur de chargement qui
    /// tourne indéfiniment n'apprend rien à l'utilisateur et masque la cause.
    func reportPlaybackFailure(_ failure: PlaybackFailure, origin: String) {
        jellyfinLog.error(
            """
            LECTURE · ÉCHEC (\(origin, privacy: .public)) \
            · \(failure.description, privacy: .public) \
            · domaine \(failure.domain, privacy: .public) code \(failure.code, privacy: .public) \
            · sous-jacente : \(failure.underlying ?? "aucune", privacy: .public)
            """
        )
        if let item = player.currentItem { logErrorEntries(of: item) }
        markFailed(Self.readableMessage(for: failure))
    }

    /// Traduit ce qu'AVFoundation renvoie en une phrase qui oriente vers la cause.
    /// Ses messages d'origine — « The operation could not be completed » — ne
    /// disent rien à qui regarde un téléviseur.
    private static func readableMessage(for failure: PlaybackFailure) -> String {
        switch (failure.domain, failure.code) {
        case (NSURLErrorDomain, NSURLErrorTimedOut):
            return L("Le serveur n'a pas répondu à temps. Il est peut-être occupé à transcoder.")
        case (NSURLErrorDomain, NSURLErrorCannotConnectToHost),
             (NSURLErrorDomain, NSURLErrorNetworkConnectionLost):
            return L("Connexion au serveur perdue pendant la lecture.")
        case ("CoreMediaErrorDomain", let code):
            return L("Le flux est illisible (code \(code)). Le transcodage a probablement échoué côté serveur — son journal en dira la raison.")
        default:
            return failure.description
        }
    }

    // MARK: Blocage silencieux

    /// Surveille un démarrage qui n'arrive jamais.
    ///
    /// Le cas le plus déroutant n'est pas l'erreur, c'est son absence : le serveur
    /// répond, la playlist se charge, aucun échec n'est signalé, et pourtant rien
    /// ne s'affiche. `reasonForWaitingToPlay` nomme alors ce que le lecteur attend,
    /// et le journal d'erreurs révèle les segments que le serveur n'a jamais
    /// produits.
    func watchForStalledStart() {
        startWatchdog?.cancel()
        startWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.startTimeout))
            guard !Task.isCancelled, let self else { return }
            guard player.timeControlStatus != .playing else { return }

            let reason = player.reasonForWaitingToPlay?.rawValue ?? "inconnue"
            jellyfinLog.error(
                "LECTURE · rien après \(Self.startTimeout, privacy: .public) s · en attente : \(reason, privacy: .public)"
            )
            if let item = player.currentItem { logErrorEntries(of: item) }

            markFailed(L("La lecture n'a pas démarré au bout de \(Int(Self.startTimeout)) secondes. Le serveur accepte la demande mais ne délivre pas le flux — son transcodage a probablement échoué pour ce fichier."))
        }
    }

    func cancelStartWatchdog() {
        startWatchdog?.cancel()
        startWatchdog = nil
    }

    /// Large : un transcodage qui démarre à froid sur un gros fichier peut mettre
    /// un long moment avant de produire son premier segment.
    static var startTimeout: Double { 30 }
}
