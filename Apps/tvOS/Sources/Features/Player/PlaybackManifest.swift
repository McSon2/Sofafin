import AVFoundation
import Foundation
import JellyfinKit
import UniformTypeIdentifiers

/// Réécrit la playlist maître avant qu'AVPlayer ne la lise.
///
/// Jellyfin propose toujours trois variantes pour un film HDR, toutes au même
/// débit : la première conserve la plage d'origine et lui permet de **recopier**
/// le flux, les deux suivantes sont des replis convertis en SDR qu'il ne peut
/// produire qu'en réencodant l'image. L'ordre dit lequel vaut mieux, mais rien
/// n'oblige le lecteur à le suivre, et il ne le suit pas :
///
/// — depuis tvOS 13 il choisit la variante qui promet le meilleur démarrage,
///   et à débit égal ce choix est arbitraire ;
/// — un film HDR10+ porte `SUPPLEMENTAL-CODECS="…/cdm4"`, que le lecteur ne
///   reconnaît pas : il déclare alors la première variante inéligible et se
///   rabat sur un repli, donc sur un réencodage 4K complet. `startsOnFirstEligibleVariant`
///   n'y change rien, précisément parce que l'inéligibilité est le problème.
///
/// Ne rien laisser d'autre que la bonne variante supprime le choix. L'étiquette
/// `SUPPLEMENTAL-CODECS` part avec : elle ne décrit qu'une surcouche de
/// métadonnées, et le flux qu'elle accompagne reste du HEVC Main 10 PQ que
/// l'Apple TV affiche en HDR10 — ce que fait n'importe quel téléviseur sans
/// HDR10+. Le pire qu'elle puisse produire, c'est ce refus.
///
/// Seule la playlist maître passe par ici. Les URI qu'elle contient sont
/// réécrites en absolu, si bien que la variante, les segments et les sous-titres
/// repartent en HTTP direct, sans détour par ce délégué.
final class PlaybackManifestRewriter: NSObject, AVAssetResourceLoaderDelegate {

    /// Schémas d'emprunt : AVFoundation n'appelle le délégué que pour les URL
    /// dont il ne sait rien. Il en faut deux, un par schéma d'origine — un
    /// serveur exposé derrière un domaine est en HTTPS, et le rappeler en clair
    /// ferait échouer la requête sans que rien ne l'explique.
    private static let schemes = ["http": "sofafin-hls", "https": "sofafin-hlss"]

    private let session: URLSession
    private let queue = DispatchQueue(label: "fr.sofafin.manifeste")

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        super.init()
    }

    /// Prépare l'élément à lire, en interceptant sa playlist maître.
    ///
    /// Une adresse dont le schéma n'est ni HTTP ni HTTPS est rendue telle quelle :
    /// mieux vaut une lecture non interceptée qu'une adresse que personne ne sait
    /// résoudre.
    func asset(for url: URL) -> AVURLAsset {
        guard let scheme = url.scheme.flatMap({ Self.schemes[$0] }),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return AVURLAsset(url: url)
        }
        components.scheme = scheme
        guard let borrowed = components.url else { return AVURLAsset(url: url) }
        let asset = AVURLAsset(url: borrowed)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let borrowed = loadingRequest.request.url,
              let original = Self.httpURL(from: borrowed) else { return false }

        session.dataTask(with: original) { data, _, error in
            guard let data, let manifest = String(data: data, encoding: .utf8) else {
                loadingRequest.finishLoading(with: error ?? URLError(.cannotParseResponse))
                return
            }
            let payload = Data(
                HLSManifest.keepingOnlyFirstVariant(of: manifest, relativeTo: original).utf8
            )

            if let information = loadingRequest.contentInformationRequest {
                // Un **type uniforme**, pas un type MIME : la documentation
                // d'AVFoundation prévient qu'un type que le système ne reconnaît
                // pas comme un format lisible fait échouer la lecture. Servir
                // `application/vnd.apple.mpegurl` ici donne un
                // AVFoundationErrorDomain -11868 sans autre explication.
                information.contentType = UTType.m3uPlaylist.identifier
                information.contentLength = Int64(payload.count)
                information.isByteRangeAccessSupported = true
            }

            if let request = loadingRequest.dataRequest {
                // Le lecteur demande une plage, pas forcément la totalité : lui
                // répondre depuis le début décalerait tout ce qui suit.
                let offset = Int(request.currentOffset)
                guard offset <= payload.count else {
                    loadingRequest.finishLoading(with: URLError(.badServerResponse))
                    return
                }
                let length = request.requestsAllDataToEndOfResource
                    ? payload.count - offset
                    : min(request.requestedLength, payload.count - offset)
                request.respond(with: payload.subdata(in: offset ..< offset + length))
            }

            loadingRequest.finishLoading()
        }.resume()

        return true
    }

    // MARK: Réécriture

    /// Rend son schéma d'origine à une URL empruntée.
    private static func httpURL(from url: URL) -> URL? {
        guard let borrowed = url.scheme,
              let origin = schemes.first(where: { $0.value == borrowed })?.key,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = origin
        return components.url
    }
}
