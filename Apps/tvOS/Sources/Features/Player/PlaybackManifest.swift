import Foundation
import JellyfinKit
import os

/// Résout la playlist maître en l'adresse de sa première variante.
///
/// Jellyfin en propose trois pour un film HDR, toutes au même débit : la
/// première garde la plage d'origine et lui permet de **recopier** le flux, les
/// deux suivantes sont des replis convertis en SDR qu'il ne peut produire qu'en
/// réencodant l'image — mesuré 1,88× le temps réel contre 141× en copie. L'ordre
/// dit laquelle vaut mieux, mais le lecteur ne le suit pas : depuis tvOS 13 il
/// retient celle qui promet le meilleur démarrage, ce qui à débit égal revient à
/// tirer au sort.
///
/// Lui donner l'adresse de la variante plutôt que celle du catalogue le prive du
/// choix. Le reste ne change pas : c'est une playlist servie par Jellyfin, sur le
/// même chemin réseau que tout le reste de l'application.
///
/// Deux autres voies ont été essayées et abandonnées, l'une et l'autre pour la
/// même raison — elles supposent de servir la playlist soi-même, et le lecteur
/// de l'Apple TV ne la lit pas dans le processus de l'application :
/// `AVAssetResourceLoader` échoue sans rien expliquer, et un serveur sur la
/// boucle locale fonctionne sur un Mac mais pas sur l'appareil.
///
/// Ce que cela coûte : les pistes de sous-titres déclarées dans la playlist
/// maître ne suivent pas. Elles se redemandent au serveur, qui régénère le flux
/// avec la piste voulue.
enum PlaybackManifest {

    /// Renvoie l'adresse à confier au lecteur.
    ///
    /// Rend l'adresse d'origine si quoi que ce soit échoue : une lecture où le
    /// lecteur choisit mal vaut mieux qu'une lecture qui n'ouvre pas.
    static func resolved(_ master: URL) async -> URL {
        guard master.pathExtension == "m3u8" else { return master }
        do {
            let (data, _) = try await URLSession.shared.data(from: master)
            guard let manifest = String(data: data, encoding: .utf8),
                  let variant = HLSManifest.firstVariantURL(in: manifest, relativeTo: master) else {
                return master
            }
            return variant
        } catch {
            jellyfinLog.error(
                "LECTURE · variante non résolue, le lecteur choisira seul : \(error.localizedDescription, privacy: .public)"
            )
            return master
        }
    }
}
