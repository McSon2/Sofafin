import JellyfinKit
import Observation
import SwiftUI

/// Une rangée de l'accueil.
struct HomeSection: Identifiable {
    let id: String
    let title: String
    let layout: RowLayout
    let items: [MediaItem]
}

@Observable
@MainActor
final class HomeModel {
    private(set) var sections: [HomeSection] = []
    private(set) var featured: [MediaItem] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    /// Genres mis en avant : on ne montre que ceux qui ont assez de titres
    /// pour remplir une rangée, sinon l'accueil se retrouve criblé de trous.
    private let minimumItemsPerGenreRow = 5
    private let maximumGenreRows = 3

    func load(using client: JellyfinClient) async {
        isLoading = true
        errorMessage = nil

        async let resume = (try? await client.resumeItems(limit: 12)) ?? []
        async let nextUp = (try? await client.nextUp(limit: 16)) ?? []
        async let latest = (try? await client.latestItems(limit: 24)) ?? []
        async let movies = (try? await client.items(
            includeTypes: ["Movie"], sortBy: "DateCreated", sortOrder: "Descending", limit: 24
        ).items) ?? []
        async let series = (try? await client.items(
            includeTypes: ["Series"], sortBy: "DateCreated", sortOrder: "Descending", limit: 24
        ).items) ?? []
        async let favorites = (try? await client.items(
            includeTypes: ["Movie", "Series"], sortBy: "SortName", filters: ["IsFavorite"], limit: 24
        ).items) ?? []
        async let collections = (try? await client.collections(limit: 24)) ?? []

        let (resumeItems, nextUpItems, latestItems, movieItems, seriesItems, favoriteItems, collectionItems) =
            await (resume, nextUp, latest, movies, series, favorites, collections)

        var built: [HomeSection] = []
        append(&built, id: "resume", "Reprendre la lecture", .landscape, resumeItems)
        append(&built, id: "nextup", "Prochains épisodes", .landscape, nextUpItems)
        append(&built, id: "latest", "Ajouts récents", .poster, latestItems)
        append(&built, id: "favorites", "Mes favoris", .poster, favoriteItems)
        append(&built, id: "collections", "Collections", .poster, collectionItems)
        append(&built, id: "movies", "Films", .poster, movieItems)
        append(&built, id: "series", "Séries", .poster, seriesItems)

        // Une vue reconstruite annule ses requêtes en vol : le résultat est alors
        // vide sans que le serveur soit en cause. Conclure ici afficherait à tort
        // une médiathèque déserte.
        guard !Task.isCancelled else { return }

        sections = built
        // Le billboard puise dans les nouveautés : ce sont elles qui donnent envie.
        featured = Array((latestItems.isEmpty ? movieItems : latestItems).prefix(8))
        isLoading = false

        if built.isEmpty {
            errorMessage = "Aucun contenu trouvé sur ce serveur."
        }

        await appendGenreRows(using: client, seed: movieItems + seriesItems)
    }

    private func append(
        _ sections: inout [HomeSection],
        id: String,
        _ title: String,
        _ layout: RowLayout,
        _ items: [MediaItem]
    ) {
        guard !items.isEmpty else { return }
        sections.append(HomeSection(id: id, title: title, layout: layout, items: items))
    }

    /// Rangées thématiques construites après coup : l'accueil s'affiche d'abord,
    /// ces requêtes supplémentaires viennent l'enrichir sans le retarder.
    private func appendGenreRows(using client: JellyfinClient, seed: [MediaItem]) async {
        let ranked = seed
            .flatMap { $0.genres ?? [] }
            .reduce(into: [String: Int]()) { counts, genre in counts[genre, default: 0] += 1 }
            .filter { $0.value >= minimumItemsPerGenreRow }
            .sorted { $0.value > $1.value }
            .prefix(maximumGenreRows)
            .map(\.key)

        for genre in ranked {
            guard let items = try? await client.items(
                includeTypes: ["Movie", "Series"],
                sortBy: "Random",
                genres: [genre],
                limit: 20
            ).items, items.count >= minimumItemsPerGenreRow else { continue }

            sections.append(HomeSection(id: "genre-\(genre)", title: genre, layout: .poster, items: items))
        }
    }
}
