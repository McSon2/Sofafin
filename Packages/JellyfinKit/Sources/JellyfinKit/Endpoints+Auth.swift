import Foundation

// MARK: - Découverte du serveur

public extension JellyfinClient {
    /// Vérifie qu'une adresse pointe bien sur un Jellyfin, sans authentification.
    func publicSystemInfo() async throws -> PublicSystemInfo {
        try await get("System/Info/Public")
    }

    /// Normalise une saisie utilisateur (« 192.168.1.10:8096 », « jellyfin.exemple.fr »)
    /// en URL exploitable, et teste https puis http quand le schéma est absent.
    static func resolveServerURL(from input: String) async -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidates: [String]
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            candidates = [trimmed]
        } else if trimmed.contains(":") {
            // Un port explicite est presque toujours du HTTP en réseau local.
            candidates = ["http://\(trimmed)", "https://\(trimmed)"]
        } else {
            candidates = ["https://\(trimmed)", "http://\(trimmed)", "http://\(trimmed):8096"]
        }

        let identity = ClientIdentity(name: "Jellyflix", version: "0.1.0", deviceName: "probe", deviceId: "probe")
        for candidate in candidates {
            guard var url = URL(string: candidate) else { continue }
            if url.path.hasSuffix("/") {
                url = url.deletingLastPathComponent()
            }
            let client = JellyfinClient(baseURL: url, identity: identity)
            if let info = try? await client.publicSystemInfo(), info.version != nil {
                return url
            }
        }
        return nil
    }
}

// MARK: - Authentification classique

private struct AuthenticateByNameRequest: Encodable {
    let username: String
    let password: String

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case password = "Pw"
    }
}

public extension JellyfinClient {
    func authenticate(username: String, password: String) async throws -> AuthenticationResult {
        try await post(
            "Users/AuthenticateByName",
            body: AuthenticateByNameRequest(username: username, password: password),
            as: AuthenticationResult.self
        )
    }

    func currentUser() async throws -> JellyfinUser {
        try await get("Users/Me")
    }

    /// Invalide le token côté serveur. Silencieux en cas d'échec : on se déconnecte quand même.
    func logout() async {
        try? await postVoid("Sessions/Logout")
    }
}

// MARK: - Quick Connect

private struct QuickConnectSecret: Encodable {
    let secret: String

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
    }
}

public extension JellyfinClient {
    func quickConnectEnabled() async throws -> Bool {
        try await get("QuickConnect/Enabled", as: Bool.self)
    }

    /// Démarre une session Quick Connect : le code retourné est à saisir dans
    /// l'interface web de Jellyfin depuis un appareil déjà connecté.
    func quickConnectInitiate() async throws -> QuickConnectState {
        try await post("QuickConnect/Initiate", as: QuickConnectState.self)
    }

    func quickConnectState(secret: String) async throws -> QuickConnectState {
        try await get("QuickConnect/Connect", query: [URLQueryItem(name: "secret", value: secret)])
    }

    func authenticateWithQuickConnect(secret: String) async throws -> AuthenticationResult {
        try await post(
            "Users/AuthenticateWithQuickConnect",
            body: QuickConnectSecret(secret: secret),
            as: AuthenticationResult.self
        )
    }
}
