import Foundation

public enum JellyfinImage: String, Sendable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case thumb = "Thumb"
    case logo = "Logo"
    case banner = "Banner"
    case art = "Art"
}

public extension JellyfinClient {

    /// URL d'une image d'item. Les images Jellyfin sont servies sans authentification :
    /// on peut donc les passer directement à `AsyncImage`.
    func imageURL(
        itemId: String,
        type: JellyfinImage = .primary,
        tag: String? = nil,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        quality: Int = 90
    ) -> URL? {
        var query = [
            URLQueryItem(name: "quality", value: String(quality))
        ]
        if let tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        if let maxWidth { query.append(URLQueryItem(name: "maxWidth", value: String(maxWidth))) }
        if let maxHeight { query.append(URLQueryItem(name: "maxHeight", value: String(maxHeight))) }
        return try? url(path: "Items/\(itemId)/Images/\(type.rawValue)", query: query)
    }

    // MARK: Résolutions par défaut
    //
    // Une Apple TV 4K rend l'interface à l'échelle 2 : une affiche posée sur
    // 280 points occupe 560 pixels, et 610 une fois agrandie par le focus. Les
    // valeurs ci-dessous couvrent cet état agrandi — c'est celui que l'utilisateur
    // regarde. En demander moins revient à faire étirer l'image par le lecteur, ce
    // qui se voit immédiatement sur une grande dalle.

    /// Affiche du portrait : le poster de l'item, en retombant sur celui de la série
    /// pour un épisode (qui n'a le plus souvent qu'une vignette d'écran).
    func posterURL(for item: MediaItem, maxWidth: Int = 700) -> URL? {
        if let tag = item.imageTags?["Primary"] {
            return imageURL(itemId: item.id, type: .primary, tag: tag, maxWidth: maxWidth)
        }
        if item.type == .episode, let seriesId = item.seriesId {
            return imageURL(itemId: seriesId, type: .primary, tag: item.seriesPrimaryImageTag, maxWidth: maxWidth)
        }
        return nil
    }

    /// Affiche du paysage : vignette d'épisode, sinon backdrop, sinon poster.
    func thumbURL(for item: MediaItem, maxWidth: Int = 1100) -> URL? {
        if item.type == .episode, let tag = item.imageTags?["Primary"] {
            return imageURL(itemId: item.id, type: .primary, tag: tag, maxWidth: maxWidth)
        }
        if let tag = item.imageTags?["Thumb"] {
            return imageURL(itemId: item.id, type: .thumb, tag: tag, maxWidth: maxWidth)
        }
        if let tag = item.parentThumbImageTag, let parentId = item.parentThumbItemId {
            return imageURL(itemId: parentId, type: .thumb, tag: tag, maxWidth: maxWidth)
        }
        return backdropURL(for: item, maxWidth: maxWidth) ?? posterURL(for: item, maxWidth: maxWidth)
    }

    /// Grande image de fond, celle qui remplit le billboard d'accueil.
    ///
    /// 2560 et non 3840 : l'image occupe toute la largeur d'une dalle 4K, mais elle
    /// passe sous un voile sombre et ne porte aucun détail fin. Réclamer la pleine
    /// résolution triplerait le poids d'une image que le billboard remplace à
    /// chaque déplacement du focus.
    func backdropURL(for item: MediaItem, maxWidth: Int = 2560) -> URL? {
        if let tag = item.backdropImageTags?.first {
            return imageURL(itemId: item.id, type: .backdrop, tag: tag, maxWidth: maxWidth)
        }
        if let tag = item.parentBackdropImageTags?.first, let parentId = item.parentBackdropItemId {
            return imageURL(itemId: parentId, type: .backdrop, tag: tag, maxWidth: maxWidth)
        }
        // Les épisodes héritent du backdrop de leur série.
        if let seriesId = item.seriesId, item.type == .episode {
            return imageURL(itemId: seriesId, type: .backdrop, maxWidth: maxWidth)
        }
        return nil
    }

    /// Logo du titre — c'est lui qui donne au billboard son allure de Netflix.
    /// Posé sur 620 points, il en réclame 1240 en pixels.
    func logoURL(for item: MediaItem, maxWidth: Int = 1280) -> URL? {
        if let tag = item.imageTags?["Logo"] {
            return imageURL(itemId: item.id, type: .logo, tag: tag, maxWidth: maxWidth)
        }
        if let seriesId = item.seriesId {
            return imageURL(itemId: seriesId, type: .logo, maxWidth: maxWidth)
        }
        return nil
    }

    func personImageURL(for person: Person, maxWidth: Int = 400) -> URL? {
        guard let id = person.id, let tag = person.primaryImageTag else { return nil }
        return imageURL(itemId: id, type: .primary, tag: tag, maxWidth: maxWidth)
    }
}
