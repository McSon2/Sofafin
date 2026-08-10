import JellyfinKit
import SwiftUI

/// Le grand visuel d'ouverture : image plein cadre, logo du titre, synopsis court
/// et deux actions. C'est la pièce maîtresse de l'accueil — elle suit l'élément
/// survolé dans les rangées, comme sur les services de streaming.
struct HeroBillboard: View {
    @Environment(AppSession.self) private var session
    let item: MediaItem
    /// Portée de focus de l'accueil : c'est elle qui permet de désigner le bouton
    /// de lecture comme cible par défaut, pour que l'app n'ouvre pas sur la barre
    /// latérale déployée.
    let namespace: Namespace.ID
    /// Le contenu arrive après le premier rendu ; il faut donc pouvoir réclamer le
    /// focus une fois le billboard réellement à l'écran.
    @FocusState.Binding var playFocused: Bool
    let onPlay: (MediaItem) -> Void
    let onDetails: (MediaItem) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: session.api.backdropURL(for: item))
                .frame(maxWidth: .infinity)
                .frame(height: 760)
                .clipped()
                .overlay(LinearGradient.heroSideScrim)
                .overlay(LinearGradient.heroScrim)
                .id(item.id) // force le fondu quand la sélection change

            content
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.bottom, 60)
        }
        .frame(height: 760)
        .animation(.easeInOut(duration: 0.4), value: item.id)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            titleBlock

            if item.type == .episode, let series = item.seriesName {
                Text([series, item.episodeCode, item.name].compactMap(\.self).joined(separator: " · "))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            MetadataLine(item: item)

            if let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(3)
                    .frame(maxWidth: 900, alignment: .leading)
            }

            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Le logo officiel du titre quand Jellyfin en a un ; sinon un titre typographié.
    @ViewBuilder
    private var titleBlock: some View {
        if let logo = session.api.logoURL(for: item) {
            AsyncImage(url: logo) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 620, maxHeight: 200, alignment: .leading)
                } else {
                    fallbackTitle
                }
            }
        } else {
            fallbackTitle
        }
    }

    private var fallbackTitle: some View {
        Text(item.rowTitle)
            .font(Theme.Font.heroTitle)
            .foregroundStyle(Theme.Palette.primaryText)
            .shadow(color: .black.opacity(0.6), radius: 18, y: 6)
            .lineLimit(2)
            .frame(maxWidth: 1000, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 22) {
            Button {
                onPlay(item)
            } label: {
                Label(playLabel, systemImage: isCollection ? "rectangle.stack.fill" : "play.fill")
                    .font(Theme.Font.cardTitle)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .prefersDefaultFocus(true, in: namespace)
            .focused($playFocused)

            // Une collection n'ouvre que sur sa fiche : deux boutons y mèneraient
            // au même endroit.
            if !isCollection {
                Button {
                    onDetails(item)
                } label: {
                    Label("Plus d'infos", systemImage: "info.circle")
                        .font(Theme.Font.cardTitle)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.top, 10)
    }

    private var isCollection: Bool { item.type == .boxSet }

    private var playLabel: String {
        if isCollection { return "Voir la collection" }
        return item.resumePosition != nil ? "Reprendre" : "Lecture"
    }
}
