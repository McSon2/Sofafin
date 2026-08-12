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
    /// Pourquoi l'accueil est vide — la nuance change ce qu'on propose à
    /// l'utilisateur : une médiathèque réellement déserte n'appelle aucune action,
    /// un serveur muet appelle un bouton pour réessayer.
    enum Failure: Equatable {
        case unreachable(String)
        case empty

        var title: String {
            switch self {
            case .unreachable: return L("Serveur injoignable")
            case .empty: return L("Médiathèque vide")
            }
        }

        var message: String {
            switch self {
            case .unreachable(let detail): return detail
            case .empty: return L("Aucun film ni série n'a été trouvé sur ce serveur.")
            }
        }

        var icon: String {
            switch self {
            case .unreachable: return "wifi.exclamationmark"
            case .empty: return "tray"
            }
        }

        /// Réessayer une médiathèque vide ne servirait à rien : c'est côté serveur
        /// qu'il faut agir.
        var isRetryable: Bool { self != .empty }
    }

    private(set) var sections: [HomeSection] = []
    private(set) var featured: [MediaItem] = []
    private(set) var isLoading = true
    private(set) var failure: Failure?

    /// Recharge l'accueil.
    ///
    /// `silently` distingue les deux cas qui menaient jusqu'ici au même écran de
    /// chargement. Une ouverture d'écran mérite son indicateur ; un rafraîchissement
    /// déclenché par un « vu », un favori ou un retour de lecture ne doit **rien**
    /// démonter : vider les rangées le temps d'un aller-retour au serveur ferait
    /// clignoter tout l'écran et, surtout, détruirait la position du focus.
    func load(using client: JellyfinClient, silently: Bool = false) async {
        isLoading = !silently && sections.isEmpty
        if !silently { failure = nil }

        // La première requête sert de sonde : elle seule remonte son erreur, les
        // autres restant optionnelles. Sans cela une panne réseau se présentait
        // comme une médiathèque vide, message trompeur et sans issue.
        let resumeItems: [MediaItem]
        do {
            resumeItems = try await client.resumeItems(limit: 12)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            // Un rafraîchissement silencieux qui échoue laisse l'écran tel quel :
            // remplacer des rangées valides par une erreur serait une régression
            // pour l'utilisateur, qui n'a rien demandé.
            if !silently || sections.isEmpty {
                failure = .unreachable(error.localizedDescription)
            }
            return
        }

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

        let (nextUpItems, latestItems, movieItems, seriesItems, favoriteItems, collectionItems) =
            await (nextUp, latest, movies, series, favorites, collections)

        var built: [HomeSection] = []
        append(&built, id: "resume", L("Reprendre la lecture"), .landscape, resumeItems)
        append(&built, id: "nextup", L("Prochains épisodes"), .landscape, nextUpItems)
        append(&built, id: "latest", L("Ajouts récents"), .poster, latestItems)
        append(&built, id: "favorites", L("Mes favoris"), .poster, favoriteItems)
        append(&built, id: "movies", L("Films"), .poster, movieItems)
        append(&built, id: "series", L("Séries"), .poster, seriesItems)
        append(&built, id: "collections", L("Collections"), .poster, collectionItems)

        // Une vue reconstruite annule ses requêtes en vol : le résultat est alors
        // vide sans que le serveur soit en cause. Conclure ici afficherait à tort
        // une médiathèque déserte.
        guard !Task.isCancelled else { return }

        sections = built
        // Le billboard puise dans les nouveautés : ce sont elles qui donnent envie.
        featured = Array((latestItems.isEmpty ? movieItems : latestItems).prefix(8))
        isLoading = false
        failure = built.isEmpty ? .empty : nil

        // Une seule fois : les cartes ne changent pas d'un « marquer comme vu »
        // à l'autre, et les reconstruire remplacerait les vignettes sous les yeux
        // de l'utilisateur.
        guard genres.isEmpty, !built.isEmpty else { return }
        genres = (try? await client.movieGenresWithArtwork()) ?? []
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

    /// Les genres de la médiathèque, pour la rangée qui mène à leur page.
    ///
    /// Chargés après l'accueil : leur constitution demande une requête par genre,
    /// et l'attendre retarderait tout l'écran pour une rangée qui vient loin dans
    /// le défilement.
    private(set) var genres: [GenreShowcase] = []
}
