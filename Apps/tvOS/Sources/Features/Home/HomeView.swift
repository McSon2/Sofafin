import JellyfinKit
import SwiftUI

struct HomeView: View {
    @Environment(AppSession.self) private var session
    /// La pile appartient à `MainTabView`, qui doit pouvoir la vider depuis la barre d'onglets.
    @Binding var path: NavigationPath

    @State private var model = HomeModel()
    @State private var spotlight: MediaItem?
    /// Dernière vignette effleurée, pas encore promue au billboard — voir
    /// `spotlightDebounce`.
    @State private var spotlightCandidate: MediaItem?
    @State private var playback: PlaybackRequest?
    @State private var resumeCandidate: MediaItem?
    @Namespace private var contentFocus
    @FocusState private var heroPlayFocused: Bool
    /// Le focus initial ne se réclame qu'**une fois**. L'accueil se recharge à
    /// chaque « vu », chaque favori, chaque retour de lecture et chaque retour au
    /// premier plan : le refaire à chaque fois arracherait le focus des mains de
    /// l'utilisateur pour le ramener sur le billboard.
    @State private var hasClaimedInitialFocus = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                if model.isLoading {
                    LoadingView()
                } else if let failure = model.failure {
                    EmptyStateView(
                        icon: failure.icon,
                        title: failure.title,
                        message: failure.message,
                        onRetry: failure.isRetryable ? { session.libraryDidChange() } : nil
                    )
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
        // pour que les rangées reflètent l'état réel du serveur. Ces rechargements
        // sont silencieux : les rangées restent à l'écran et se mettent à jour en
        // place, au lieu de céder la place à un indicateur de chargement.
        .task(id: session.libraryRevision) {
            await model.load(using: session.api, silently: hasClaimedInitialFocus)
        }
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
            guard !isLoading, !hasClaimedInitialFocus, model.failure == nil else { return }
            hasClaimedInitialFocus = true
            heroPlayFocused = true
        }
        // Les actions de l'étagère du haut atterrissent ici : c'est l'écran racine
        // de l'onglet initial, donc le seul toujours monté au lancement.
        .task(id: session.pendingDeepLink) { await followDeepLink() }
        .task(id: spotlightCandidate?.id) { await spotlightDebounce() }
    }

    /// Le billboard suit le focus, mais avec un temps de retard.
    ///
    /// Chaque promotion recharge une image plein cadre de 760 pt et enchaîne un
    /// fondu : traverser une rangée d'une traite en déclenchait autant qu'il y a de
    /// vignettes survolées. Un quart de seconde de stabilité suffit à ne retenir
    /// que la vignette sur laquelle l'utilisateur s'arrête vraiment.
    private func spotlightDebounce() async {
        guard let candidate = spotlightCandidate else { return }
        // La toute première promotion est immédiate : l'écran est encore sur le
        // titre mis en avant par défaut, attendre y serait perçu comme une latence.
        if spotlight != nil {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        spotlight = candidate
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
                        onFocus: { spotlightCandidate = $0 },
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
