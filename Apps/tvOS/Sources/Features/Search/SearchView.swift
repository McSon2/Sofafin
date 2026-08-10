import JellyfinKit
import SwiftUI

struct SearchView: View {
    @Environment(AppSession.self) private var session

    @Binding var path: NavigationPath

    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var playback: PlaybackRequest?
    @State private var resumeCandidate: MediaItem?

    private let columns = Array(
        repeating: GridItem(.fixed(Theme.Metrics.posterWidth), spacing: Theme.Metrics.cardSpacing),
        count: 5
    )

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                if query.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "Rechercher",
                        message: "Titre de film, de série ou d'épisode."
                    )
                } else if isSearching && results.isEmpty {
                    LoadingView()
                } else if results.isEmpty {
                    EmptyStateView(
                        icon: "questionmark.folder",
                        title: "Aucun résultat",
                        message: "Rien ne correspond à « \(query) »."
                    )
                } else {
                    grid
                }
            }
            .searchable(text: $query, prompt: "Rechercher un titre")
            .navigationDestination(for: MediaItem.self) { item in
                DetailView(item: item)
            }
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(item: request.item, startTime: request.startTime)
        }
        .resumeChoice(for: $resumeCandidate) { playback = $0 }
        .task(id: query) { await search() }
    }

    private var grid: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: 46) {
                ForEach(results) { item in
                    PosterCard(item: item, onOpenDetails: { path.append(item) }) { select(item) }
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
    }

    /// Un titre entamé demande où reprendre ; les autres ouvrent leur fiche.
    private func select(_ item: MediaItem) {
        if item.resumePosition != nil {
            resumeCandidate = item
        } else {
            path.append(item)
        }
    }

    /// Anti-rebond : la saisie à la télécommande produit un caractère à la fois,
    /// inutile d'interroger le serveur à chaque lettre.
    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        results = (try? await session.api.search(term, limit: 60)) ?? []
        isSearching = false
    }
}
