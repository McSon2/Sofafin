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

    /// Affiche du portrait : le poster de l'item, en retombant sur celui de la série
    /// pour un épisode (qui n'a le plus souvent qu'une vignette d'écran).
    func posterURL(for item: MediaItem, maxWidth: Int = 500) -> URL? {
        if let tag = item.imageTags?["Primary"] {
            return imageURL(itemId: item.id, type: .primary, tag: tag, maxWidth: maxWidth)
        }
        if item.type == .episode, let seriesId = item.seriesId {
            return imageURL(itemId: seriesId, type: .primary, tag: item.seriesPrimaryImageTag, maxWidth: maxWidth)
        }
        return nil
    }

    /// Affiche du paysage : vignette d'épisode, sinon backdrop, sinon poster.
    func thumbURL(for item: MediaItem, maxWidth: Int = 780) -> URL? {
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
    func backdropURL(for item: MediaItem, maxWidth: Int = 1920) -> URL? {
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
    func logoURL(for item: MediaItem, maxWidth: Int = 640) -> URL? {
        if let tag = item.imageTags?["Logo"] {
            return imageURL(itemId: item.id, type: .logo, tag: tag, maxWidth: maxWidth)
        }
        if let seriesId = item.seriesId {
            return imageURL(itemId: seriesId, type: .logo, maxWidth: maxWidth)
        }
        return nil
    }

    func personImageURL(for person: Person, maxWidth: Int = 300) -> URL? {
        guard let id = person.id, let tag = person.primaryImageTag else { return nil }
        return imageURL(itemId: id, type: .primary, tag: tag, maxWidth: maxWidth)
    }
}
