import AVFoundation
import AVKit
import JellyfinKit
import SwiftUI
import UIKit

/// Tout ce que le moteur pose *sur* le contrôleur d'AVKit : bouton flottant de
/// saut, marqueurs de chapitres, proposition d'épisode suivant, panneaux
/// d'information et items de la barre de transport.
///
/// Ces affordances sont les points d'extension officiels de tvOS. Elles donnent
/// le vocabulaire d'un lecteur de service de streaming sans rien réécrire des
/// contrôles système — qu'aucune implémentation maison n'égalerait.
extension PlaybackEngine {

    // MARK: - Bouton flottant « Passer… »

    /// Met à jour l'action contextuelle selon la position dans le média.
    ///
    /// Appelée deux fois par seconde, elle ne reconstruit le bouton que sur un
    /// changement réel de segment : le recréer à chaque battement le ferait
    /// clignoter et lui reprendrait le focus au moment même où l'utilisateur
    /// tente de le presser.
    func refreshSkipAction(at position: Double) {
        guard let context else { return }
        let active = context.segments.active(at: position)

        // Le générique de fin appartient à la proposition d'épisode suivant :
        // deux affordances au même instant se disputeraient le même geste.
        let candidate = active.flatMap { segment -> MediaSegment? in
            segment.kind.endsContent && context.nextEpisode != nil ? nil : segment
        }

        guard candidate?.id != offeredSegmentId else { return }
        offeredSegmentId = candidate?.id

        guard let candidate else {
            controller?.contextualActions = []
            return
        }
        controller?.contextualActions = [
            UIAction(
                title: candidate.kind.skipLabel,
                image: UIImage(systemName: "forward.end.alt.fill")
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.skip(past: candidate) }
            }
        ]
    }

    private func skip(past segment: MediaSegment) {
        controller?.contextualActions = []
        offeredSegmentId = nil

        // Sauter le générique d'un titre sans suite, c'est en avoir fini avec lui.
        if segment.kind.endsContent {
            finishAndClose()
            return
        }
        player.seek(
            to: CMTime(seconds: segment.end, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    // MARK: - Marqueurs de la timeline
    //
    // **`navigationMarkerGroups` est volontairement absent.** Il paraissait être le
    // moyen officiel de poser les chapitres sur la timeline, mais AVKit en tire un
    // second bouton dans la barre de transport, à l'icône de liste — la même que
    // celle du menu « Chapitres » ci-dessous. Ce bouton ouvre un panneau de
    // vignettes qu'AVKit fabrique en allant échantillonner le média : sur un flux
    // HLS transcodé à la demande, sans piste de défilement rapide, il n'y parvient
    // pas et affiche **une carte grise vide**. Deux icônes identiques, dont une
    // inerte.
    //
    // Les chapitres restent atteignables par le menu textuel, qui n'a besoin de
    // rien échantillonner, et les segments par le bouton « Passer l'intro »
    // (`contextualActions`) — lequel ne dépend pas de ces marqueurs.

    /// Alimente le panneau d'information de la télécommande Siri.
    static func metadata(for item: MediaItem) -> [AVMetadataItem] {
        var items = [titleMetadata(item.displayTitle)]

        if let overview = item.overview, !overview.isEmpty {
            items.append(metadataItem(.commonIdentifierDescription, value: overview))
        }
        if item.type == .episode {
            let context = [item.seriesName, item.episodeCode].compactMap(\.self).joined(separator: " · ")
            if !context.isEmpty {
                items.append(metadataItem(.iTunesMetadataTrackSubTitle, value: context))
            }
        }
        return items
    }

    private static func titleMetadata(_ value: String) -> AVMetadataItem {
        metadataItem(.commonIdentifierTitle, value: value)
    }

    private static func metadataItem(_ identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }

    // MARK: - Proposition d'épisode suivant

    /// Vignette de l'épisode proposé. Une image de scène, pas une affiche :
    /// c'est ce que la proposition affiche en grand.
    static func previewImage(for item: MediaItem, using client: JellyfinClient) async -> UIImage? {
        guard let url = client.thumbURL(for: item, maxWidth: 1280),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        return UIImage(data: data)
    }

    /// Attache la proposition à l'élément en cours.
    ///
    /// `contentTimeForTransition` la fait apparaître au début du générique quand
    /// le serveur l'a repéré ; à défaut, `indefinite` la reporte à la toute fin du
    /// média.
    ///
    /// `automaticAcceptanceInterval` ne se décompte qu'**à partir de la fin du
    /// média** : sur un générique long, il s'ajoute à la durée de celui-ci au lieu
    /// de la borner. Le délai réellement appliqué est celui que la carte pose
    /// elle-même à son apparition — voir `NextEpisodeProposalViewController` — et
    /// la valeur ci-dessous s'y aligne pour que les deux mécanismes ne puissent
    /// pas se contredire.
    func attachProposal(
        for next: MediaItem,
        image: UIImage?,
        to playerItem: AVPlayerItem,
        context: PlaybackContext
    ) {
        // L'élément a pu être remplacé pendant le téléchargement de la vignette.
        guard player.currentItem === playerItem else { return }

        let transition = context.segments.outroStart.map {
            CMTime(seconds: $0, preferredTimescale: 600)
        } ?? .indefinite

        let proposal = AVContentProposal(
            contentTimeForTransition: transition,
            title: next.displayTitle,
            previewImage: image
        )
        proposal.automaticAcceptanceInterval = NextEpisodeProposalViewController.acceptanceDelay
        proposal.metadata = Self.metadata(for: next)
        playerItem.nextContentProposal = proposal
    }

    // MARK: - Barre de transport

    /// Pose sur le contrôleur tout ce qui dépend du titre en cours.
    func applyDecorations() {
        guard let controller, let context else { return }

        controller.transportBarIncludesTitleView = true
        controller.transportBarCustomMenuItems = menuItems(for: context)
        controller.customInfoViewControllers = infoPanels(for: context)
        controller.customOverlayViewController = overlayController(for: context)
        controller.contentProposalViewController = NextEpisodeProposalViewController()
    }

    private func menuItems(for context: PlaybackContext) -> [UIMenuElement] {
        var items: [UIMenuElement] = []

        let chapters = context.chapters
        if chapters.count > 1 {
            let actions = chapters.enumerated().map { index, chapter in
                UIAction(title: chapter.name ?? "Chapitre \(index + 1)",
                         subtitle: chapter.start.timecode) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.player.seek(
                            to: CMTime(seconds: chapter.start, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                    }
                }
            }
            items.append(UIMenu(title: "Chapitres",
                                image: UIImage(systemName: "list.bullet"),
                                children: actions))
        }

        if let next = context.nextEpisode {
            items.append(
                UIAction(title: "Épisode suivant",
                         subtitle: next.rowSubtitle,
                         image: UIImage(systemName: "forward.end.fill")) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.play(next, startTime: 0, previousDidFinish: true)
                    }
                }
            )
        }

        items.append(
            UIAction(title: "Marquer comme vu",
                     image: UIImage(systemName: "checkmark.circle.fill")) { [weak self] _ in
                MainActor.assumeIsolated { self?.markPlayedAndClose() }
            }
        )
        return items
    }

    // MARK: - Panneaux d'information

    /// Les onglets qui apparaissent au swipe vers le bas. Leur `title` nomme
    /// l'onglet ; un fond transparent laisse voir la vidéo derrière, comme dans
    /// les panneaux natifs.
    private func infoPanels(for context: PlaybackContext) -> [UIViewController] {
        guard let client else { return [] }
        var panels: [UIViewController] = []

        if context.siblings.count > 1 {
            panels.append(panel(
                titled: context.item.seasonName ?? "Épisodes",
                height: 360,
                content: EpisodesPanel(
                    episodes: context.siblings,
                    currentId: context.item.id,
                    client: client,
                    onSelect: { [weak self] episode in
                        self?.play(episode, startTime: episode.resumePosition)
                    }
                )
            ))
        }

        let cast = (context.item.people ?? []).filter { $0.type == "Actor" }
        if !cast.isEmpty {
            panels.append(panel(
                titled: "Distribution",
                height: 300,
                content: CastPanel(cast: cast, client: client)
            ))
        }

        // Pas de panneau « À propos » : AVKit ouvre déjà le sien en premier onglet,
        // bâti sur `externalMetadata` — titre et synopsis, exactement ce qu'il
        // contenait. Deux onglets pour la même chose n'apprenaient rien et
        // allongeaient la rangée à parcourir.
        return panels
    }

    private func panel(titled title: String, height: CGFloat, content: some View) -> UIViewController {
        let controller = UIHostingController(rootView: content)
        controller.title = title
        controller.view.backgroundColor = .clear
        // AVKit dimensionne ces contrôleurs par leur `preferredContentSize`. Sans
        // elle, le panneau s'ouvre sur une bande vide : les onglets sont bien là,
        // mais le contenu est écrasé à une hauteur nulle. La largeur est imposée
        // par le système, seule la hauteur compte.
        controller.preferredContentSize = CGSize(width: 0, height: height)
        return controller
    }

    // MARK: - Bandeau superposé

    /// Rappel discret de ce qui est en train d'être lu et de la façon dont le
    /// serveur le délivre. Il s'efface seul et **ne prend jamais le focus** :
    /// une vue interactive posée là intercepterait la télécommande.
    private func overlayController(for context: PlaybackContext) -> UIViewController {
        let controller = UIHostingController(
            rootView: PlaybackBadge(
                title: context.item.rowTitle,
                subtitle: context.item.rowSubtitle,
                method: context.plan.method.label
            )
        )
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    // MARK: - Délégué d'AVKit

    func playerViewController(_ controller: AVPlayerViewController, didAccept proposal: AVContentProposal) {
        guard let next = context?.nextEpisode else { return }
        play(next, startTime: 0, previousDidFinish: true)
    }

    /// Refuser la suite, c'est arrêter de regarder.
    func playerViewController(_ controller: AVPlayerViewController, didReject proposal: AVContentProposal) {
        finishAndClose()
    }
}
