import JellyfinKit
import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .restoring:
                ZStack {
                    Theme.Palette.background.ignoresSafeArea()
                    LoadingView()
                }
            case .needsServer, .needsSignIn:
                ConnectView()
            case .ready:
                MainTabView()
            }
        }
        .decorativeAnimation(.easeInOut(duration: 0.35), value: session.phase)
    }
}

/// Navigation principale. `sidebarAdaptable` donne sur tvOS 26 la barre latérale
/// escamotable qui laisse le contenu occuper tout l'écran — le comportement
/// qu'on attend d'une application de streaming.
struct MainTabView: View {
    @Environment(AppSession.self) private var session

    /// Les piles de navigation vivent ici, et non dans chaque écran : c'est la
    /// seule façon de les vider quand on choisit un onglet dans la barre.
    @State private var selection: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var genresPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var libraryPaths: [String: NavigationPath] = [:]

    /// Onglet quitté la dernière fois. Retrouver l'application là où on l'a
    /// laissée est une attente de base sur un téléviseur : on y revient souvent
    /// pour poursuivre exactement ce qu'on faisait.
    @AppStorage("lastSelectedTab") private var storedTab: String = AppTab.home.storageKey

    enum AppTab: Hashable {
        case home
        case library(String)
        case genres
        case search
        case settings

        var storageKey: String {
            switch self {
            case .home: return "home"
            case .genres: return "genres"
            case .search: return "search"
            case .settings: return "settings"
            case .library(let id): return "library:\(id)"
            }
        }

        /// `nil` quand la clé ne correspond à rien de connu — une bibliothèque
        /// retirée du serveur depuis la dernière session, par exemple.
        static func from(storageKey: String, libraries: [MediaItem]) -> AppTab? {
            switch storageKey {
            case "home": return .home
            case "genres": return .genres
            case "search": return .search
            case "settings": return .settings
            default:
                guard let id = storageKey.split(separator: ":", maxSplits: 1).last.map(String.init),
                      libraries.contains(where: { $0.id == id })
                else { return nil }
                return .library(id)
            }
        }
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Accueil", systemImage: "house.fill", value: AppTab.home) {
                HomeView(path: $homePath)
            }

            ForEach(session.libraries) { library in
                Tab(library.displayTitle, systemImage: icon(for: library), value: AppTab.library(library.id)) {
                    LibraryView(library: library, path: libraryPath(library.id))
                }
            }

            Tab("Genres", systemImage: "theatermasks.fill", value: AppTab.genres) {
                GenresView(path: $genresPath)
            }

            Tab("Rechercher", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView(path: $searchPath)
            }

            Tab("Réglages", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background(Theme.Palette.background)
        // Les bibliothèques sont déjà chargées quand cette vue apparaît : la clé
        // enregistrée peut donc être confrontée à ce que le serveur propose
        // réellement, et retomber sur l'accueil si l'onglet a disparu.
        .onAppear {
            if let restored = AppTab.from(storageKey: storedTab, libraries: session.libraries) {
                selection = restored
            }
        }
    }

    /// Choisir un onglet dans la barre le ramène à sa racine — y compris l'onglet
    /// déjà actif, où c'est le seul geste disponible pour quitter une fiche.
    private var tabSelection: Binding<AppTab> {
        Binding {
            selection
        } set: { destination in
            popToRoot(destination)
            selection = destination
            storedTab = destination.storageKey
        }
    }

    private func popToRoot(_ tab: AppTab) {
        switch tab {
        case .home:
            homePath = NavigationPath()
        case .genres:
            genresPath = NavigationPath()
        case .search:
            searchPath = NavigationPath()
        case .library(let id):
            libraryPaths[id] = NavigationPath()
        case .settings:
            break
        }
    }

    private func libraryPath(_ id: String) -> Binding<NavigationPath> {
        Binding {
            libraryPaths[id] ?? NavigationPath()
        } set: { newValue in
            libraryPaths[id] = newValue
        }
    }

    private func icon(for library: MediaItem) -> String {
        switch library.collectionType {
        case .movies: return "film.fill"
        case .tvshows: return "tv.fill"
        default: return "square.stack.fill"
        }
    }
}
