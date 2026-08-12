import Foundation

/// Un genre de la médiathèque, tel que le serveur le connaît.
///
/// Les genres ne sont pas une liste fixe : ils viennent des métadonnées des
/// titres, et chaque médiathèque a les siens. Les demander au serveur plutôt que
/// de les déduire des titres chargés donne la liste complète, dans la langue de
/// la médiathèque, sans avoir à tout rapatrier.
public struct Genre: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

/// Un genre et l'affiche qui l'illustre.
public struct GenreShowcase: Identifiable, Sendable {
    public let genre: Genre
    /// Un titre du genre, choisi pour son affiche. `nil` tant qu'elle n'a pas
    /// été demandée, ou si le genre s'avère vide.
    public let artwork: MediaItem?

    public var id: String { genre.id }
    public var name: String { genre.name }

    public init(genre: Genre, artwork: MediaItem?) {
        self.genre = genre
        self.artwork = artwork
    }
}

public extension JellyfinClient {

    /// Les genres présents parmi les films de la médiathèque.
    ///
    /// Restreint aux films : ce sont eux que la page de genre présente, et un
    /// genre qui n'existerait que sur des séries y mènerait à une grille vide.
    func movieGenres() async throws -> [Genre] {
        struct Response: Decodable { let items: [Genre]
            enum CodingKeys: String, CodingKey { case items = "Items" }
        }
        let response: Response = try await get("Genres", query: [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "includeItemTypes", value: "Movie"),
            URLQueryItem(name: "recursive", value: "true"),
            URLQueryItem(name: "sortBy", value: "SortName"),
            URLQueryItem(name: "sortOrder", value: "Ascending")
        ])
        return response.items
    }

    /// Un film du genre, choisi pour illustrer sa carte.
    ///
    /// Le mieux noté plutôt qu'un tirage au sort : la carte doit rester la même
    /// d'une visite à l'autre, sans quoi la page semble changer toute seule.
    func artwork(for genre: Genre) async throws -> MediaItem? {
        try await items(
            includeTypes: ["Movie"],
            sortBy: "CommunityRating",
            sortOrder: "Descending",
            genres: [genre.name],
            limit: 1
        ).items?.first
    }

    /// Les genres accompagnés de leur affiche.
    ///
    /// Les affiches se demandent en parallèle — une requête par genre, et une
    /// médiathèque en compte quelques dizaines — mais par groupes, pour ne pas
    /// ouvrir autant de connexions simultanées que de genres.
    func movieGenresWithArtwork() async throws -> [GenreShowcase] {
        let genres = try await movieGenres()
        var showcases: [GenreShowcase] = []
        showcases.reserveCapacity(genres.count)

        for batch in stride(from: 0, to: genres.count, by: 6).map({
            Array(genres[$0 ..< min($0 + 6, genres.count)])
        }) {
            let resolved = await withTaskGroup(of: (Int, MediaItem?).self) { group in
                for (offset, genre) in batch.enumerated() {
                    group.addTask { (offset, try? await self.artwork(for: genre)) }
                }
                var found: [Int: MediaItem?] = [:]
                for await (offset, item) in group { found[offset] = item }
                return found
            }
            for (offset, genre) in batch.enumerated() {
                showcases.append(GenreShowcase(genre: genre, artwork: resolved[offset] ?? nil))
            }
        }

        // Un genre sans aucun film n'a rien à montrer et mènerait à une grille
        // vide : le serveur en déclare parfois, hérités de titres supprimés.
        return showcases.filter { $0.artwork != nil }
    }
}
