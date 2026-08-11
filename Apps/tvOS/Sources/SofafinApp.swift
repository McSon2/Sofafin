import JellyfinKit
import SwiftUI

@main
struct SofafinApp: App {
    @State private var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase
    /// La langue choisie est propagée par l'environnement : c'est ce qui fait
    /// changer les `Text` de toute l'interface sans redémarrer l'application.
    @AppStorage("appLanguage") private var language: AppLanguage = .system

    init() {
        // Une médiathèque affiche des centaines d'affiches : sans cache disque
        // généreux, chaque retour à l'accueil les retélécharge.
        URLCache.shared = URLCache(
            memoryCapacity: 128 * 1024 * 1024,
            diskCapacity: 1024 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.dark)
                .environment(\.locale, language.locale ?? .autoupdatingCurrent)
                // Reconstruit l'arbre au changement de langue : sans cela, les
                // vues déjà rendues garderaient les chaînes résolues dans
                // l'ancienne langue jusqu'à ce qu'une autre raison les rafraîchisse.
                .id(language)
                .task { await session.restore() }
                .onOpenURL { session.handle($0) }
                // Le serveur vit sans nous : un épisode regardé sur le téléphone
                // pendant que l'application dormait doit se voir dès qu'on la
                // retrouve, sans avoir à changer d'onglet pour la forcer.
                .onChange(of: scenePhase) { previous, phase in
                    guard phase == .active, previous != .active, session.phase == .ready else { return }
                    session.libraryDidChange()
                }
        }
    }
}
