import Foundation

// MARK: - Profil d'appareil

/// Décrit à Jellyfin ce qu'AVPlayer sait lire. Le serveur s'en sert pour choisir
/// entre lecture directe, remux (« direct stream ») et réencodage complet.
///
/// Le point important : AVFoundation ne lit pas le conteneur Matroska, qui domine
/// une médiathèque de films. En déclarant HLS + fMP4 en profil de transcodage, on
/// laisse Jellyfin **remuxer** ces fichiers sans toucher aux codecs — quelques pour
/// cent de CPU au lieu d'un réencodage complet.
public enum DeviceProfileFactory {

    public static func appleTV(maxBitrate: Int = 120_000_000) -> DeviceProfile {
        DeviceProfile(
            name: "Jellyflix Apple TV",
            maxStreamingBitrate: maxBitrate,
            maxStaticBitrate: maxBitrate,
            directPlayProfiles: [
                DirectPlayProfile(
                    container: "mp4,m4v,mov",
                    audioCodec: "aac,ac3,eac3,alac,mp3,flac,opus",
                    videoCodec: "h264,hevc,dvhe,dvh1,hvc1,mpeg4",
                    mediaType: "Video"
                ),
                DirectPlayProfile(
                    container: "mp3,aac,m4a,flac,alac,wav",
                    audioCodec: nil,
                    videoCodec: nil,
                    mediaType: "Audio"
                )
            ],
            transcodingProfiles: [
                TranscodingProfile(
                    container: "mp4",
                    mediaType: "Video",
                    videoCodec: "hevc,h264",
                    audioCodec: "aac,ac3,eac3",
                    streamProtocol: "hls",
                    context: "Streaming",
                    maxAudioChannels: "6",
                    minSegments: 2,
                    // Couper ailleurs que sur une image clé produit des segments que
                    // le lecteur refuse : les clients de référence laissent ffmpeg
                    // s'aligner sur les images clés.
                    breakOnNonKeyFrames: false,
                    enableSubtitlesInManifest: true,
                    copyTimestamps: false,
                    estimateContentLength: false,
                    transcodeSeekInfo: "Auto"
                ),
                TranscodingProfile(
                    container: "aac",
                    mediaType: "Audio",
                    videoCodec: nil,
                    audioCodec: "aac",
                    streamProtocol: "http",
                    context: "Streaming",
                    maxAudioChannels: "2",
                    minSegments: nil,
                    breakOnNonKeyFrames: nil,
                    enableSubtitlesInManifest: nil,
                    copyTimestamps: nil,
                    estimateContentLength: nil,
                    transcodeSeekInfo: nil
                )
            ],
            subtitleProfiles: [
                // Livrés dans le flux HLS quand on transcode…
                SubtitleProfile(format: "vtt", method: "Hls"),
                // …et en fichier séparé quand on lit en direct.
                SubtitleProfile(format: "vtt", method: "External"),
                SubtitleProfile(format: "srt", method: "External"),
                SubtitleProfile(format: "subrip", method: "External"),
                SubtitleProfile(format: "ass", method: "Encode"),
                SubtitleProfile(format: "ssa", method: "Encode"),
                SubtitleProfile(format: "pgssub", method: "Encode"),
                SubtitleProfile(format: "dvdsub", method: "Encode"),
                SubtitleProfile(format: "dvbsub", method: "Encode")
            ]
        )
    }
}

public struct DeviceProfile: Codable, Sendable {
    public let name: String
    public let maxStreamingBitrate: Int
    public let maxStaticBitrate: Int
    public let directPlayProfiles: [DirectPlayProfile]
    public let transcodingProfiles: [TranscodingProfile]
    public let subtitleProfiles: [SubtitleProfile]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case maxStaticBitrate = "MaxStaticBitrate"
        case directPlayProfiles = "DirectPlayProfiles"
        case transcodingProfiles = "TranscodingProfiles"
        case subtitleProfiles = "SubtitleProfiles"
    }
}

public struct DirectPlayProfile: Codable, Sendable {
    public let container: String
    public let audioCodec: String?
    public let videoCodec: String?
    public let mediaType: String

    enum CodingKeys: String, CodingKey {
        case container = "Container"
        case audioCodec = "AudioCodec"
        case videoCodec = "VideoCodec"
        case mediaType = "Type"
    }
}

public struct TranscodingProfile: Codable, Sendable {
    public let container: String
    public let mediaType: String
    public let videoCodec: String?
    public let audioCodec: String?
    public let streamProtocol: String
    public let context: String
    public let maxAudioChannels: String?
    public let minSegments: Int?
    public let breakOnNonKeyFrames: Bool?
    public let enableSubtitlesInManifest: Bool?
    public let copyTimestamps: Bool?
    public let estimateContentLength: Bool?
    public let transcodeSeekInfo: String?

    enum CodingKeys: String, CodingKey {
        case container = "Container"
        case mediaType = "Type"
        case videoCodec = "VideoCodec"
        case audioCodec = "AudioCodec"
        case streamProtocol = "Protocol"
        case context = "Context"
        case maxAudioChannels = "MaxAudioChannels"
        case minSegments = "MinSegments"
        case breakOnNonKeyFrames = "BreakOnNonKeyFrames"
        case enableSubtitlesInManifest = "EnableSubtitlesInManifest"
        case copyTimestamps = "CopyTimestamps"
        case estimateContentLength = "EstimateContentLength"
        case transcodeSeekInfo = "TranscodeSeekInfo"
    }
}

public struct SubtitleProfile: Codable, Sendable {
    public let format: String
    public let method: String

    enum CodingKeys: String, CodingKey {
        case format = "Format"
        case method = "Method"
    }
}

// MARK: - Requête de lecture

private struct PlaybackInfoRequest: Encodable {
    let userId: String?
    let maxStreamingBitrate: Int
    let startTimeTicks: Int64
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let mediaSourceId: String?
    let deviceProfile: DeviceProfile
    let enableDirectPlay: Bool
    let enableDirectStream: Bool
    let enableTranscoding: Bool
    let allowVideoStreamCopy: Bool
    let allowAudioStreamCopy: Bool
    let autoOpenLiveStream: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "UserId"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case startTimeTicks = "StartTimeTicks"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case mediaSourceId = "MediaSourceId"
        case deviceProfile = "DeviceProfile"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case allowVideoStreamCopy = "AllowVideoStreamCopy"
        case allowAudioStreamCopy = "AllowAudioStreamCopy"
        case autoOpenLiveStream = "AutoOpenLiveStream"
    }
}

/// Tout ce dont le lecteur a besoin pour démarrer.
public struct PlaybackPlan: Sendable {
    public let url: URL
    public let item: MediaItem
    public let mediaSource: MediaSource
    public let playSessionId: String
    public let startTime: Double
    public let method: PlayMethod
    /// Sous-titres à charger séparément (uniquement en lecture directe).
    public let externalSubtitles: [ExternalSubtitle]

    public enum PlayMethod: String, Sendable {
        case directPlay = "DirectPlay"
        case directStream = "DirectStream"
        case transcode = "Transcode"

        public var label: String {
            switch self {
            case .directPlay: return "Lecture directe"
            case .directStream: return "Remux"
            case .transcode: return "Transcodage"
            }
        }
    }
}

public struct ExternalSubtitle: Sendable, Identifiable, Hashable {
    public let id: Int
    public let url: URL
    public let language: String?
    public let title: String
    public let isDefault: Bool
    public let isForced: Bool
}

public extension JellyfinClient {

    /// Négocie la lecture avec le serveur puis construit l'URL à donner à AVPlayer.
    func playbackPlan(
        for item: MediaItem,
        startTime: Double = 0,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        mediaSourceId: String? = nil,
        maxBitrate: Int = 120_000_000
    ) async throws -> PlaybackPlan {
        let request = PlaybackInfoRequest(
            userId: userId,
            maxStreamingBitrate: maxBitrate,
            startTimeTicks: startTime.ticksFromSeconds,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            mediaSourceId: mediaSourceId,
            deviceProfile: DeviceProfileFactory.appleTV(maxBitrate: maxBitrate),
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            allowVideoStreamCopy: true,
            allowAudioStreamCopy: true,
            autoOpenLiveStream: true
        )

        let response: PlaybackInfoResponse = try await post(
            "Items/\(item.id)/PlaybackInfo",
            query: [URLQueryItem(name: "userId", value: userId)],
            body: request,
            as: PlaybackInfoResponse.self
        )

        guard let source = response.mediaSources?.first(where: { $0.id == mediaSourceId })
                ?? response.mediaSources?.first else {
            throw JellyfinError.noPlayableSource
        }
        let playSessionId = response.playSessionId ?? UUID().uuidString

        // Le serveur a tranché : une URL de transcodage signifie qu'il refuse la lecture directe.
        if let transcodingPath = source.transcodingUrl {
            guard let url = URL(string: transcodingPath, relativeTo: baseURL)?.absoluteURL else {
                throw JellyfinError.invalidURL(transcodingPath)
            }
            return PlaybackPlan(
                url: url,
                item: item,
                mediaSource: source,
                playSessionId: playSessionId,
                startTime: startTime,
                method: source.supportsDirectStream == true ? .directStream : .transcode,
                externalSubtitles: []
            )
        }

        guard source.supportsDirectPlay == true || source.supportsDirectStream == true else {
            throw JellyfinError.noPlayableSource
        }

        let container = source.container.map { ".\($0)" } ?? ""
        let streamURL = try url(path: "Videos/\(item.id)/stream\(container)", query: [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: source.id ?? item.id),
            URLQueryItem(name: "playSessionId", value: playSessionId),
            URLQueryItem(name: "deviceId", value: identity.deviceId),
            URLQueryItem(name: "api_key", value: accessToken)
        ])

        return PlaybackPlan(
            url: streamURL,
            item: item,
            mediaSource: source,
            playSessionId: playSessionId,
            startTime: startTime,
            method: .directPlay,
            externalSubtitles: externalSubtitles(from: source)
        )
    }

    private func externalSubtitles(from source: MediaSource) -> [ExternalSubtitle] {
        (source.mediaStreams ?? [])
            .filter { $0.isSubtitle && $0.deliveryMethod == "External" }
            .compactMap { stream in
                guard let index = stream.index, let path = stream.deliveryUrl,
                      let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { return nil }
                return ExternalSubtitle(
                    id: index,
                    url: url,
                    language: stream.language,
                    title: stream.displayTitle ?? stream.language ?? "Sous-titres",
                    isDefault: stream.isDefault ?? false,
                    isForced: stream.isForced ?? false
                )
            }
    }
}

// MARK: - Rapport de lecture

private struct PlaybackReport: Encodable {
    let itemId: String
    let mediaSourceId: String?
    let playSessionId: String
    let positionTicks: Int64
    let isPaused: Bool?
    let canSeek: Bool?
    let playMethod: String?
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case canSeek = "CanSeek"
        case playMethod = "PlayMethod"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
    }
}

public extension JellyfinClient {

    func reportPlaybackStart(_ plan: PlaybackPlan, audioStreamIndex: Int? = nil, subtitleStreamIndex: Int? = nil) async {
        let report = PlaybackReport(
            itemId: plan.item.id,
            mediaSourceId: plan.mediaSource.id,
            playSessionId: plan.playSessionId,
            positionTicks: plan.startTime.ticksFromSeconds,
            isPaused: false,
            canSeek: true,
            playMethod: plan.method.rawValue,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex
        )
        try? await postVoid("Sessions/Playing", body: report)
    }

    func reportPlaybackProgress(_ plan: PlaybackPlan, position: Double, isPaused: Bool) async {
        let report = PlaybackReport(
            itemId: plan.item.id,
            mediaSourceId: plan.mediaSource.id,
            playSessionId: plan.playSessionId,
            positionTicks: position.ticksFromSeconds,
            isPaused: isPaused,
            canSeek: true,
            playMethod: plan.method.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        try? await postVoid("Sessions/Playing/Progress", body: report)
    }

    /// À appeler impérativement en fin de lecture : c'est ce qui enregistre la position
    /// de reprise et libère le processus de transcodage côté serveur.
    func reportPlaybackStopped(_ plan: PlaybackPlan, position: Double) async {
        let report = PlaybackReport(
            itemId: plan.item.id,
            mediaSourceId: plan.mediaSource.id,
            playSessionId: plan.playSessionId,
            positionTicks: position.ticksFromSeconds,
            isPaused: nil,
            canSeek: nil,
            playMethod: nil,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        try? await postVoid("Sessions/Playing/Stopped", body: report)
    }
}
