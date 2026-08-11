import JellyfinKit
import SwiftUI

/// Bibliothèque complète en grille, avec tri et filtres.
struct LibraryView: View {
    @Environment(AppSession.self) private var session
    let library: MediaItem
    @Binding var path: NavigationPath

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var sort: SortOption = .dateAdded
    @State private var ascending = SortOption.dateAdded.defaultAscending
    @State private var watchFilter: WatchFilter = .all
    @State private var playback: PlaybackRequest?
    @State private var resumeCandidate: MediaItem?
    @State private var totalCount = 0
    @State private var loadFailure: String?
    /// Portée de focus de l'écran : sans cible désignée, le moteur ouvre la
    /// bibliothèque sur le menu « Trier par » — la barre de filtres étant dessinée
    /// avant la grille — au lieu de la première affiche.
    @Namespace private var gridFocus

    enum SortOption: String, CaseIterable, Identifiable {
        case dateAdded, title, year, rating
        var id: String { rawValue }

        var label: String {
            switch self {
            case .dateAdded: return "Ajout récent"
            case .title: return "Titre"
            case .year: return "Année"
            case .rating: return "Note"
            }
        }

        var field: String {
            switch self {
            case .dateAdded: return "DateCreated"
            case .title: return "SortName"
            case .year: return "ProductionYear"
            case .rating: return "CommunityRating"
            }
        }

        /// Sens appliqué la première fois qu'on choisit ce tri : le plus utile
        /// d'emblée — ajouts récents, années et meilleures notes en tête, mais les
        /// titres de A à Z.
        var defaultAscending: Bool { self == .title }
    }

    enum WatchFilter: String, CaseIterable, Identifiable {
        case all, unwatched, watched, favorites
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "Tout"
            case .unwatched: return "Non vus"
            case .watched: return "Vus"
            case .favorites: return "Favoris"
            }
        }

        /// `nil` = pas de filtre sur l'état de lecture.
        var isPlayed: Bool? {
            switch self {
            case .unwatched: return false
            case .watched: return true
            case .all, .favorites: return nil
            }
        }
    }

    private let columns = Array(
        repeating: GridItem(.fixed(Theme.Metrics.posterWidth), spacing: Theme.Metrics.cardSpacing),
        count: Theme.Metrics.gridColumns
    )

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    // La grille est dessinée après la barre et déborde vers le haut
                    // (son rognage est désactivé pour ne pas couper l'agrandissement
                    // au focus) : sans ce plan et ce fond, les affiches passeraient
                    // par-dessus les filtres.
                    toolbar
                        .background {
                            LinearGradient(
                                stops: [
                                    .init(color: Theme.Palette.background, location: 0.0),
                                    .init(color: Theme.Palette.background, location: 0.75),
                                    .init(color: Theme.Palette.background.opacity(0), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .ignoresSafeArea(edges: .top)
                        }
                        .zIndex(1)

                    if isLoading {
                        LoadingView()
                    } else if let loadFailure {
                        EmptyStateView(
                            icon: "wifi.exclamationmark",
                            title: "Serveur injoignable",
                            message: loadFailure,
                            onRetry: { session.libraryDidChange() }
                        )
                    } else if items.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: "Rien ici",
                            message: "Aucun titre ne correspond à ces filtres."
                        )
                    } else {
                        grid
                    }
                }
                .focusScope(gridFocus)
            }
            .navigationDestination(for: MediaItem.self) { item in
                DetailView(item: item)
            }
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(item: request.item, startTime: request.startTime)
        }
        .resumeChoice(for: $resumeCandidate) { playback = $0 }
        // Deux clés distinctes, parce que les deux causes n'appellent pas le même
        // traitement : changer de tri ou de filtre remplace le contenu et justifie
        // un indicateur de chargement ; une révision de bibliothèque — un « vu »,
        // un favori — ne doit rien démonter.
        .task(id: queryKey) { await load(silently: false) }
        .task(id: session.libraryRevision) {
            guard !items.isEmpty else { return }
            await load(silently: true)
        }
    }

    private var queryKey: String {
        "\(library.id)-\(sort.rawValue)-\(ascending)-\(watchFilter.rawValue)"
    }

    private var toolbar: some View {
        HStack(spacing: 28) {
            // Les pastilles sont incompressibles : sans priorité ni taille figée,
            // c'est ce titre qui encaissait toute la contrainte et se repliait
            // sur une pile de lignes.
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(library.displayTitle)
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(countLabel)
                    .font(Theme.Font.badge)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
            .lineLimit(1)
            .fixedSize()
            .layoutPriority(1)

            Spacer(minLength: 20)

            if !isCollectionLibrary { watchFilterPicker }
            sortPicker
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .padding(.top, 30)
        .padding(.bottom, 20)
        // Les menus sont calés à droite : sans section de focus, remonter depuis
        // une affiche de la colonne de gauche ne trouve aucune cible au-dessus
        // d'elle et le focus reste coincé dans la grille. C'est exactement le
        // repli que `MediaRow` déclare pour les rangées horizontales.
        .focusSection()
    }

    private var countLabel: String {
        isCollectionLibrary
            ? (totalCount == 1 ? "1 collection" : "\(totalCount) collections")
            : "\(totalCount) titres"
    }

    private var watchFilterPicker: some View {
        GlassMenu(title: "Afficher", value: watchFilter.label) {
            ForEach(WatchFilter.allCases) { option in
                MenuCheckItem(title: option.label, isSelected: watchFilter == option) {
                    watchFilter = option
                }
            }
        }
    }

    /// Trier des collections par note ou par année ne produirait qu'un ordre
    /// arbitraire : TMDb ne renseigne ni l'une ni l'autre pour un regroupement.
    private var sortOptions: [SortOption] {
        isCollectionLibrary ? [.title, .dateAdded] : SortOption.allCases
    }

    /// Le tri porte deux informations : le critère et son sens. Choisir un critère
    /// applique son sens naturel, le re-choisir inverse l'ordre — pas besoin d'une
    /// commande séparée pour ça.
    private var sortPicker: some View {
        GlassMenu(
            title: "Trier par",
            value: sort.label,
            symbol: ascending ? "arrow.up" : "arrow.down"
        ) {
            ForEach(sortOptions) { option in
                MenuCheckItem(title: option.label, isSelected: sort == option) {
                    if sort == option {
                        ascending.toggle()
                    } else {
                        sort = option
                        ascending = option.defaultAscending
                    }
                }
            }
        }
    }

    private var grid: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: 46) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PosterCard(item: item, onOpenDetails: { path.append(item) }) { select(item) }
                        // La première affiche est la cible d'ouverture de l'écran.
                        .prefersDefaultFocus(index == 0, in: gridFocus)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 40)
        }
        // Rognage conservé, contrairement aux rangées horizontales : un ScrollView
        // non rogné dessine hors de la hiérarchie normale et passerait par-dessus
        // la barre de filtres pendant le défilement. Le rembourrage intérieur
        // suffit ici à absorber l'agrandissement au focus.
    }

    /// Un titre entamé demande où reprendre ; les autres ouvrent leur fiche.
    private func select(_ item: MediaItem) {
        if item.resumePosition != nil {
            resumeCandidate = item
        } else {
            path.append(item)
        }
    }

    /// Une bibliothèque de collections ne se filtre pas comme une médiathèque :
    /// un regroupement n'est ni vu ni non vu, et n'a ni note ni année.
    private var isCollectionLibrary: Bool { library.collectionType == .boxsets }

    private var includedTypes: [String] {
        switch library.collectionType {
        case .tvshows: return ["Series"]
        case .boxsets: return ["BoxSet"]
        default: return ["Movie"]
        }
    }

    /// `silently` : recharger sans vider la grille. Un « marquer comme vu » depuis
    /// le menu d'une vignette faisait jusqu'ici disparaître les affiches derrière
    /// un indicateur de chargement, et le focus repartait de la première case.
    private func load(silently: Bool) async {
        isLoading = !silently && items.isEmpty
        if !silently { loadFailure = nil }

        let filters = watchFilter == .favorites ? ["IsFavorite"] : []
        do {
            let response = try await session.api.items(
                parentId: library.id,
                includeTypes: includedTypes,
                sortBy: sort.field,
                sortOrder: ascending ? "Ascending" : "Descending",
                filters: isCollectionLibrary ? [] : filters,
                isPlayed: isCollectionLibrary ? nil : watchFilter.isPlayed,
                limit: 300,
                // Le nombre de titres tient lieu de sous-titre sous une affiche de
                // collection, l'année étant presque toujours absente.
                fields: isCollectionLibrary ? ItemFieldSet.list + ",ChildCount" : ItemFieldSet.list
            )
            guard !Task.isCancelled else { return }
            let received = response.items ?? []
            items = received
            totalCount = response.totalRecordCount ?? received.count
            loadFailure = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            // Un rafraîchissement de fond qui échoue laisse la grille en place :
            // l'utilisateur n'a rien demandé, lui retirer son contenu serait pire
            // que de lui montrer un état d'un instant périmé.
            if !silently { loadFailure = error.localizedDescription }
        }
        isLoading = false
    }
}
