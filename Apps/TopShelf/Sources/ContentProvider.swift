import JellyfinKit
import TVServices

/// Alimente l'étagère du haut de l'écran d'accueil tvOS : ce que le système affiche
/// au-dessus de la grille quand l'icône de Sofafin est sélectionnée.
///
/// L'extension tourne dans un processus séparé, sans accès à l'état de l'app : elle
/// reconstruit un client à partir de la session partagée via le groupe
/// d'applications, puis interroge le serveur elle-même.
final class ContentProvider: TVTopShelfContentProvider {

    /// Le système attend une réponse rapide et retombe sur l'image statique en cas
    /// de retard. On borne donc l'attente plutôt que de risquer une étagère vide.
    private static let deadline: Duration = .seconds(6)

    /// Seules les données traversent la frontière de concurrence : les objets
    /// `TVTopShelf…` ne sont pas `Sendable` et sont donc bâtis après coup.
    private struct Payload: Sendable {
        let resume: [MediaItem]
        let nextUp: [MediaItem]
    }

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        jellyfinLog.debug("Top Shelf : contenu demandé par le système")

        guard let client = CredentialStore.restoreClient(
            clientName: "Sofafin Top Shelf",
            deviceName: "Apple TV"
        ) else {
            jellyfinLog.error("Top Shelf : aucune session dans le groupe \(CredentialStore.appGroup, privacy: .public)")
            completionHandler(nil)
            return
        }
        jellyfinLog.debug("Top Shelf : session trouvée pour \(client.baseURL.absoluteString, privacy: .public)")

        // `nonisolated(unsafe)` : l'en-tête de TVServices précise que ce gestionnaire
        // « peut être appelé depuis n'importe quelle file », mais il n'est pas
        // déclaré `Sendable` — le franchir depuis une tâche exige donc de le dire
        // explicitement au compilateur.
        nonisolated(unsafe) let handler = completionHandler

        Task {
            let payload = await Self.fetch(using: client)
            jellyfinLog.error(
                "Top Shelf : \(payload?.resume.count ?? -1) reprises, \(payload?.nextUp.count ?? -1) prochains épisodes"
            )
            handler(payload.flatMap { Self.buildContent(from: $0, using: client) })
        }
    }

    private static func fetch(using client: JellyfinClient) async -> Payload? {
        await withTaskGroup(of: Payload?.self) { group in
            group.addTask {
                async let resume = (try? await client.resumeItems(limit: 8)) ?? []
                async let nextUp = (try? await client.nextUp(limit: 8)) ?? []
                let (resumeItems, nextUpItems) = await (resume, nextUp)
                return Payload(resume: resumeItems, nextUp: nextUpItems)
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func buildContent(from payload: Payload, using client: JellyfinClient) -> TVTopShelfContent? {
        let resumeItems = payload.resume
        let nextUpItems = payload.nextUp

        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []

        if !resumeItems.isEmpty {
            let section = TVTopShelfItemCollection(items: resumeItems.map { item($0, using: client) })
            section.title = "Reprendre la lecture"
            sections.append(section)
        }

        // Un épisode déjà en cours figure dans « Reprendre » : l'afficher deux fois
        // n'apporterait rien.
        let resumeIds = Set(resumeItems.map(\.id))
        let upcoming = nextUpItems.filter { !resumeIds.contains($0.id) }
        if !upcoming.isEmpty {
            let section = TVTopShelfItemCollection(items: upcoming.map { item($0, using: client) })
            section.title = "Prochains épisodes"
            sections.append(section)
        }

        guard !sections.isEmpty else { return nil }
        return TVTopShelfSectionedContent(sections: sections)
    }

    private static func item(_ media: MediaItem, using client: JellyfinClient) -> TVTopShelfSectionedItem {
        let entry = TVTopShelfSectionedItem(identifier: media.id)
        entry.title = displayTitle(for: media)
        // Format 16:9 : ces rangées montrent des images de scène, pas des affiches.
        entry.imageShape = .hdtv

        // Le visuel de la série plutôt que la vignette de l'épisode : une capture
        // de scène isolée est rarement flatteuse une fois agrandie, là où le
        // backdrop est composé pour être vu ainsi. `backdropURL` remonte déjà à la
        // série pour un épisode, et la vignette ne sert que de dernier recours.
        if let url = client.backdropURL(for: media, maxWidth: 1280)
            ?? client.thumbURL(for: media, maxWidth: 1280) {
            entry.setImageURL(url, for: .screenScale1x)
            let large = client.backdropURL(for: media, maxWidth: 2560)
                ?? client.thumbURL(for: media, maxWidth: 2560)
            entry.setImageURL(large ?? url, for: .screenScale2x)
        }

        if let progress = media.progressFraction {
            entry.playbackProgress = progress
        }

        entry.playAction = TVTopShelfAction(url: DeepLink.play(media.id))
        entry.displayAction = TVTopShelfAction(url: DeepLink.details(media.id))
        return entry
    }

    /// Sur l'étagère, une seule ligne de texte est visible : pour un épisode, la
    /// série et le code de saison informent davantage que le titre de l'épisode seul.
    private static func displayTitle(for media: MediaItem) -> String {
        guard media.type == .episode else { return media.displayTitle }
        let parts = [media.seriesName, media.episodeCode].compactMap(\.self)
        return parts.isEmpty ? media.displayTitle : parts.joined(separator: " · ")
    }
}
