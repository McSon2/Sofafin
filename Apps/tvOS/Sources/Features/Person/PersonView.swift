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
    @State private var playbackTarget: MediaItem?

    private let columns = Array(
        repeating: GridItem(.fixed(Theme.Metrics.posterWidth), spacing: Theme.Metrics.cardSpacing),
        count: 6
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
        }
        .navigationDestination(item: $pushedItem) { item in
            DetailView(item: item)
        }
        .fullScreenCover(item: $playbackTarget) { item in
            PlayerView(item: item)
        }
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
                ForEach(items) { item in
                    PosterCard(item: item, onOpenDetails: { pushedItem = item }) { select(item) }
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 40)
        }
    }

    private func select(_ item: MediaItem) {
        if item.resumePosition != nil {
            playbackTarget = item
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
