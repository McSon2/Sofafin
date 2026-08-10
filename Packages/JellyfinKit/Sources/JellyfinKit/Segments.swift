import Foundation

// MARK: - Segments de média

/// Nature d'une portion repérée dans un média. Jellyfin 10.10+ les expose
/// nativement ; ce sont elles qui alimentent le bouton « Passer l'intro ».
public enum MediaSegmentKind: String, Codable, Sendable, Hashable {
    case intro = "Intro"
    case outro = "Outro"
    case recap = "Recap"
    case preview = "Preview"
    case commercial = "Commercial"
    case unknown = "Unknown"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaSegmentKind(rawValue: raw) ?? .unknown
    }

    /// Texte du bouton flottant. Il doit dire ce que le saut fait sauter :
    /// « Passer » seul laisse l'utilisateur deviner ce qu'il perd.
    public var skipLabel: String {
        switch self {
        case .intro: return "Passer l'intro"
        case .outro: return "Passer le générique"
        case .recap: return "Passer le résumé"
        case .preview: return "Passer la bande-annonce"
        case .commercial: return "Passer la publicité"
        case .unknown: return "Passer ce passage"
        }
    }

    /// Un générique de fin ne se « passe » pas comme une intro : le sauter revient
    /// à terminer l'épisode. Le lecteur s'en sert pour enchaîner plutôt que de
    /// déposer l'utilisateur sur les dernières secondes noires.
    public var endsContent: Bool { self == .outro }
}

public struct MediaSegment: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let itemId: String?
    public let kind: MediaSegmentKind
    public let startTicks: Int64?
    public let endTicks: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case itemId = "ItemId"
        case kind = "Type"
        case startTicks = "StartTicks"
        case endTicks = "EndTicks"
    }

    public var start: Double { (startTicks ?? 0).secondsFromTicks }
    public var end: Double { (endTicks ?? 0).secondsFromTicks }

    /// Un segment n'est exploitable que s'il dure assez pour qu'un saut ait du sens.
    /// Les détecteurs produisent parfois des bornes dégénérées.
    public var isUsable: Bool { end - start >= 2 }

    public func contains(_ position: Double) -> Bool {
        position >= start && position < end
    }
}

private struct MediaSegmentsResponse: Decodable {
    let items: [MediaSegment]?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

public extension JellyfinClient {

    /// Segments d'un média (intro, résumé, générique…).
    ///
    /// Le renseignement de ces bornes dépend d'un fournisseur côté serveur : une
    /// médiathèque qui n'en a aucun répond simplement une liste vide, et l'absence
    /// de segments n'est jamais une erreur de lecture. On absorbe donc l'échec ici
    /// plutôt que de le faire remonter au lecteur.
    func mediaSegments(itemId: String) async -> [MediaSegment] {
        // `includeSegmentTypes` est un **tableau** : il se transmet en répétant le
        // paramètre. Les joindre par des virgules — la convention de la plupart
        // des autres endpoints Jellyfin — fait répondre 400 à celui-ci.
        let types: [MediaSegmentKind] = [.intro, .outro, .recap, .preview, .commercial]
        do {
            let response: MediaSegmentsResponse = try await get(
                "MediaSegments/\(itemId)",
                query: types.map { URLQueryItem(name: "includeSegmentTypes", value: $0.rawValue) }
            )
            return (response.items ?? []).filter(\.isUsable).sorted { $0.start < $1.start }
        } catch {
            jellyfinLog.debug("Aucun segment pour \(itemId, privacy: .public) : \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

// MARK: - Sélection d'un segment

public extension Array where Element == MediaSegment {

    /// Segment couvrant la position courante, s'il en existe un.
    func active(at position: Double) -> MediaSegment? {
        first { $0.contains(position) }
    }

    /// Début du générique de fin, qui sert de repère pour proposer la suite.
    var outroStart: Double? {
        first { $0.kind == .outro }?.start
    }
}
