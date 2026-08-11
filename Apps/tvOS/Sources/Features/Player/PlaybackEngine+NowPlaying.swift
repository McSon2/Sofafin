import AVFoundation
import AVKit
import JellyfinKit
import MediaPlayer
import UIKit

/// Ce que le système affiche de la lecture **en dehors** de l'application :
/// panneau Now Playing de la télécommande, Control Center, écran d'accueil de
/// l'Apple TV, appareils AirPlay et widgets du réseau.
///
/// `AVPlayerViewController` sait décorer ses propres contrôles à partir de
/// `externalMetadata`, mais il ne renseigne pas MediaRemote : sans les
/// informations ci-dessous, le système réclame en boucle une file de lecture qui
/// n'existe pas — « Operation requires a client data source to have been
/// registered » — et l'Apple TV reste incapable de dire ce qu'on regarde.
///
/// Trois pièces sont nécessaires, et aucune ne suffit seule : une **session audio
/// active** (sans elle le système ne considère pas l'app comme lecteur courant),
/// les **informations du titre**, et les **commandes distantes** qui rendent le
/// panneau agissant plutôt que décoratif.
extension PlaybackEngine {

    // MARK: Session audio

    /// À appeler une fois avant la première lecture.
    ///
    /// `moviePlayback` demande au système le traitement d'un film — dialogue mis
    /// en avant, dynamique préservée — là où la catégorie seule ne dit rien de
    /// l'usage.
    ///
    /// **Sans `setActive(true)`.** Déclarer l'intention suffit : c'est
    /// `AVPlayerViewController` qui active la session au moment où il démarre le
    /// flux, et lui disputer ce rôle revient à activer une route audio pendant
    /// qu'il négocie la sienne. `MPNowPlayingInfoCenter`, lui, n'en dépend pas.
    static func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    // MARK: Informations du titre

    /// Publie le titre en cours. La vignette arrive après coup : la télécharger
    /// d'abord retarderait l'apparition du panneau pour une image que l'utilisateur
    /// ne regarde peut-être jamais.
    func publishNowPlaying(for context: PlaybackContext) {
        let item = context.item
        var info: [String: Any] = [
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPMediaItemPropertyTitle: item.displayTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime().seconds.isFinite
                ? player.currentTime().seconds : 0,
            MPNowPlayingInfoPropertyPlaybackRate: Double(player.rate)
        ]

        // Un épisode se présente sous le nom de sa série — c'est ce que
        // l'utilisateur cherche dans un panneau système, pas le titre de
        // l'épisode, qui occupe déjà la ligne principale.
        if item.type == .episode {
            if let series = item.seriesName { info[MPMediaItemPropertyArtist] = series }
            if let season = item.seasonName { info[MPMediaItemPropertyAlbumTitle] = season }
        } else if let year = item.productionYear {
            info[MPMediaItemPropertyArtist] = String(year)
        }

        // La durée vient de la fiche Jellyfin plutôt que de l'élément : celle de
        // l'AVPlayerItem est indéfinie tant qu'il n'est pas prêt, et une durée
        // absente fige la barre du panneau système à zéro.
        if let runtime = item.runtime, runtime > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = runtime
        }

        // Pas de `playbackState` : le régler exige l'autorisation privée
        // `com.apple.mediaremote.set-playback-state`, qu'une application tierce
        // n'obtient pas — le système l'ignore en le consignant dans le journal.
        // La vitesse publiée ci-dessus suffit à lui faire déduire l'état.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        Task { [weak self] in await self?.attachArtwork(for: item) }
    }

    private func attachArtwork(for item: MediaItem) async {
        guard let client,
              let url = client.posterURL(for: item, maxWidth: 600)
                ?? client.thumbURL(for: item, maxWidth: 600),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data)
        else { return }

        // Le titre a pu changer pendant le téléchargement — enchaînement d'épisode,
        // ou lecture déjà terminée. Poser l'affiche du précédent serait pire que
        // de n'en poser aucune.
        guard context?.item.id == item.id, var info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        else { return }

        info[MPMediaItemPropertyArtwork] = Self.artwork(from: image)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Emballe l'affiche pour le panneau système.
    ///
    /// `nonisolated`, et la fermeture explicitement `@Sendable` : le système
    /// réclame l'image **depuis sa propre file**, au moment où il en a besoin.
    /// Construite telle quelle dans une méthode isolée à l'acteur principal, la
    /// fermeture en hériterait l'isolation, et cet appel venu d'ailleurs
    /// deviendrait une violation — que l'exécution sanctionne par un arrêt sec
    /// (`EXC_BREAKPOINT` sur un fil de fond), sans exception ni message.
    nonisolated private static func artwork(from image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    /// Réaligne position et vitesse. Le système extrapole entre deux appels à
    /// partir de la vitesse annoncée : il suffit donc de le prévenir quand cette
    /// extrapolation cesse d'être valable — pause, reprise, déplacement dans la
    /// timeline — et non à chaque battement.
    func refreshNowPlayingPosition() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        let position = player.currentTime().seconds
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position.isFinite ? position : 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(player.rate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Commandes distantes

    /// Branche les commandes du panneau système. Seules celles qu'on sait
    /// réellement exécuter sont activées : une commande laissée active mais sans
    /// effet affiche un bouton mort dans le Control Center.
    ///
    /// **Ces gestionnaires ne sont pas appelés sur le fil principal.** MediaRemote
    /// les invoque depuis sa propre file, et `MainActor.assumeIsolated` y provoque
    /// un arrêt immédiat du processus, sans exception ni trace. Chacun se contente
    /// donc d'ordonnancer le travail sur l'acteur principal et de répondre
    /// aussitôt : le système attend un accusé de réception, pas un résultat.
    func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.player.play()
                self?.refreshNowPlayingPosition()
            }
            return .success
        }

        center.pauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.player.pause()
                self?.refreshNowPlayingPosition()
            }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.player.timeControlStatus == .playing {
                    self.player.pause()
                } else {
                    self.player.play()
                }
                self.refreshNowPlayingPosition()
            }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
            // La valeur est extraite ici : l'événement appartient à MediaRemote et
            // n'a pas à traverser la frontière d'acteur.
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            else { return .commandFailed }
            Task { @MainActor in
                guard let self else { return }
                self.player.seek(
                    to: CMTime(seconds: position, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                self.refreshNowPlayingPosition()
            }
            return .success
        }

        center.nextTrackCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self, let next = self.context?.nextEpisode else { return }
                self.play(next, startTime: 0, previousDidFinish: true)
            }
            return .success
        }

        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand] {
            command.isEnabled = true
        }
        center.changePlaybackPositionCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = context?.nextEpisode != nil

        // Sans épisode précédent à proposer, ces deux-là n'auraient rien à faire.
        center.previousTrackCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
    }

    /// Les gestionnaires retiennent le moteur : les laisser en place après la
    /// lecture maintiendrait en vie un lecteur déjà fermé, et la commande suivante
    /// agirait sur lui.
    func unregisterRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
    }
}
