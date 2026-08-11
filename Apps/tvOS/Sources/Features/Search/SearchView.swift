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

    /// Recherches précédentes, les plus récentes d'abord.
    ///
    /// Taper à la télécommande est le geste le plus coûteux de tvOS : les
    /// directives demandent d'offrir systématiquement une alternative au clavier.
    /// La dictée en est une, fournie par le système ; reproposer ce qu'on a déjà
    /// cherché en est une autre, et ramène une recherche à un seul clic.
    @AppStorage("recentSearches") private var recentSearchesRaw = ""

    // Pas de focus par défaut ici, contrairement aux autres grilles : le champ de
    // recherche doit garder la main tant que l'utilisateur tape.
    private let columns = Array(
        repeating: GridItem(.fixed(Theme.Metrics.posterWidth), spacing: Theme.Metrics.cardSpacing),
        count: Theme.Metrics.gridColumns
    )

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                if query.isEmpty {
                    if recentSearches.isEmpty {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "Rechercher",
                            message: "Titre de film, de série ou d'épisode. Le micro de la télécommande évite d'avoir à taper."
                        )
                    } else {
                        recentSearchesView
                    }
                } else if isSearching && results.isEmpty {
                    LoadingView()
                } else if results.isEmpty {
                    EmptyStateView(
                        icon: "questionmark.folder",
                        title: "Aucun résultat",
                        message: L("Rien ne correspond à « \(query) ».")
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

    // MARK: Recherches récentes

    private var recentSearches: [String] {
        recentSearchesRaw.split(separator: "\n").map(String.init)
    }

    private var recentSearchesView: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Recherches récentes")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.Palette.primaryText)

            // Une pastille par terme, sur deux rangs au plus : au-delà, la liste
            // devient elle-même un obstacle à parcourir.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4),
                alignment: .leading,
                spacing: 20
            ) {
                ForEach(recentSearches, id: \.self) { term in
                    SelectableChip(title: term, isSelected: false) { query = term }
                }
            }

            Button("Effacer l'historique") { recentSearchesRaw = "" }
                .buttonStyle(.glass)
                .font(Theme.Font.badge)
                .padding(.top, 20)
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 60)
    }

    /// N'enregistre que ce qui a réellement abouti : une frappe abandonnée en
    /// cours de route n'a aucune valeur de raccourci.
    private func remember(_ term: String) {
        var terms = recentSearches.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        terms.insert(term, at: 0)
        recentSearchesRaw = terms.prefix(8).joined(separator: "\n")
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
            // Indispensable : une frappe annulée en vol laissait ce drapeau armé.
            // En repassant sous deux caractères, l'écran restait alors bloqué sur
            // un indicateur de chargement qu'aucune recherche n'alimentait plus.
            isSearching = false
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        results = (try? await session.api.search(term, limit: 60)) ?? []
        guard !Task.isCancelled else { return }
        isSearching = false
        if !results.isEmpty { remember(term) }
    }
}
