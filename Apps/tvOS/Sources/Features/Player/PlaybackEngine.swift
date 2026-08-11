import AVFoundation
import AVKit
import JellyfinKit
import SwiftUI
import UIKit

// MARK: - Contexte

/// Tout ce que le lecteur sait du titre en cours. Rassemblé en une fois au
/// chargement : chaque élément vient d'un appel distinct au serveur, et les
/// disperser dans le temps ferait apparaître les affordances au compte-gouttes.
struct PlaybackContext {
    let plan: PlaybackPlan
    let segments: [MediaSegment]
    /// Épisode qui suit, s'il y en a un — le moteur de la proposition de fin.
    let nextEpisode: MediaItem?
    /// Épisodes de la même saison, pour le panneau d'information.
    let siblings: [MediaItem]

    var item: MediaItem { plan.item }
    var chapters: [ChapterInfo] { item.chapters ?? [] }
}

// MARK: - Moteur

/// Possède l'`AVPlayer` et tout ce qui gravite autour d'une lecture : négociation
/// avec le serveur, reprise, rapports de session, segments à passer, chapitres,
/// proposition de l'épisode suivant.
///
/// L'enchaînement d'épisodes se fait **sans démonter le lecteur** : on remplace
/// l'élément dans le même `AVPlayer`. Fermer puis rouvrir l'écran ferait
/// réapparaître le fond noir, perdrait la position de la télécommande et
/// relancerait une animation de présentation entre deux épisodes.
@MainActor
@Observable
final class PlaybackEngine: NSObject, @MainActor AVPlayerViewControllerDelegate {

    enum Phase: Equatable {
        case loading
        case playing
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var context: PlaybackContext?

    /// Bascule sur l'écran d'échec, sans jamais écraser une cause déjà établie :
    /// c'est le premier échec qui explique, les suivants n'en sont que la suite.
    func markFailed(_ message: String) {
        guard case .failed = phase else {
            phase = .failed(message)
            return
        }
    }

    let player = AVPlayer()

    /// Demande la fermeture de l'écran de lecture.
    var onDismiss: (() -> Void)?

    /// Le contrôleur porte les affordances (bouton flottant, menus, panneaux).
    /// Référence faible : c'est lui qui possède le moteur, pas l'inverse.
    weak var controller: AVPlayerViewController? {
        didSet { applyDecorations() }
    }

    /// Lisible par les extensions du moteur — les décorations interrogent le
    /// serveur pour leurs vignettes.
    private(set) var client: JellyfinClient?

    private var ticker: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    /// Dernier état de transport connu. Pause et reprise sont les instants où le
    /// panneau système doit être réaligné : entre les deux, il extrapole seul
    /// depuis la vitesse annoncée.
    private var lastTimeControlStatus: AVPlayer.TimeControlStatus = .paused

    // Diagnostic — voir `PlaybackEngine+Diagnostics`.
    var failureObserver: NSKeyValueObservation?
    var errorLogObserver: NSObjectProtocol?
    var stallObserver: NSObjectProtocol?
    var startWatchdog: Task<Void, Never>?

    private var tickCount = 0
    private var lastPosition: Double = 0
    /// Écritures serveur en vol, à attendre avant de rendre la main.
    private var pendingWork: [Task<Void, Never>] = []
    /// Segment actuellement proposé au saut : sert à ne reconstruire le bouton
    /// que sur un vrai changement. Le reconstruire à chaque battement le ferait
    /// clignoter et lui volerait le focus.
    var offeredSegmentId: String?
    private var hasStopped = false

    // MARK: Cycle de vie

    func configure(client: JellyfinClient) {
        self.client = client
        // Déclare l'usage de la session audio — lecture d'un film — sans l'activer :
        // c'est AVKit qui s'en charge au démarrage du flux.
        Self.configureAudioSession()
    }

    /// Première lecture de la session.
    func start(_ item: MediaItem, startTime: Double?) async {
        await load(item, startTime: startTime, previousDidFinish: false)
    }

    /// Bascule vers un autre titre sans quitter le lecteur.
    /// `previousDidFinish` distingue l'enchaînement automatique — l'épisode
    /// précédent est alors rapporté comme terminé — d'un choix manuel.
    func play(_ item: MediaItem, startTime: Double?, previousDidFinish: Bool = false) {
        Task { await load(item, startTime: startTime, previousDidFinish: previousDidFinish) }
    }

    /// Arrêt définitif : c'est cet appel qui enregistre la position de reprise et
    /// libère le processus de transcodage resté ouvert côté serveur.
    ///
    /// `position` permet de rapporter une fin de média — un saut de générique ne
    /// passe pas par la dernière seconde, et sans elle Jellyfin garderait le titre
    /// dans « Reprendre la lecture ».
    func stop(reporting position: Double? = nil) {
        guard !hasStopped else { return }
        hasStopped = true
        detachObservers()
        reportStop(position: position ?? currentPosition)
        player.pause()
        player.replaceCurrentItem(with: nil)
        // Les gestionnaires de commande retiennent le moteur : les laisser en place
        // ferait agir la télécommande sur un lecteur déjà fermé.
        unregisterRemoteCommands()
        clearNowPlaying()
    }

    /// Termine comme si le média était allé à son terme, puis ferme l'écran.
    func finishAndClose() {
        stop(reporting: context?.item.runtime)
        onDismiss?()
    }

    /// Marque explicitement le titre comme vu avant de fermer.
    func markPlayedAndClose() {
        if let client, let id = context?.item.id {
            pendingWork.append(Task { try? await client.markPlayed(itemId: id) })
        }
        finishAndClose()
    }

    /// Attend que le serveur ait pris acte de la fin de lecture.
    ///
    /// L'écran qui reprend la main recharge ses rangées dans la foulée : sans ce
    /// point de rendez-vous, il interrogerait le serveur avant que la position ne
    /// soit enregistrée et réafficherait l'ancienne.
    func finish() async {
        stop()
        let work = pendingWork
        pendingWork = []
        for task in work { await task.value }
    }

    // MARK: Chargement

    private func load(_ requested: MediaItem, startTime: Double?, previousDidFinish: Bool) async {
        guard let client else { return }

        if context != nil {
            detachObservers()
            reportStop(position: previousDidFinish ? (context?.item.runtime ?? currentPosition) : currentPosition)
        }

        phase = .loading
        offeredSegmentId = nil
        controller?.contextualActions = []

        // Les listes ne portent ni pistes ni chapitres : il faut la fiche complète
        // pour que le serveur raisonne sur la bonne source et que la timeline
        // puisse être marquée.
        let full = (try? await client.item(id: requested.id)) ?? requested
        let resume = startTime ?? full.resumePosition ?? 0

        // Les quatre appels sont indépendants ; les enchaîner ajouterait leurs
        // latences au temps de démarrage.
        async let segmentsTask = client.mediaSegments(itemId: full.id)
        async let nextTask = client.nextEpisode(after: full)
        async let siblingsTask = Self.siblings(of: full, using: client)
        async let planTask = client.playbackPlan(for: full, startTime: resume)

        let segments = await segmentsTask
        let next = await nextTask
        let siblings = await siblingsTask

        let plan: PlaybackPlan
        do {
            plan = try await planTask
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        logPlaybackStart(
            plan,
            resume: resume,
            segments: segments.count,
            chapters: full.chapters?.count ?? 0,
            next: next?.displayTitle
        )

        let newContext = PlaybackContext(plan: plan, segments: segments, nextEpisode: next, siblings: siblings)
        context = newContext
        hasStopped = false

        let playerItem = AVPlayerItem(asset: AVURLAsset(url: plan.url))
        playerItem.externalMetadata = Self.metadata(for: full)
        // Pas de `navigationMarkerGroups` : voir `PlaybackEngine+Decorations`.

        player.replaceCurrentItem(with: playerItem)
        player.appliesMediaSelectionCriteriaAutomatically = true

        seek(playerItem, to: plan.startTime)
        attachObservers(to: playerItem)
        attachDiagnostics(to: playerItem)
        player.play()
        phase = .playing
        // Un démarrage qui n'arrive jamais est le cas le plus déroutant : aucune
        // erreur n'est signalée, l'écran tourne indéfiniment.
        watchForStalledStart()

        applyDecorations()
        reportStart(plan)

        // Ce que le système montre de la lecture hors de l'application. Posé après
        // `player.play()` : la vitesse annoncée au panneau doit être la vraie.
        publishNowPlaying(for: newContext)
        registerRemoteCommands()

        // La vignette de l'épisode suivant se télécharge : poser la proposition
        // après coup évite de retarder le démarrage de l'image.
        if let next {
            Task { [weak self] in
                let image = await Self.previewImage(for: next, using: client)
                self?.attachProposal(for: next, image: image, to: playerItem, context: newContext)
            }
        }
    }

    /// Épisodes de la même saison — le panneau « Épisodes » n'a de sens que pour
    /// une série.
    private static func siblings(of item: MediaItem, using client: JellyfinClient) async -> [MediaItem] {
        guard item.type == .episode, let seriesId = item.seriesId else { return [] }
        return (try? await client.episodes(seriesId: seriesId, seasonId: item.seasonId)) ?? []
    }

    // MARK: Positionnement

    /// En HLS, Jellyfin publie une playlist couvrant tout le média : le lecteur se
    /// déplace donc librement dedans, et la reprise se fait côté client. Jamais
    /// avant `readyToPlay` cependant — la durée est alors inconnue et le `seek`
    /// est ignoré sans erreur.
    private func seek(_ playerItem: AVPlayerItem, to position: Double) {
        guard position > 1 else { return }
        let target = CMTime(seconds: position, preferredTimescale: 600)

        if playerItem.status == .readyToPlay {
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            // `Task { @MainActor }` et non `assumeIsolated` : KVO délivre sur la
            // file qui a modifié la propriété, et AVFoundation ne promet pas que
            // ce soit la principale. L'affirmer y ferait tomber le processus sans
            // exception ni trace — le même piège qui a coûté le panneau système.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                // Une seule fois : les repositionnements suivants viennent de l'utilisateur.
                self.statusObserver = nil
            }
        }
    }

    /// La timeline couvre le média entier dans tous les modes : le temps écoulé
    /// est directement la position dans le film.
    private var currentPosition: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : lastPosition
    }

    // MARK: Observation

    private func attachObservers(to playerItem: AVPlayerItem) {
        // Un demi-seconde : c'est le pas qui rend l'apparition du bouton
        // « Passer l'intro » imperceptiblement tardive. Les rapports au serveur,
        // eux, restent espacés de dix secondes.
        ticker = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.seconds.isFinite else { return }
                // Un écart supérieur au pas du battement trahit un déplacement
                // dans la timeline : l'extrapolation du panneau système est alors
                // fausse, et lui seul peut nous le dire — AVKit ne notifie pas les
                // repositionnements venus de ses propres contrôles.
                if abs(time.seconds - self.lastPosition) > 1.5 {
                    self.refreshNowPlayingPosition()
                }
                self.lastPosition = time.seconds
                self.refreshSkipAction(at: time.seconds)

                // Pause et reprise sont relevées ici plutôt que par une
                // observation de `timeControlStatus` : KVO délivre ses
                // notifications sur la file qui a modifié la propriété — une file
                // interne d'AVFoundation — où `MainActor.assumeIsolated` piège
                // fatalement. Ce battement-ci est explicitement sur `.main`.
                if self.lastTimeControlStatus != self.player.timeControlStatus {
                    self.lastTimeControlStatus = self.player.timeControlStatus
                    self.refreshNowPlayingPosition()
                    // La première image est arrivée : plus rien à surveiller.
                    if self.player.timeControlStatus == .playing { self.cancelStartWatchdog() }
                }

                self.tickCount += 1
                if self.tickCount % 20 == 0 { self.reportProgress(position: time.seconds) }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePlaybackEnd()
            }
        }
    }

    private func detachObservers() {
        if let ticker { player.removeTimeObserver(ticker) }
        ticker = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObserver = nil
        lastTimeControlStatus = .paused
        tickCount = 0
        detachDiagnostics()
        cancelStartWatchdog()
    }

    /// Fin du média. Quand une proposition d'épisode suivant est en place, AVKit
    /// prend la main : il affiche son compte à rebours puis accepte tout seul.
    /// Fermer ici couperait cette séquence.
    private func handlePlaybackEnd() {
        guard context?.nextEpisode == nil else { return }
        finishAndClose()
    }

    // MARK: Rapports au serveur

    /// Une bande-annonce ne se reprend pas et ne se marque pas comme vue : la
    /// rapporter la ferait remonter dans « Reprendre la lecture » au milieu des
    /// films, et compterait comme un visionnage.
    private var reportsToServer: Bool { context?.item.type != .trailer }

    private func reportStart(_ plan: PlaybackPlan) {
        guard let client, plan.item.type != .trailer else { return }
        Task { await client.reportPlaybackStart(plan) }
    }

    private func reportProgress(position: Double) {
        guard let client, let plan = context?.plan, reportsToServer else { return }
        let isPaused = player.timeControlStatus != .playing
        Task { await client.reportPlaybackProgress(plan, position: position, isPaused: isPaused) }
    }

    private func reportStop(position: Double) {
        guard let client, let plan = context?.plan, reportsToServer else { return }
        pendingWork.append(Task { await client.reportPlaybackStopped(plan, position: position) })
    }
}
