import JellyfinKit
import SwiftUI

/// Tout ce que la médiathèque contient avec cette personne — acteur, réalisateur
/// ou scénariste. Le point d'entrée est la distribution d'une fiche.
struct PersonView: View {
    @Environment(AppSession.self) private var session
    let person: Person

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var pushedItem: MediaItem?
    @State private var playback: PlaybackRequest?
    @State private var resumeCandidate: MediaItem?
    @Namespace private var gridFocus

    private let columns = Array(
        repeating: GridItem(.fixed(Theme.Metrics.posterWidth), spacing: Theme.Metrics.cardSpacing),
        count: Theme.Metrics.gridColumns
    )

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                if isLoading {
                    LoadingView()
                } else if items.isEmpty {
                    EmptyStateView(
                        icon: "person.slash",
                        title: "Aucun titre",
                        message: "Rien dans ta médiathèque avec \(person.name ?? "cette personne")."
                    )
                } else {
                    grid
                }
            }
            .focusScope(gridFocus)
        }
        .navigationDestination(item: $pushedItem) { item in
            DetailView(item: item)
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(item: request.item, startTime: request.startTime)
        }
        .resumeChoice(for: $resumeCandidate) { playback = $0 }
        .task(id: session.libraryRevision) { await load() }
    }

    private var header: some View {
        HStack(spacing: 28) {
            RemoteImage(url: session.api.personImageURL(for: person, maxWidth: 300))
                .frame(width: 140, height: 140)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(person.name ?? "Sans nom")
                    .font(Theme.Font.heroTitle)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .padding(.top, 40)
        .padding(.bottom, 24)
    }

    private var subtitle: String {
        let count = items.count
        guard count > 0 else { return " " }
        return count == 1 ? "1 titre" : "\(count) titres"
    }

    private var grid: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: 46) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PosterCard(item: item, onOpenDetails: { pushedItem = item }) { select(item) }
                        .prefersDefaultFocus(index == 0, in: gridFocus)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 40)
        }
    }

    /// Même geste, même réponse que partout ailleurs : un titre entamé demande où
    /// reprendre. Cet écran lançait la lecture sans poser la question, ce qui
    /// donnait au même clic deux comportements selon l'endroit d'où on le faisait
    /// — et repartait du début quand l'utilisateur voulait reprendre.
    private func select(_ item: MediaItem) {
        if item.resumePosition != nil {
            resumeCandidate = item
        } else {
            pushedItem = item
        }
    }

    private func load() async {
        guard let id = person.id else {
            isLoading = false
            return
        }
        isLoading = true
        items = (try? await session.api.items(
            includeTypes: ["Movie", "Series"],
            sortBy: "PremiereDate",
            sortOrder: "Descending",
            personIds: [id],
            limit: 200
        ).items) ?? []
        isLoading = false
    }
}
