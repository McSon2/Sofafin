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
        .animation(.easeInOut(duration: 0.35), value: session.phase)
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
    @State private var searchPath = NavigationPath()
    @State private var libraryPaths: [String: NavigationPath] = [:]

    enum AppTab: Hashable {
        case home
        case library(String)
        case search
        case settings
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

            Tab("Rechercher", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView(path: $searchPath)
            }

            Tab("Réglages", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background(Theme.Palette.background)
    }

    /// Choisir un onglet dans la barre le ramène à sa racine — y compris l'onglet
    /// déjà actif, où c'est le seul geste disponible pour quitter une fiche.
    private var tabSelection: Binding<AppTab> {
        Binding {
            selection
        } set: { destination in
            popToRoot(destination)
            selection = destination
        }
    }

    private func popToRoot(_ tab: AppTab) {
        switch tab {
        case .home:
            homePath = NavigationPath()
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
