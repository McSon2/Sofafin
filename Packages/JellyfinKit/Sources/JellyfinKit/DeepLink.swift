import Foundation

/// Liens internes de Sofafin.
///
/// Partagés entre l'application et l'extension Top Shelf : c'est le seul canal par
/// lequel l'étagère du haut peut demander une lecture ou l'ouverture d'une fiche.
public enum DeepLink {
    public static let scheme = "sofafin"

    public enum Destination: Equatable, Sendable {
        case play(itemId: String)
        case details(itemId: String)
    }

    public static func play(_ itemId: String) -> URL {
        URL(string: "\(scheme)://play/\(itemId)")!
    }

    public static func details(_ itemId: String) -> URL {
        URL(string: "\(scheme)://item/\(itemId)")!
    }

    public static func destination(from url: URL) -> Destination? {
        guard url.scheme == scheme else { return nil }
        // « sofafin://play/<id> » : l'hôte porte le verbe, le chemin l'identifiant.
        let identifier = url.pathComponents.filter { $0 != "/" }.first
        guard let identifier, !identifier.isEmpty else { return nil }

        switch url.host() {
        case "play": return .play(itemId: identifier)
        case "item": return .details(itemId: identifier)
        default: return nil
        }
    }
}
