import JellyfinKit
import SwiftUI

struct HomeView: View {
    @Environment(AppSession.self) private var session
    /// La pile appartient à `MainTabView`, qui doit pouvoir la vider depuis la barre d'onglets.
    @Binding var path: NavigationPath

    @State private var model = HomeModel()
    @State private var spotlight: MediaItem?
    @State private var playback: PlaybackRequest?
    @State private var resumeCandidate: MediaItem?
    @Namespace private var contentFocus
    @FocusState private var heroPlayFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                if model.isLoading {
                    LoadingView()
                } else if let error = model.errorMessage {
                    EmptyStateView(icon: "exclamationmark.triangle", title: "Rien à afficher", message: error)
                } else {
                    content
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationDestination(for: MediaItem.self) { item in
                DetailView(item: item)
            }
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(item: request.item, startTime: request.startTime)
        }
        .resumeChoice(for: $resumeCandidate) { playback = $0 }
        // Rechargé aussi après un « vu » ou un favori, et au retour d'une lecture,
        // pour que les rangées reflètent l'état réel du serveur.
        .task(id: session.libraryRevision) { await model.load(using: session.api) }
        .onChange(of: playback) { previous, current in
            guard previous != nil, current == nil else { return }
            // Le lecteur signale sa position au serveur en quittant, sans attendre
            // de réponse. Recharger dans la foulée interrogerait Jellyfin avant
            // qu'il ait enregistré la progression, et « Reprendre la lecture »
            // resterait tel quel jusqu'au prochain passage sur l'écran.
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                session.libraryDidChange()
            }
        }
        // Le contenu n'existe pas encore au premier rendu : le focus est réclamé
        // dès que le billboard est réellement affiché, faute de quoi tvOS le laisse
        // sur la barre latérale et l'ouvre.
        .onChange(of: model.isLoading) { _, isLoading in
            if !isLoading { heroPlayFocused = true }
        }
        // Les actions de l'étagère du haut atterrissent ici : c'est l'écran racine
        // de l'onglet initial, donc le seul toujours monté au lancement.
        .task(id: session.pendingDeepLink) { await followDeepLink() }
    }

    private var content: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
                if let hero = spotlight ?? model.featured.first {
                    HeroBillboard(
                        item: hero,
                        namespace: contentFocus,
                        playFocused: $heroPlayFocused,
                        onPlay: { play($0) },
                        onDetails: { navigate(to: $0) }
                    )
                    .padding(.bottom, 12)
                }

                ForEach(model.sections) { section in
                    MediaRow(
                        title: section.title,
                        items: section.items,
                        layout: section.layout,
                        onFocus: { spotlight = $0 },
                        onOpenDetails: { navigate(to: $0) },
                        onSelect: { select($0) }
                    )
                }
            }
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        // Portée de focus de l'accueil : sans elle, l'app s'ouvre sur la barre
        // latérale déployée au lieu du contenu.
        .focusScope(contentFocus)
    }

    /// Un titre entamé demande d'abord où reprendre ; tout le reste ouvre sa fiche.
    /// Lancer une lecture reste possible d'un appui long, ou depuis la fiche.
    private func select(_ item: MediaItem) {
        if item.resumePosition != nil {
            resumeCandidate = item
        } else {
            navigate(to: item)
        }
    }

    private func navigate(to item: MediaItem) {
        path.append(item)
    }

    /// Depuis le billboard : proposer le choix si le titre est entamé, sinon lancer.
    private func play(_ item: MediaItem) {
        // Une collection n'a pas de lecture propre : elle mène à sa fiche, seul
        // endroit où l'on sait quel film de la saga lancer.
        if item.type == .boxSet {
            navigate(to: item)
        } else if item.resumePosition != nil {
            resumeCandidate = item
        } else {
            playback = PlaybackRequest(item)
        }
    }

    /// L'étagère ne transmet qu'un identifiant : il faut recharger la fiche complète
    /// avant de pouvoir lire ou naviguer.
    private func followDeepLink() async {
        guard let destination = session.consumeDeepLink() else { return }

        switch destination {
        case .play(let itemId):
            guard let item = try? await session.api.item(id: itemId) else { return }
            path = NavigationPath()
            playback = PlaybackRequest(item)
        case .details(let itemId):
            guard let item = try? await session.api.item(id: itemId) else { return }
            path = NavigationPath()
            path.append(item)
        }
    }
}
