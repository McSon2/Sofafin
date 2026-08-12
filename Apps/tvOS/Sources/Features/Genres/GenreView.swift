import JellyfinKit
import SwiftUI

/// Les films d'un genre, en grille.
///
/// Films seulement : c'est ce que la page de genre annonce, et mêler des séries
/// à la grille obligerait à distinguer deux natures de vignettes là où l'œil
/// cherche simplement quoi regarder ce soir.
struct GenreView: View {
    @Environment(AppSession.self) private var session
    let genre: Genre
    @Binding var path: NavigationPath

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var loadFailure: String?
    @State private var playback: PlaybackRequest?
    @State private var resumeCandidate: MediaItem?
    @Namespace private var gridFocus

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Theme.Metrics.posterWidth), spacing: 46),
              count: Theme.Metrics.gridColumns)
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView().tint(.white).scaleEffect(1.6)
            } else if let loadFailure {
                EmptyStateView(
                    icon: "exclamationmark.triangle.fill",
                    title: "Chargement impossible",
                    message: loadFailure
                )
            } else if items.isEmpty {
                EmptyStateView(
                    icon: "film",
                    title: "Aucun film",
                    message: "Ce genre ne contient aucun film."
                )
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background)
        .focusScope(gridFocus)
        .navigationTitle(genre.name)
        .fullScreenCover(item: $playback) { request in
            PlayerView(item: request.item, startTime: request.startTime)
        }
        .resumeChoice(for: $resumeCandidate) { playback = $0 }
        .task { await load(silently: false) }
        // Une révision de médiathèque — un « vu », un favori — remet la grille à
        // jour sans rien démonter.
        .task(id: session.libraryRevision) {
            guard !items.isEmpty else { return }
            await load(silently: true)
        }
    }

    private var grid: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: 46) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PosterCard(item: item, onOpenDetails: { path.append(item) }) { select(item) }
                        .prefersDefaultFocus(index == 0, in: gridFocus)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 40)
        }
    }

    /// Un titre entamé demande où reprendre ; les autres ouvrent leur fiche.
    private func select(_ item: MediaItem) {
        if item.resumePosition != nil {
            resumeCandidate = item
        } else {
            path.append(item)
        }
    }

    private func load(silently: Bool) async {
        if !silently { isLoading = true }
        defer { isLoading = false }
        do {
            items = try await session.api.items(
                includeTypes: ["Movie"],
                sortBy: "SortName",
                sortOrder: "Ascending",
                genres: [genre.name],
                limit: 300
            ).items ?? []
            loadFailure = nil
        } catch {
            guard !silently else { return }
            loadFailure = error.localizedDescription
        }
    }
}
