import Foundation
import OSLog

/// Journal des échanges avec le serveur. À suivre pendant un test avec :
/// `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.maximesaltet.sofafin"'`
public let jellyfinLog = Logger(subsystem: "com.maximesaltet.sofafin", category: "api")

// MARK: - Identité du client

/// Ce que Jellyfin voit dans son panneau « Appareils » et ses sessions actives.
public struct ClientIdentity: Sendable, Hashable {
    public let name: String
    public let version: String
    public let deviceName: String
    public let deviceId: String

    public init(name: String, version: String, deviceName: String, deviceId: String) {
        self.name = name
        self.version = version
        self.deviceName = deviceName
        self.deviceId = deviceId
    }
}

// MARK: - Erreurs

public enum JellyfinError: LocalizedError, Sendable {
    case invalidURL(String)
    case badResponse
    case http(status: Int, body: String?)
    case unauthorized
    case decoding(String)
    case noPlayableSource

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Adresse de serveur invalide : \(value)"
        case .badResponse:
            return "Réponse inattendue du serveur."
        case .http(let status, let body):
            if status == 404 { return "Introuvable sur le serveur (404)." }
            return "Le serveur a répondu \(status)." + (body.map { " \($0)" } ?? "")
        case .unauthorized:
            return "Session expirée. Reconnecte-toi au serveur."
        case .decoding(let detail):
            return "Réponse illisible du serveur : \(detail)"
        case .noPlayableSource:
            return "Aucune source lisible pour ce média."
        }
    }
}

// MARK: - Client

/// Client HTTP Jellyfin. Immuable : changer de serveur ou de token produit une
/// nouvelle instance, ce qui le rend `Sendable` sans verrou.
public struct JellyfinClient: Sendable {
    public let baseURL: URL
    public let identity: ClientIdentity
    public let accessToken: String?
    public let userId: String?

    private let session: URLSession

    public init(
        baseURL: URL,
        identity: ClientIdentity,
        accessToken: String? = nil,
        userId: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.identity = identity
        self.accessToken = accessToken
        self.userId = userId
        self.session = session
    }

    public func authenticated(token: String, userId: String) -> JellyfinClient {
        JellyfinClient(baseURL: baseURL, identity: identity, accessToken: token, userId: userId, session: session)
    }

    // MARK: En-tête d'autorisation

    /// Jellyfin attend un en-tête `Authorization` au format `MediaBrowser` avec les
    /// paramètres entre guillemets — c'est aussi lui qui porte le token une fois connecté.
    var authorizationHeader: String {
        var parts = [
            "Client=\"\(identity.name)\"",
            "Device=\"\(identity.deviceName)\"",
            "DeviceId=\"\(identity.deviceId)\"",
            "Version=\"\(identity.version)\""
        ]
        if let accessToken { parts.append("Token=\"\(accessToken)\"") }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    // MARK: Construction de requêtes

    func url(path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw JellyfinError.invalidURL(path)
        }
        let cleaned = query.filter { $0.value?.isEmpty == false }
        if !cleaned.isEmpty { components.queryItems = cleaned }
        guard let url = components.url else { throw JellyfinError.invalidURL(path) }
        return url
    }

    private func request(_ url: URL, method: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 20
        return request
    }

    @discardableResult
    private func perform(_ request: URLRequest) async throws -> Data {
        let path = request.url?.path ?? "?"
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Une annulation n'est pas une panne : elle survient normalement quand
            // une vue disparaît avant la fin de ses requêtes. La signaler comme
            // erreur noierait les vraies dans le bruit.
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                jellyfinLog.debug("Requête \(path, privacy: .public) annulée")
            } else {
                jellyfinLog.error("Requête \(path, privacy: .public) échouée : \(error.localizedDescription, privacy: .public)")
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw JellyfinError.badResponse }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            jellyfinLog.error("Requête \(path, privacy: .public) refusée (\(http.statusCode))")
            throw JellyfinError.unauthorized
        default:
            let body = String(data: data.prefix(300), encoding: .utf8)
            jellyfinLog.error("Requête \(path, privacy: .public) → \(http.statusCode) \(body ?? "", privacy: .public)")
            throw JellyfinError.http(status: http.statusCode, body: body)
        }
    }

    // MARK: Verbes

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let data = try await perform(request(try url(path: path, query: query), method: "GET"))
        return try Self.decode(data)
    }

    func post<T: Decodable, Body: Encodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        body: Body?,
        as type: T.Type = T.self
    ) async throws -> T {
        let payload = try body.map { try Self.encoder.encode($0) }
        let data = try await perform(request(try url(path: path, query: query), method: "POST", body: payload))
        return try Self.decode(data)
    }

    func post<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        try await post(path, query: query, body: Optional<EmptyResponse>.none, as: type)
    }

    func postVoid<Body: Encodable>(_ path: String, query: [URLQueryItem] = [], body: Body?) async throws {
        let payload = try body.map { try Self.encoder.encode($0) }
        try await perform(request(try url(path: path, query: query), method: "POST", body: payload))
    }

    func postVoid(_ path: String, query: [URLQueryItem] = []) async throws {
        try await postVoid(path, query: query, body: Optional<EmptyResponse>.none)
    }

    func deleteVoid(_ path: String, query: [URLQueryItem] = []) async throws {
        try await perform(request(try url(path: path, query: query), method: "DELETE"))
    }

    // MARK: Codage

    static let encoder = JSONEncoder()

    static func decode<T: Decodable>(_ data: Data) throws -> T {
        // Réponse vide sur un endpoint typé `EmptyResponse`.
        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            jellyfinLog.error("Décodage de \(String(describing: T.self), privacy: .public) impossible : \(String(describing: error), privacy: .public)")
            throw JellyfinError.decoding(String(describing: error))
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = parseJellyfinDate(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Date illisible : \(raw)"
            )
        }
        return decoder
    }()

    /// .NET sérialise ses dates avec sept décimales de seconde
    /// (`2024-03-15T21:04:11.7830000Z`). `ISO8601DateFormatter` n'en accepte que
    /// trois et rejette tout le reste — ce qui ferait échouer le décodage de
    /// n'importe quel item portant une date. On ramène donc la fraction à trois
    /// chiffres avant de la lui confier.
    static func parseJellyfinDate(_ raw: String) -> Date? {
        if let date = isoWithFraction.date(from: raw) ?? isoPlain.date(from: raw) { return date }

        guard let dotIndex = raw.firstIndex(of: ".") else { return nil }
        let fractionStart = raw.index(after: dotIndex)
        guard let fractionEnd = raw[fractionStart...].firstIndex(where: { !$0.isNumber }) else {
            return nil
        }
        let truncated = raw.replacingCharacters(
            in: fractionStart..<fractionEnd,
            with: String(raw[fractionStart..<fractionEnd].prefix(3))
        )
        return isoWithFraction.date(from: truncated) ?? isoPlain.date(from: truncated)
    }

    // `nonisolated(unsafe)` : configurés une fois puis seulement lus. Foundation les
    // documente comme utilisables en concurrence, mais ne les déclare pas `Sendable`.
    nonisolated(unsafe) private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

public struct EmptyResponse: Codable, Sendable {
    public init() {}
}
