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

    @State private var position = ScrollPosition()

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 28) {
                ForEach(episodes) { episode in
                    Button { onSelect(episode) } label: {
                        card(for: episode)
                    }
                    .buttonStyle(MediaCardButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(episode.accessibilityDescription)
                    .accessibilityValue(episode.id == currentId ? "En cours de lecture" : "")
                    .accessibilityHint("Bascule la lecture sur cet épisode")
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 60)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
        .scrollPosition($position)
        // Ouvrir la liste sur l'épisode regardé : sans cela une saison de
        // vingt épisodes commence toujours au premier. `initial: true` remplace
        // l'ancien `onAppear`, et suit en plus les changements d'épisode quand la
        // lecture enchaîne sans que le panneau soit démonté.
        .onChange(of: currentId, initial: true) { _, id in
            position.scrollTo(id: id, anchor: .leading)
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
                    CastPortrait(person: person, client: client)
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
    }
}

/// Un portrait de la rangée.
///
/// Il porte son propre `FocusState` : `focusable()` seul déplace bien le focus,
/// mais **sans rien changer à l'écran**. La rangée devenait alors un espace où
/// l'on navigue à l'aveugle — la faute la plus grave qu'une interface de
/// télévision puisse commettre, l'état de focus étant le seul repère disponible.
private struct CastPortrait: View {
    let person: Person
    let client: JellyfinClient

    @FocusState private var isFocused: Bool

    var body: some View {
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
        .brightness(isFocused ? 0.06 : 0)
        .focusLift(isFocused)
        .focusable()
        .focused($isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [person.name, person.role]
                .compactMap(\.self)
                .filter { !$0.isEmpty }
                .joined(separator: ", rôle : ")
        )
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
        .decorativeAnimation(.easeInOut(duration: 0.6), value: isVisible)
        .task {
            try? await Task.sleep(for: .seconds(5))
            isVisible = false
        }
    }
}
