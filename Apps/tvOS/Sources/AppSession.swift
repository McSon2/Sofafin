import Foundation
import JellyfinKit
import Observation
import TVServices

/// État d'authentification global : quel serveur, quel utilisateur, quel client prêt à l'emploi.
@Observable
@MainActor
final class AppSession {

    enum Phase: Equatable {
        case restoring
        case needsServer
        case needsSignIn(serverName: String?)
        case ready
    }

    private(set) var phase: Phase = .restoring
    private(set) var client: JellyfinClient?
    private(set) var user: JellyfinUser?
    private(set) var serverURL: URL?
    private(set) var serverName: String?

    /// Bibliothèques affichées comme onglets. Elles sont chargées **avant** de passer
    /// en `.ready` : si la liste arrivait après, l'apparition des onglets
    /// reconstruirait la barre et annulerait les chargements déjà en cours.
    private(set) var libraries: [MediaItem] = []

    /// Incrémenté après chaque action qui modifie l'état côté serveur (vu, favori).
    /// Les écrans s'y abonnent pour se recharger : sans cela, un titre marqué comme
    /// vu resterait affiché dans « Reprendre la lecture », le serveur ayant pourtant
    /// effacé sa progression.
    private(set) var libraryRevision = 0

    func libraryDidChange() {
        libraryRevision += 1
        notifyTopShelf()
    }

    /// Prévient tvOS que l'étagère du haut est périmée. Sans ce signal, le système
    /// s'en tient à ce qu'il a mis en cache et peut ne jamais rappeler l'extension.
    func notifyTopShelf() {
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    /// Cible demandée par l'étagère du haut, consommée par `HomeView` dès que la
    /// session est prête — un lien peut arriver avant la fin de la restauration.
    var pendingDeepLink: DeepLink.Destination?

    func handle(_ url: URL) {
        guard let destination = DeepLink.destination(from: url) else { return }
        pendingDeepLink = destination
    }

    func consumeDeepLink() -> DeepLink.Destination? {
        defer { pendingDeepLink = nil }
        return pendingDeepLink
    }

    var lastError: String?

    private let identity: ClientIdentity

    init() {
        identity = ClientIdentity(
            name: "Sofafin",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            deviceName: "Apple TV",
            deviceId: CredentialStore.deviceId()
        )
    }

    /// Client authentifié. Les vues n'y accèdent qu'une fois la phase à `.ready`.
    var api: JellyfinClient {
        guard let client else {
            preconditionFailure("Accès à l'API avant authentification")
        }
        return client
    }

    // MARK: Restauration

    func restore() async {
        // Visible dans la console Xcode, contrairement aux journaux de l'extension :
        // c'est le seul moyen de savoir depuis l'app si le conteneur partagé — dont
        // dépend entièrement le Top Shelf — est réellement accessible.
        CredentialStore.logSharedStorageState()

        guard let stored = CredentialStore.load() else {
            phase = .needsServer
            return
        }
        // Identité reconstruite avec l'identifiant d'appareil **enregistré**, et non
        // l'identifiant courant : Jellyfin lie chaque jeton à l'appareil qui l'a
        // demandé et rejette la session (401) dès que les deux divergent — ce qui
        // arrive quand les préférences locales sont réinitialisées alors que la
        // session, elle, survit dans le conteneur partagé.
        let restored = JellyfinClient(
            baseURL: stored.serverURL,
            identity: ClientIdentity(
                name: identity.name,
                version: identity.version,
                deviceName: identity.deviceName,
                deviceId: stored.deviceId
            ),
            accessToken: stored.accessToken,
            userId: stored.userId
        )
        do {
            let me = try await restored.currentUser()
            client = restored
            user = me
            serverURL = stored.serverURL
            serverName = stored.serverName
            await loadLibraries(using: restored)
            phase = .ready
            // La session vient d'être rétablie : l'étagère peut enfin être remplie.
            notifyTopShelf()
        } catch JellyfinError.unauthorized {
            // Token révoqué côté serveur : on garde l'adresse, on redemande l'identité.
            CredentialStore.clear()
            serverURL = stored.serverURL
            serverName = stored.serverName
            phase = .needsSignIn(serverName: stored.serverName)
        } catch {
            // Serveur injoignable : inutile de déconnecter, l'utilisateur retentera.
            lastError = L("Serveur injoignable : \(error.localizedDescription)")
            phase = .needsServer
        }
    }

    // MARK: Serveur

    /// Valide une adresse saisie et prépare la phase de connexion.
    func connectToServer(_ input: String) async -> Bool {
        lastError = nil
        guard let url = await JellyfinClient.resolveServerURL(from: input) else {
            lastError = L("Aucun serveur Jellyfin à cette adresse.")
            return false
        }
        let probe = JellyfinClient(baseURL: url, identity: identity)
        let info = try? await probe.publicSystemInfo()
        serverURL = url
        serverName = info?.serverName
        phase = .needsSignIn(serverName: info?.serverName)
        return true
    }

    var anonymousClient: JellyfinClient? {
        serverURL.map { JellyfinClient(baseURL: $0, identity: identity) }
    }

    // MARK: Connexion

    func signIn(username: String, password: String) async -> Bool {
        guard let anonymousClient else { return false }
        lastError = nil
        do {
            let result = try await anonymousClient.authenticate(username: username, password: password)
            return await finalizeSignIn(result)
        } catch JellyfinError.unauthorized {
            lastError = L("Identifiant ou mot de passe incorrect.")
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func completeQuickConnect(secret: String) async -> Bool {
        guard let anonymousClient else { return false }
        do {
            let result = try await anonymousClient.authenticateWithQuickConnect(secret: secret)
            return await finalizeSignIn(result)
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func finalizeSignIn(_ result: AuthenticationResult) async -> Bool {
        guard let token = result.accessToken, let account = result.user, let url = serverURL else {
            lastError = L("Réponse d'authentification incomplète.")
            return false
        }
        let authenticated = JellyfinClient(
            baseURL: url,
            identity: identity,
            accessToken: token,
            userId: account.id
        )
        CredentialStore.save(StoredCredentials(
            serverURL: url,
            serverName: serverName,
            userId: account.id,
            userName: account.name,
            accessToken: token,
            deviceId: identity.deviceId
        ))
        client = authenticated
        user = account
        await loadLibraries(using: authenticated)
        phase = .ready
        notifyTopShelf()
        return true
    }

    /// Onglets de la barre latérale, dans un ordre imposé.
    ///
    /// Jellyfin renvoie ses vues par ordre alphabétique, ce qui placerait
    /// « Collections » avant « Films ». On veut l'inverse : les deux médiathèques
    /// d'abord, les regroupements ensuite. Les vues sans intérêt ici — musique,
    /// livres, TV en direct — sont écartées faute d'écran pour les présenter.
    private func loadLibraries(using client: JellyfinClient) async {
        let order: [CollectionKind] = [.movies, .tvshows, .boxsets]
        libraries = (try? await client.userViews())?
            .filter { order.contains($0.collectionType ?? .unknown) }
            .sorted { left, right in
                let leftRank = order.firstIndex(of: left.collectionType ?? .unknown) ?? order.count
                let rightRank = order.firstIndex(of: right.collectionType ?? .unknown) ?? order.count
                return leftRank < rightRank
            } ?? []
    }

    // MARK: Déconnexion

    func signOut() async {
        await client?.logout()
        CredentialStore.clear()
        client = nil
        user = nil
        phase = .needsServer
    }

    /// Ne quitte que le compte, en gardant le serveur déjà validé.
    func switchUser() async {
        await client?.logout()
        CredentialStore.clear()
        client = nil
        user = nil
        phase = .needsSignIn(serverName: serverName)
    }
}
