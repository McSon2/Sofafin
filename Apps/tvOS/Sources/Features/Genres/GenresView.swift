import JellyfinKit
import SwiftUI

/// Les genres de la médiathèque, chacun illustré par un de ses films.
///
/// Une bibliothèque se parcourt par ordre d'ajout ou par titre ; cette page
/// répond à une autre question — « j'ai envie d'une comédie » — que ni la grille
/// ni la recherche ne servent bien.
struct GenresView: View {
    @Environment(AppSession.self) private var session
    @Binding var path: NavigationPath

    @State private var showcases: [GenreShowcase] = []
    @State private var isLoading = true
    @State private var loadFailure: String?
    /// Sans cible désignée, le moteur de focus ouvre l'écran sur la barre
    /// d'onglets plutôt que sur la première carte.
    @Namespace private var gridFocus

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Theme.Metrics.landscapeWidth), spacing: 46),
              count: 4)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && showcases.isEmpty {
                    ProgressView().tint(.white).scaleEffect(1.6)
                } else if let loadFailure {
                    EmptyStateView(
                        icon: "exclamationmark.triangle.fill",
                        title: "Genres indisponibles",
                        message: loadFailure
                    )
                } else if showcases.isEmpty {
                    EmptyStateView(
                        icon: "theatermasks",
                        title: "Aucun genre",
                        message: "Les genres viennent des métadonnées de vos films : ils apparaîtront une fois la médiathèque analysée."
                    )
                } else {
                    grid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.background)
            .focusScope(gridFocus)
            .navigationDestination(for: Genre.self) { genre in
                GenreView(genre: genre, path: $path)
            }
            .navigationDestination(for: MediaItem.self) { item in
                DetailView(item: item)
            }
        }
        .task { await load() }
    }

    private var grid: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: 46) {
                ForEach(Array(showcases.enumerated()), id: \.element.id) { index, showcase in
                    GenreCard(showcase: showcase) { path.append(showcase.genre) }
                        .prefersDefaultFocus(index == 0, in: gridFocus)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 40)
        }
    }

    private func load() async {
        // Rechargement silencieux : revenir d'une fiche ne doit pas faire
        // clignoter la page entière alors que les genres n'ont pas bougé.
        if showcases.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            showcases = try await session.api.movieGenresWithArtwork()
            loadFailure = nil
        } catch {
            loadFailure = error.localizedDescription
        }
    }
}

/// Carte d'un genre : l'affiche d'un de ses films, assombrie, et son nom.
///
/// L'assombrissement n'est pas décoratif — il rend le nom lisible quelle que soit
/// l'affiche, y compris les plus claires, sans avoir à poser un cartouche opaque
/// qui masquerait l'image.
struct GenreCard: View {
    @Environment(AppSession.self) private var session
    let showcase: GenreShowcase
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                if let artwork = showcase.artwork {
                    RemoteImage(url: session.api.thumbURL(for: artwork))
                } else {
                    Theme.Palette.surface
                }

                LinearGradient(
                    colors: [.black.opacity(0.15), .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(showcase.name)
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(20)
            }
            .frame(width: Theme.Metrics.landscapeWidth, height: Theme.Metrics.landscapeHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
            .focusParallax(isFocused)
        }
        .buttonStyle(.mediaCard)
        .focused($isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showcase.name)
        .accessibilityHint("Ouvre les films de ce genre")
    }
}
