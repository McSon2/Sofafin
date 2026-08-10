import JellyfinKit
import SwiftUI

/// Demande de lecture : quoi, et à partir d'où.
///
/// La position doit voyager avec le titre — sans elle, « Reprendre depuis le début »
/// ne pourrait pas se distinguer d'une reprise, le lecteur retombant toujours sur la
/// position enregistrée côté serveur.
struct PlaybackRequest: Identifiable, Equatable {
    let item: MediaItem
    /// `nil` laisse le lecteur décider, `0` force le début.
    let startTime: Double?

    var id: String { item.id }

    init(_ item: MediaItem, startTime: Double? = nil) {
        self.item = item
        self.startTime = startTime
    }
}

extension Double {
    /// « 1:23:45 » ou « 23:45 » — la durée telle qu'on l'annonce à l'écran.
    var timecode: String {
        let total = Int(rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// Propose de reprendre ou de recommencer avant de lancer un titre entamé.
///
/// Sur un téléviseur, relancer par erreur un film au début est coûteux à rattraper :
/// mieux vaut une question de trop qu'une reprise perdue.
struct ResumeChoiceModifier: ViewModifier {
    @Binding var candidate: MediaItem?
    let onPlay: (PlaybackRequest) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            candidate?.displayTitle ?? "",
            isPresented: Binding(
                get: { candidate != nil },
                set: { if !$0 { candidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = candidate, let position = item.resumePosition {
                Button("Reprendre à \(position.timecode)") {
                    onPlay(PlaybackRequest(item, startTime: position))
                    candidate = nil
                }
                Button("Reprendre depuis le début") {
                    onPlay(PlaybackRequest(item, startTime: 0))
                    candidate = nil
                }
                Button("Annuler", role: .cancel) { candidate = nil }
            }
        }
    }
}

extension View {
    func resumeChoice(
        for candidate: Binding<MediaItem?>,
        onPlay: @escaping (PlaybackRequest) -> Void
    ) -> some View {
        modifier(ResumeChoiceModifier(candidate: candidate, onPlay: onPlay))
    }
}
