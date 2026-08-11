import AVKit
import JellyfinKit
import SwiftUI

/// Lecture plein écran.
///
/// Tout le travail est dans `PlaybackEngine` : cette vue ne fait que présenter le
/// contrôleur d'AVKit, le relier au moteur, et couvrir l'attente initiale.
struct PlayerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let item: MediaItem
    /// Position imposée (reprise choisie dans une fiche, par exemple).
    var startTime: Double?

    @State private var engine = PlaybackEngine()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Le conteneur existe dès le premier instant et ne repart jamais :
            // c'est ce qui permet d'enchaîner les épisodes dans le même lecteur.
            PlayerContainer(engine: engine)
                .ignoresSafeArea()

            if case .failed(let message) = engine.phase {
                VStack(spacing: 26) {
                    EmptyStateView(
                        icon: "exclamationmark.triangle.fill",
                        title: "Lecture impossible",
                        message: message
                    )
                    Button("Fermer") { dismiss() }
                        .buttonStyle(.glass)
                }
            } else if engine.phase == .loading {
                // Opaque, et jusqu'à ce que la lecture démarre pour de bon : le
                // lecteur affiche la première image du film dès qu'il a de quoi
                // décoder, avant même d'avoir rejoint la position de reprise.
                // Laisser paraître cette image donne à croire que le film
                // recommence au début.
                ZStack {
                    Color.black
                    VStack(spacing: 24) {
                        ProgressView().tint(.white).scaleEffect(1.6)
                        Text("Préparation de la lecture…")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .task {
            // Les affiches et le flux vidéo sortent du même serveur : tant que la
            // lecture dure, la bande passante lui revient entièrement.
            ImagePrefetcher.shared.setSuspended(true)
            engine.configure(client: session.api)
            engine.onDismiss = { dismiss() }
            await engine.start(item, startTime: startTime)
        }
        // Filet de sécurité sur le bouton Menu, dont les directives font la seule
        // sortie possible de n'importe quel écran. Un `AVPlayerViewController`
        // présenté par le système se ferme tout seul ; celui-ci est **embarqué**
        // dans un `fullScreenCover`, et rien ne garantit qu'il consomme
        // l'événement — auquel cas l'écran de lecture n'aurait aucune issue.
        // Si AVKit le traite déjà, ce gestionnaire n'est jamais appelé.
        .onExitCommand { dismiss() }
        .onDisappear {
            ImagePrefetcher.shared.setSuspended(false)
            // Rafraîchir seulement après que le serveur a enregistré la position :
            // « Reprendre la lecture » afficherait sinon l'état d'avant la séance.
            Task {
                await engine.finish()
                session.libraryDidChange()
            }
        }
    }
}

// MARK: - Pont AVKit

private struct PlayerContainer: UIViewControllerRepresentable {
    let engine: PlaybackEngine

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = engine.player
        controller.delegate = engine
        controller.allowsPictureInPicturePlayback = true
        controller.videoGravity = .resizeAspect
        // Le moteur pose ses affordances dessus dès qu'il en connaît le titre.
        engine.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
