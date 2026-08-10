import JellyfinKit
import SwiftUI

/// Contenu des panneaux qui s'ouvrent au swipe vers le bas pendant la lecture, et
/// du bandeau superposé à l'image.
///
/// Ces vues vivent dans des `UIHostingController` confiés à AVKit : elles n'ont
/// donc **pas** accès à `AppSession` par l'environnement, et reçoivent le client
/// en paramètre.

// MARK: - Épisodes

/// La saison en cours, pour changer d'épisode sans quitter la lecture.
struct EpisodesPanel: View {
    let episodes: [MediaItem]
    let currentId: String
    let client: JellyfinClient
    let onSelect: (MediaItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(episodes) { episode in
                        Button { onSelect(episode) } label: {
                            card(for: episode)
                        }
                        .buttonStyle(MediaCardButtonStyle())
                        .id(episode.id)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
            // Ouvrir la liste sur l'épisode regardé : sans cela une saison de
            // vingt épisodes commence toujours au premier.
            .onAppear { proxy.scrollTo(currentId, anchor: .leading) }
        }
    }

    private func card(for episode: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteImage(url: client.thumbURL(for: episode, maxWidth: 640))
                .frame(width: 340, height: 191)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if episode.id == currentId {
                        Text("En cours")
                            .font(Theme.Font.badge)
                            .foregroundStyle(Theme.Palette.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Theme.Palette.accent, in: Capsule())
                            .padding(12)
                    }
                }

            Text([episode.episodeCode, episode.name].compactMap(\.self).joined(separator: " · "))
                .font(Theme.Font.badge)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 340, alignment: .leading)
    }
}

// MARK: - Distribution

/// Qui joue dans ce qu'on regarde. Les portraits sont focusables sans être
/// actionnables : c'est ce qui permet de faire défiler la rangée, la fiche d'un
/// acteur n'ayant pas sa place par-dessus une lecture en cours.
struct CastPanel: View {
    let cast: [Person]
    let client: JellyfinClient

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 32) {
                ForEach(cast.prefix(20), id: \.id) { person in
                    VStack(spacing: 12) {
                        RemoteImage(url: client.personImageURL(for: person))
                            .frame(width: 150, height: 150)
                            .clipShape(Circle())

                        Text(person.name ?? "")
                            .font(Theme.Font.badge)
                            .foregroundStyle(Theme.Palette.primaryText)
                            .lineLimit(1)

                        if let role = person.role, !role.isEmpty {
                            Text(role)
                                .font(Theme.Font.badge)
                                .foregroundStyle(Theme.Palette.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: 190)
                    .focusable()
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
    }
}

// MARK: - À propos

/// Le synopsis, et ce que le serveur a réellement décidé d'envoyer — utile quand
/// une lecture chauffe le processeur sans raison apparente.
struct AboutPanel: View {
    let context: PlaybackContext

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                if let overview = context.item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }

                if let genres = context.item.genres, !genres.isEmpty {
                    Text(genres.prefix(5).joined(separator: " · "))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }

                HStack(spacing: 14) {
                    ForEach(technicalTags, id: \.self) { tag in
                        Text(tag)
                            .font(Theme.Font.badge)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .liquidGlass(cornerRadius: 10)
                    }
                }
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(.horizontal, 60)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
        .focusable()
    }

    /// Ce qui décrit la livraison du flux, dans l'ordre où on se pose la question :
    /// comment, en quoi, à quelle définition.
    private var technicalTags: [String] {
        var tags = [context.plan.method.label]

        if let video = context.plan.mediaSource.mediaStreams?.first(where: \.isVideo) {
            if let codec = video.codec { tags.append(codec.uppercased()) }
            if let height = video.height { tags.append("\(height)p") }
            if let range = video.videoRangeType, range != "SDR" { tags.append(range) }
        }
        if let audio = context.plan.mediaSource.mediaStreams?.first(where: \.isAudio),
           let codec = audio.codec {
            tags.append(audio.channels == 6 ? "\(codec.uppercased()) 5.1" : codec.uppercased())
        }
        if let runtime = context.item.runtimeLabel { tags.append(runtime) }
        return tags
    }
}

// MARK: - Bandeau superposé

/// Rappel de ce qui est lu, affiché quelques secondes au démarrage puis effacé.
///
/// Il double volontairement peu de choses : le titre disparaît des contrôles dès
/// qu'ils se masquent, et savoir si le serveur transcode évite d'aller le
/// vérifier dans son tableau de bord.
struct PlaybackBadge: View {
    let title: String
    let subtitle: String?
    let method: String

    @State private var isVisible = true

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(title)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1)

            Text([subtitle, method].compactMap(\.self).joined(separator: " · "))
                .font(Theme.Font.badge)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .liquidGlass(cornerRadius: 16)
        .padding(.trailing, Theme.Metrics.screenPadding)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: isVisible)
        .task {
            try? await Task.sleep(for: .seconds(5))
            isVisible = false
        }
    }
}
