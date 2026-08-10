import Foundation

/// Ce qu'il faut conserver entre deux lancements pour reprendre la session.
public struct StoredCredentials: Codable, Sendable, Equatable {
    public let serverURL: URL
    public let serverName: String?
    public let userId: String
    public let userName: String?
    public let accessToken: String
    public let deviceId: String

    public init(
        serverURL: URL,
        serverName: String?,
        userId: String,
        userName: String?,
        accessToken: String,
        deviceId: String
    ) {
        self.serverURL = serverURL
        self.serverName = serverName
        self.userId = userId
        self.userName = userName
        self.accessToken = accessToken
        self.deviceId = deviceId
    }
}

/// Stockage de la session.
///
/// On n'utilise **pas** le trousseau : sur tvOS, Apple ne garantit pas sa
/// persistance — le système peut le purger à tout moment, ce qui obligerait à se
/// reconnecter sans raison apparente. Les préférences, elles, survivent aux
/// relancements comme aux mises à jour de l'application.
///
/// Le compromis est acceptable : ce qui est conservé n'est pas un mot de passe
/// mais un jeton de session, révocable depuis Jellyfin (Tableau de bord →
/// Appareils), sur un appareil qui reste au salon.
public enum CredentialStore {
    private static let sessionKey = "jellyflix.session"

    /// Groupe d'applications partagé avec l'extension Top Shelf : celle-ci tourne
    /// dans un processus distinct et n'a aucun accès aux préférences de l'app.
    public static let appGroup = "group.com.maximesaltet.jellyflix"

    /// Dossier partagé entre l'application et l'extension Top Shelf.
    ///
    /// On écrit un **fichier**, et non des préférences : sur tvOS,
    /// `UserDefaults(suiteName:)` passe par `cfprefsd` avec une portée « tous
    /// utilisateurs » que le système refuse pour un conteneur d'app group —
    /// « Using kCFPreferencesAnyUser with a container is only allowed for System
    /// Containers ». Le conteneur, lui, est parfaitement accessible en écriture
    /// directe ; c'est seulement la couche préférences qui est bloquée.
    private static var sharedContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// Emplacement du fichier de session dans le conteneur partagé.
    ///
    /// tvOS restreint fortement l'écriture sur disque : la racine du conteneur est
    /// en lecture seule sur l'appareil (elle est permissive au simulateur, ce qui
    /// masque le problème), et tous les sous-dossiers ne sont pas créables. Plutôt
    /// que de parier sur un emplacement, on essaie les candidats du plus durable au
    /// plus tolérant et on retient le premier qui accepte réellement une écriture.
    nonisolated(unsafe) private static var resolvedFile: URL?

    private static var sessionFile: URL? {
        if let resolvedFile { return resolvedFile }
        guard let container = sharedContainer else { return nil }

        let candidates = [
            container.appendingPathComponent("Library/Application Support", isDirectory: true),
            container.appendingPathComponent("Library/Caches", isDirectory: true),
            container.appendingPathComponent("Library", isDirectory: true),
            container
        ]

        for directory in candidates {
            if !FileManager.default.fileExists(atPath: directory.path) {
                guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
                else { continue }
            }
            // Le seul test fiable est l'écriture elle-même : `isWritableFile`
            // répond faux sur un dossier absent et vrai sur des volumes qui
            // refusent malgré tout la création de fichiers.
            let candidate = directory.appendingPathComponent("session.json")
            let probe = directory.appendingPathComponent(".jellyflix-probe")
            guard (try? Data().write(to: probe)) != nil else { continue }
            try? FileManager.default.removeItem(at: probe)

            resolvedFile = candidate
            jellyfinLog.debug("TOP SHELF · emplacement retenu : \(candidate.path, privacy: .public)")
            return candidate
        }

        jellyfinLog.error("TOP SHELF · aucun emplacement inscriptible dans \(container.path, privacy: .public)")
        return nil
    }

    /// Le conteneur partagé est-il accessible ? L'extension Top Shelf en dépend
    /// entièrement : sans lui, elle ne verra jamais la session.
    public static var isAppGroupAvailable: Bool {
        sharedContainer != nil
    }

    /// État du stockage partagé, tracé depuis l'application — les journaux de
    /// l'extension, eux, n'apparaissent pas dans la console Xcode.
    public static func logSharedStorageState() {
        guard let file = sessionFile else {
            jellyfinLog.error(
                "TOP SHELF · conteneur \(appGroup, privacy: .public) INACCESSIBLE — l'extension ne pourra rien lire"
            )
            return
        }

        let exists = FileManager.default.fileExists(atPath: file.path)
        let writable = FileManager.default.isWritableFile(atPath: file.deletingLastPathComponent().path)
        jellyfinLog.debug(
            "TOP SHELF · session.json \(exists ? "présent" : "ABSENT", privacy: .public), dossier \(writable ? "inscriptible" : "EN LECTURE SEULE", privacy: .public) — \(file.path, privacy: .public)"
        )
    }

    public static func save(_ credentials: StoredCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }

        if let sessionFile {
            do {
                try data.write(to: sessionFile, options: .atomic)
                jellyfinLog.debug("TOP SHELF · session écrite (\(data.count) octets) dans \(sessionFile.path, privacy: .public)")
                // Copie locale de secours : si le groupe venait à disparaître, la
                // session survivrait au moins dans l'application.
                UserDefaults.standard.set(data, forKey: sessionKey)
                return
            } catch {
                jellyfinLog.error("Écriture de la session partagée impossible : \(error.localizedDescription, privacy: .public)")
            }
        } else {
            jellyfinLog.error("Conteneur \(appGroup, privacy: .public) indisponible : session gardée en local")
        }

        UserDefaults.standard.set(data, forKey: sessionKey)
    }

    public static func load() -> StoredCredentials? {
        if let sessionFile, let data = try? Data(contentsOf: sessionFile),
           let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: data) {
            return credentials
        }

        // Repli et migration. La session a successivement vécu dans les préférences
        // locales, puis dans celles du groupe (qui fonctionnent au simulateur mais
        // pas sur l'appareil). On la récupère où qu'elle soit et on la recopie dans
        // le conteneur partagé, plutôt que d'imposer une reconnexion.
        let legacySources = [UserDefaults.standard, UserDefaults(suiteName: appGroup)].compactMap(\.self)

        for source in legacySources {
            guard let data = source.data(forKey: sessionKey),
                  let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: data)
            else { continue }

            if let sessionFile {
                try? data.write(to: sessionFile, options: .atomic)
            }
            UserDefaults.standard.set(data, forKey: sessionKey)
            return credentials
        }

        return nil
    }

    public static func clear() {
        if let sessionFile {
            try? FileManager.default.removeItem(at: sessionFile)
        }
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    /// Client prêt à l'emploi reconstruit depuis la session enregistrée.
    /// C'est le point d'entrée de l'extension Top Shelf, qui n'a pas d'`AppSession`.
    public static func restoreClient(clientName: String, deviceName: String) -> JellyfinClient? {
        guard let stored = load() else { return nil }
        return JellyfinClient(
            baseURL: stored.serverURL,
            identity: ClientIdentity(
                name: clientName,
                version: "0.1.0",
                deviceName: deviceName,
                deviceId: stored.deviceId
            ),
            accessToken: stored.accessToken,
            userId: stored.userId
        )
    }

    /// Identifiant d'appareil stable : Jellyfin s'en sert pour reconnaître l'Apple TV
    /// d'un lancement à l'autre. En changer ferait apparaître un second appareil
    /// dans la liste des sessions du serveur.
    public static func deviceId() -> String {
        let key = "jellyflix.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}
