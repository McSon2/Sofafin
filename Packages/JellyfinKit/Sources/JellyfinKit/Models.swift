import Foundation

// MARK: - Constantes du domaine Jellyfin

/// Jellyfin exprime toutes les durées en « ticks » .NET : 10 000 000 ticks = 1 seconde.
public let ticksPerSecond: Int64 = 10_000_000

public extension Int64 {
    var secondsFromTicks: Double { Double(self) / Double(ticksPerSecond) }
}

public extension Double {
    var ticksFromSeconds: Int64 { Int64(self * Double(ticksPerSecond)) }
}

// MARK: - Types d'items

public enum ItemKind: String, Codable, Sendable {
    case movie = "Movie"
    case series = "Series"
    case season = "Season"
    case episode = "Episode"
    case boxSet = "BoxSet"
    case collectionFolder = "CollectionFolder"
    case folder = "Folder"
    case person = "Person"
    case video = "Video"
    case trailer = "Trailer"
    case audio = "Audio"
    case musicAlbum = "MusicAlbum"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemKind(rawValue: raw) ?? .unknown
    }
}

/// Type de collection d'une vue utilisateur (`/UserViews`).
public enum CollectionKind: String, Codable, Sendable {
    case movies, tvshows, music, books, homevideos, musicvideos, playlists
    case boxsets, livetv, folders
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CollectionKind(rawValue: raw.lowercased()) ?? .unknown
    }
}

// MARK: - Item

public struct MediaItem: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let originalTitle: String?
    public let overview: String?
    public let taglines: [String]?
    public let type: ItemKind?
    public let collectionType: CollectionKind?

    public let productionYear: Int?
    public let premiereDate: Date?
    public let communityRating: Double?
    public let criticRating: Double?
    public let officialRating: String?
    public let runTimeTicks: Int64?
    public let genres: [String]?

    public let imageTags: [String: String]?
    public let backdropImageTags: [String]?
    public let parentBackdropItemId: String?
    public let parentBackdropImageTags: [String]?
    public let parentThumbItemId: String?
    public let parentThumbImageTag: String?
    public let seriesPrimaryImageTag: String?

    public let userData: UserItemData?

    // Hiérarchie séries
    public let seriesName: String?
    public let seriesId: String?
    public let seasonId: String?
    public let seasonName: String?
    public let indexNumber: Int?
    public let parentIndexNumber: Int?
    public let childCount: Int?
    public let recursiveItemCount: Int?

    public let people: [Person]?
    public let studios: [NameGuidPair]?
    public let mediaSources: [MediaSource]?
    public let chapters: [ChapterInfo]?
    public let localTrailerCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case originalTitle = "OriginalTitle"
        case overview = "Overview"
        case taglines = "Taglines"
        case type = "Type"
        case collectionType = "CollectionType"
        case productionYear = "ProductionYear"
        case premiereDate = "PremiereDate"
        case communityRating = "CommunityRating"
        case criticRating = "CriticRating"
        case officialRating = "OfficialRating"
        case runTimeTicks = "RunTimeTicks"
        case genres = "Genres"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case parentBackdropItemId = "ParentBackdropItemId"
        case parentBackdropImageTags = "ParentBackdropImageTags"
        case parentThumbItemId = "ParentThumbItemId"
        case parentThumbImageTag = "ParentThumbImageTag"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case userData = "UserData"
        case seriesName = "SeriesName"
        case seriesId = "SeriesId"
        case seasonId = "SeasonId"
        case seasonName = "SeasonName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case childCount = "ChildCount"
        case recursiveItemCount = "RecursiveItemCount"
        case people = "People"
        case studios = "Studios"
        case mediaSources = "MediaSources"
        case chapters = "Chapters"
        case localTrailerCount = "LocalTrailerCount"
    }
}

/// Marqueur de chapitre tel que Jellyfin l'extrait du conteneur.
public struct ChapterInfo: Codable, Sendable, Hashable {
    public let startPositionTicks: Int64?
    public let name: String?
    public let imageTag: String?

    enum CodingKeys: String, CodingKey {
        case startPositionTicks = "StartPositionTicks"
        case name = "Name"
        case imageTag = "ImageTag"
    }

    public var start: Double { (startPositionTicks ?? 0).secondsFromTicks }
}

public extension MediaItem {
    var displayTitle: String { name ?? originalTitle ?? L("Sans titre") }

    /// Durée totale, en secondes.
    var runtime: Double? { runTimeTicks.map(\.secondsFromTicks) }

    var runtimeLabel: String? {
        guard let runtime, runtime > 0 else { return nil }
        let minutes = Int(runtime / 60)
        return minutes >= 60
            ? L("\(minutes / 60) h \(String(format: "%02d", minutes % 60))")
            : L("\(minutes) min")
    }

    /// Position de reprise en secondes, seulement si la lecture est réellement en cours
    /// (Jellyfin garde un `PlaybackPositionTicks` résiduel sur les items déjà terminés).
    var resumePosition: Double? {
        guard let ticks = userData?.playbackPositionTicks, ticks > 0,
              userData?.played != true else { return nil }
        return ticks.secondsFromTicks
    }

    var progressFraction: Double? {
        guard let position = resumePosition, let runtime, runtime > 0 else { return nil }
        return min(max(position / runtime, 0), 1)
    }

    var isPlayed: Bool { userData?.played ?? false }
    var isFavorite: Bool { userData?.isFavorite ?? false }

    /// « S02E05 » pour un épisode.
    var episodeCode: String? {
        guard type == .episode, let season = parentIndexNumber, let episode = indexNumber else { return nil }
        return String(format: "S%02dE%02d", season, episode)
    }

    /// Titre à afficher dans une rangée : les épisodes se lisent mieux sous le nom de leur série.
    var rowTitle: String {
        type == .episode ? (seriesName ?? displayTitle) : displayTitle
    }

    var rowSubtitle: String? {
        if type == .episode {
            return [episodeCode, name].compactMap(\.self).joined(separator: " · ")
        }
        // TMDb ne date pas les collections : leur année est vide une fois sur deux.
        // Leur taille dit de toute façon mieux ce qu'on s'apprête à ouvrir.
        if type == .boxSet, let count = childCount, count > 0 {
            return L("\(count) titres")
        }
        return productionYear.map(String.init)
    }
}

// MARK: - Données utilisateur

public struct UserItemData: Codable, Sendable, Hashable {
    public let playbackPositionTicks: Int64?
    public let playCount: Int?
    public let isFavorite: Bool?
    public let played: Bool?
    public let playedPercentage: Double?
    public let unplayedItemCount: Int?
    public let lastPlayedDate: Date?
    public let key: String?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
        case isFavorite = "IsFavorite"
        case played = "Played"
        case playedPercentage = "PlayedPercentage"
        case unplayedItemCount = "UnplayedItemCount"
        case lastPlayedDate = "LastPlayedDate"
        case key = "Key"
    }
}

public struct NameGuidPair: Codable, Sendable, Hashable, Identifiable {
    public let name: String?
    public let id: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
    }
}

public struct Person: Codable, Sendable, Hashable, Identifiable {
    public let id: String?
    public let name: String?
    public let role: String?
    public let type: String?
    public let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case role = "Role"
        case type = "Type"
        case primaryImageTag = "PrimaryImageTag"
    }
}

// MARK: - Résultats de requête

public struct ItemsResponse: Codable, Sendable {
    public let items: [MediaItem]?
    public let totalRecordCount: Int?
    public let startIndex: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}

// MARK: - Utilisateur et authentification

public struct JellyfinUser: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let serverId: String?
    public let primaryImageTag: String?
    public let hasPassword: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case serverId = "ServerId"
        case primaryImageTag = "PrimaryImageTag"
        case hasPassword = "HasPassword"
    }
}

public struct AuthenticationResult: Codable, Sendable {
    public let user: JellyfinUser?
    public let accessToken: String?
    public let serverId: String?

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverId = "ServerId"
    }
}

public struct QuickConnectState: Codable, Sendable {
    public let authenticated: Bool?
    public let secret: String?
    public let code: String?

    enum CodingKeys: String, CodingKey {
        case authenticated = "Authenticated"
        case secret = "Secret"
        case code = "Code"
    }
}

public struct PublicSystemInfo: Codable, Sendable {
    public let serverName: String?
    public let version: String?
    public let id: String?
    public let localAddress: String?
    public let startupWizardCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case version = "Version"
        case id = "Id"
        case localAddress = "LocalAddress"
        case startupWizardCompleted = "StartupWizardCompleted"
    }
}

// MARK: - Lecture

public struct PlaybackInfoResponse: Codable, Sendable {
    public let mediaSources: [MediaSource]?
    public let playSessionId: String?
    public let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
        case errorCode = "ErrorCode"
    }
}

public struct MediaSource: Codable, Sendable, Hashable, Identifiable {
    public let id: String?
    public let name: String?
    public let container: String?
    public let size: Int64?
    public let bitrate: Int?
    public let runTimeTicks: Int64?
    public let supportsDirectPlay: Bool?
    public let supportsDirectStream: Bool?
    public let supportsTranscoding: Bool?
    public let transcodingUrl: String?
    public let transcodingSubProtocol: String?
    public let transcodingContainer: String?
    public let mediaStreams: [MediaStream]?
    public let defaultAudioStreamIndex: Int?
    public let defaultSubtitleStreamIndex: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case container = "Container"
        case size = "Size"
        case bitrate = "Bitrate"
        case runTimeTicks = "RunTimeTicks"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case transcodingUrl = "TranscodingUrl"
        case transcodingSubProtocol = "TranscodingSubProtocol"
        case transcodingContainer = "TranscodingContainer"
        case mediaStreams = "MediaStreams"
        case defaultAudioStreamIndex = "DefaultAudioStreamIndex"
        case defaultSubtitleStreamIndex = "DefaultSubtitleStreamIndex"
    }
}

public struct MediaStream: Codable, Sendable, Hashable {
    public let index: Int?
    public let type: String?
    public let codec: String?
    public let language: String?
    public let displayTitle: String?
    public let isDefault: Bool?
    public let isForced: Bool?
    public let isExternal: Bool?
    public let isTextSubtitleStream: Bool?
    public let deliveryUrl: String?
    public let deliveryMethod: String?
    public let width: Int?
    public let height: Int?
    public let channels: Int?
    public let videoRangeType: String?

    enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case codec = "Codec"
        case language = "Language"
        case displayTitle = "DisplayTitle"
        case isDefault = "IsDefault"
        case isForced = "IsForced"
        case isExternal = "IsExternal"
        case isTextSubtitleStream = "IsTextSubtitleStream"
        case deliveryUrl = "DeliveryUrl"
        case deliveryMethod = "DeliveryMethod"
        case width = "Width"
        case height = "Height"
        case channels = "Channels"
        case videoRangeType = "VideoRangeType"
    }

    public var isVideo: Bool { type == "Video" }
    public var isAudio: Bool { type == "Audio" }
    public var isSubtitle: Bool { type == "Subtitle" }
}
