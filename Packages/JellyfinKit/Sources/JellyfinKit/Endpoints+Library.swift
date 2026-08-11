import Foundation

// MARK: - Jeux de champs

public enum ItemFieldSet {
    /// Ce qu'il faut pour peupler une vignette de rangée sans alourdir la réponse.
    public static let list = "Overview,PrimaryImageAspectRatio,ProductionYear,ParentId"
    /// Tout ce qu'affiche un écran de détail.
    public static let detail = """
    Overview,Genres,Studios,People,Taglines,ProductionYear,MediaSources,MediaStreams,\
    ChildCount,RecursiveItemCount,ParentId,PrimaryImageAspectRatio,ExternalUrls,Chapters
    """
}

private extension URLQueryItem {
    init(_ name: String, _ value: String?) {
        self.init(name: name, value: value)
    }

    init(_ name: String, _ value: Int?) {
        self.init(name: name, value: value.map(String.init))
    }

    init(_ name: String, _ value: Bool?) {
        self.init(name: name, value: value.map { $0 ? "true" : "false" })
    }
}

// MARK: - Bibliothèque

public extension JellyfinClient {

    /// Les bibliothèques de l'utilisateur (Films, Séries…).
    func userViews() async throws -> [MediaItem] {
        let response: ItemsResponse = try await get(
            "UserViews",
            query: [URLQueryItem("userId", userId)]
        )
        return response.items ?? []
    }

    /// « Reprendre la lecture ».
    func resumeItems(limit: Int = 12) async throws -> [MediaItem] {
        let response: ItemsResponse = try await get("UserItems/Resume", query: [
            URLQueryItem("userId", userId),
            URLQueryItem("limit", limit),
            URLQueryItem("fields", ItemFieldSet.list),
            URLQueryItem("mediaTypes", "Video"),
            URLQueryItem("enableUserData", true),
            URLQueryItem("enableImageTypes", "Primary,Backdrop,Thumb,Logo")
        ])
        return response.items ?? []
    }

    /// « Prochains épisodes » des séries commencées.
    /// Suite de ce que l'utilisateur regarde.
    ///
    /// `enableResumable` est à `false` : un épisode déjà entamé appartient à
    /// « Reprendre la lecture », l'afficher aux deux endroits ferait doublon.
    ///
    /// Un S01E01 qui apparaît ici n'est **pas** un défaut de la requête : Jellyfin
    /// ne propose le premier épisode d'une série que si celle-ci porte une trace de
    /// lecture. Une séance abandonnée sous le seuil de reprise du serveur — les
    /// premières minutes d'un essai — suffit à marquer la série comme commencée
    /// sans rendre l'épisode reprenable : il ressort alors comme prochain à voir.
    /// Le paramètre `disableFirstEpisode` masquerait ce cas, mais avec lui une
    /// série réellement entamée de quelques minutes disparaîtrait aussi de la
    /// rangée. La correction est côté serveur : effacer l'historique de la série.
    func nextUp(limit: Int = 16) async throws -> [MediaItem] {
        let response: ItemsResponse = try await get("Shows/NextUp", query: [
            URLQueryItem("userId", userId),
            URLQueryItem("limit", limit),
            URLQueryItem("fields", ItemFieldSet.list),
            URLQueryItem("enableUserData", true),
            URLQueryItem("enableImageTypes", "Primary,Backdrop,Thumb,Logo"),
            URLQueryItem("enableResumable", false)
        ])
        return response.items ?? []
    }

    /// Derniers ajouts, toutes bibliothèques ou pour une bibliothèque donnée.
    func latestItems(parentId: String? = nil, limit: Int = 20) async throws -> [MediaItem] {
        try await get("Items/Latest", query: [
            URLQueryItem("userId", userId),
            URLQueryItem("parentId", parentId),
            URLQueryItem("limit", limit),
            URLQueryItem("fields", ItemFieldSet.list),
            URLQueryItem("enableUserData", true),
            URLQueryItem("enableImageTypes", "Primary,Backdrop,Thumb,Logo"),
            URLQueryItem("includeItemTypes", "Movie,Series"),
            URLQueryItem("groupItems", "true")
        ], as: [MediaItem].self)
    }

    /// Requête générique sur `/Items`.
    func items(
        parentId: String? = nil,
        includeTypes: [String] = [],
        sortBy: String = "SortName",
        sortOrder: String = "Ascending",
        filters: [String] = [],
        genres: [String] = [],
        years: [Int] = [],
        personIds: [String] = [],
        searchTerm: String? = nil,
        isPlayed: Bool? = nil,
        startIndex: Int = 0,
        limit: Int = 60,
        recursive: Bool = true,
        fields: String = ItemFieldSet.list
    ) async throws -> ItemsResponse {
        try await get("Items", query: [
            URLQueryItem("userId", userId),
            URLQueryItem("parentId", parentId),
            URLQueryItem("includeItemTypes", includeTypes.isEmpty ? nil : includeTypes.joined(separator: ",")),
            URLQueryItem("sortBy", sortBy),
            URLQueryItem("sortOrder", sortOrder),
            URLQueryItem("filters", filters.isEmpty ? nil : filters.joined(separator: ",")),
            URLQueryItem("genres", genres.isEmpty ? nil : genres.joined(separator: "|")),
            URLQueryItem("years", years.isEmpty ? nil : years.map(String.init).joined(separator: ",")),
            URLQueryItem("personIds", personIds.isEmpty ? nil : personIds.joined(separator: ",")),
            URLQueryItem("searchTerm", searchTerm),
            URLQueryItem("isPlayed", isPlayed),
            URLQueryItem("startIndex", startIndex),
            URLQueryItem("limit", limit),
            URLQueryItem("recursive", recursive),
            URLQueryItem("fields", fields),
            URLQueryItem("enableUserData", true),
            URLQueryItem("enableTotalRecordCount", true),
            URLQueryItem("enableImageTypes", "Primary,Backdrop,Thumb,Logo")
        ])
    }

    /// Les collections de la médiathèque — les « box sets », qu'ils soient montés à
    /// la main ou fabriqués par le plugin TMDb Box Sets.
    ///
    /// `ChildCount` s'ajoute au jeu de champs de rangée pour écarter les collections
    /// vides : le plugin en crée pour des sagas dont la médiathèque ne possède aucun
    /// film, et une affiche qui n'ouvre sur rien n'a rien à faire à l'écran.
    func collections(limit: Int = 24) async throws -> [MediaItem] {
        let response = try await items(
            includeTypes: ["BoxSet"],
            sortBy: "SortName",
            limit: limit,
            fields: ItemFieldSet.list + ",ChildCount"
        )
        return (response.items ?? []).filter { ($0.childCount ?? 0) > 0 }
    }

    /// Contenu d'une collection, dans l'ordre de sortie : une saga se regarde ainsi.
    ///
    /// Volontairement non récursif — une collection peut contenir une série, dont la
    /// descente ramènerait ses épisodes un à un au lieu de la série elle-même.
    func collectionItems(collectionId: String) async throws -> [MediaItem] {
        let response = try await items(
            parentId: collectionId,
            sortBy: "PremiereDate",
            limit: 100,
            recursive: false
        )
        return response.items ?? []
    }

    /// Bandes-annonces déposées à côté du média, dans son sous-dossier `trailers/`.
    ///
    /// Seules celles-ci sont exploitables : Jellyfin connaît aussi des bandes-annonces
    /// « distantes », mais ce sont des liens YouTube, et tvOS n'a aucun moteur web
    /// pour les afficher. On les matérialise en fichiers côté serveur.
    func localTrailers(itemId: String) async -> [MediaItem] {
        do {
            return try await get("Items/\(itemId)/LocalTrailers",
                                 query: [URLQueryItem("userId", userId)],
                                 as: [MediaItem].self)
        } catch {
            jellyfinLog.debug("Aucune bande-annonce locale pour \(itemId, privacy: .public)")
            return []
        }
    }

    func item(id: String) async throws -> MediaItem {
        try await get("Items/\(id)", query: [
            URLQueryItem("userId", userId),
            URLQueryItem("fields", ItemFieldSet.detail)
        ])
    }

    func seasons(seriesId: String) async throws -> [MediaItem] {
        let response: ItemsResponse = try await get("Shows/\(seriesId)/Seasons", query: [
            URLQueryItem("userId", userId),
            URLQueryItem("fields", ItemFieldSet.list),
            URLQueryItem("enableUserData", true),
            URLQueryItem("enableImageTypes", "Primary,Backdrop,Thumb")
        ])
        return response.items ?? []
    }

    func episodes(seriesId: String, seasonId: String? = nil) async throws -> [MediaItem] {
        let response: ItemsResponse = try await get("Shows/\(seriesId)/Episodes", query: [
            URLQueryItem("userId", userId),
            URLQueryItem("seasonId", seasonId),
            URLQueryItem("fields", "Overview,MediaSources,PrimaryImageAspectRatio,ParentId"),
            URLQueryItem("enableUserData", true),
            URLQueryItem("enableImageTypes", "Primary,Thumb")
        ])
        return response.items ?? []
    }

    /// L'épisode qui suit immédiatement celui-ci, saison suivante comprise.
    ///
    /// `adjacentTo` fait faire le tri au serveur : il connaît l'ordre réel de la
    /// série, y compris ses numérotations trouées et ses épisodes spéciaux, là où
    /// un calcul côté client sur `indexNumber` se tromperait dès la première
    /// anomalie. La réponse contient l'épisode précédent, celui-ci, et le suivant.
    func nextEpisode(after item: MediaItem) async -> MediaItem? {
        guard item.type == .episode, let seriesId = item.seriesId else { return nil }
        let response: ItemsResponse? = try? await get("Shows/\(seriesId)/Episodes", query: [
            URLQueryItem("userId", userId),
            URLQueryItem("adjacentTo", item.id),
            URLQueryItem("fields", ItemFieldSet.list),
            URLQueryItem("enableUserData", true),
            URLQueryItem("enableImageTypes", "Primary,Backdrop,Thumb")
        ])
        guard let neighbours = response?.items,
              let position = neighbours.firstIndex(where: { $0.id == item.id }),
              neighbours.index(after: position) < neighbours.endIndex
        else { return nil }
        return neighbours[position + 1]
    }

    func similar(to itemId: String, limit: Int = 12) async throws -> [MediaItem] {
        let response: ItemsResponse = try await get("Items/\(itemId)/Similar", query: [
            URLQueryItem("userId", userId),
            URLQueryItem("limit", limit),
            URLQueryItem("fields", ItemFieldSet.list)
        ])
        return response.items ?? []
    }

    func search(_ term: String, limit: Int = 40) async throws -> [MediaItem] {
        let response = try await items(
            includeTypes: ["Movie", "Series", "Episode"],
            sortBy: "SortName",
            searchTerm: term,
            limit: limit
        )
        return response.items ?? []
    }

    /// Genres réellement présents dans une bibliothèque, pour alimenter les filtres.
    func genres(parentId: String? = nil) async throws -> [MediaItem] {
        let response: ItemsResponse = try await get("Genres", query: [
            URLQueryItem("userId", userId),
            URLQueryItem("parentId", parentId),
            URLQueryItem("sortBy", "SortName")
        ])
        return response.items ?? []
    }
}

// MARK: - État utilisateur

public extension JellyfinClient {
    func markPlayed(itemId: String) async throws {
        try await postVoid("UserPlayedItems/\(itemId)", query: [URLQueryItem("userId", userId)])
    }

    func markUnplayed(itemId: String) async throws {
        try await deleteVoid("UserPlayedItems/\(itemId)", query: [URLQueryItem("userId", userId)])
    }

    func setFavorite(_ isFavorite: Bool, itemId: String) async throws {
        let path = "UserFavoriteItems/\(itemId)"
        let query = [URLQueryItem("userId", userId)]
        if isFavorite {
            try await postVoid(path, query: query)
        } else {
            try await deleteVoid(path, query: query)
        }
    }
}
