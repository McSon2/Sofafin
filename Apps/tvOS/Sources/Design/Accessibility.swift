import JellyfinKit
import SwiftUI

/// Ce que VoiceOver annonce d'un titre de la médiathèque.
///
/// Une vignette est faite d'une affiche, d'un titre tronqué à une ligne, d'une
/// barre de progression et parfois d'un coin de couleur : autant d'informations
/// que l'œil saisit d'un coup et que la voix doit énoncer dans l'ordre où elles
/// comptent. Sans cela le lecteur d'écran annonce « bouton », et rien d'autre.
extension MediaItem {

    /// Phrase lue à l'arrivée du focus.
    var accessibilityDescription: String {
        var parts: [String] = []

        switch type {
        case .episode:
            // « Série, S02E05, Le Titre » : on n'annonce pas « S02E05 » brut, que
            // la synthèse vocale épellerait lettre à lettre.
            parts.append(seriesName ?? displayTitle)
            if let season = parentIndexNumber, let episode = indexNumber {
                parts.append("saison \(season), épisode \(episode)")
            }
            if let name { parts.append(name) }
        case .boxSet:
            parts.append(displayTitle)
            parts.append("collection")
            if let count = childCount, count > 0 {
                parts.append(count == 1 ? "1 titre" : "\(count) titres")
            }
        default:
            parts.append(displayTitle)
            if let productionYear { parts.append(String(productionYear)) }
        }

        if let runtimeLabel { parts.append(runtimeLabel) }
        if let rating = communityRating {
            parts.append("noté \(String(format: "%.1f", rating)) sur 10")
        }

        // L'état de lecture ferme la phrase : c'est l'information qu'on cherche en
        // parcourant une rangée, et le coin coloré la donne aux voyants.
        if let fraction = progressFraction {
            parts.append("commencé, \(Int(fraction * 100)) pour cent vus")
        } else if isPlayed {
            parts.append("vu")
        } else if let remaining = userData?.unplayedItemCount, remaining > 0 {
            parts.append(remaining == 1 ? "1 épisode non vu" : "\(remaining) épisodes non vus")
        }

        if isFavorite { parts.append("favori") }

        return parts.joined(separator: ", ")
    }

    /// Ce que déclenche un clic — jamais évident ici, puisque le geste ne fait pas
    /// la même chose selon le titre : un épisode se lance, un film entamé demande
    /// où reprendre, une collection s'ouvre.
    var accessibilityActionHint: String {
        if type == .boxSet { return "Ouvre la collection" }
        if resumePosition != nil { return "Propose de reprendre ou de recommencer" }
        if type == .episode { return "Lance la lecture" }
        return "Ouvre la fiche"
    }
}

// MARK: - Animations facultatives

extension View {
    /// Animation qui s'efface sous « Réduire les animations ».
    ///
    /// À réserver au décoratif — fondus d'illustration, dérives de fond, comptes à
    /// rebours. Ce qui *informe*, comme la réaction au focus, se calme mais ne
    /// disparaît jamais : voir `FocusLift`.
    func decorativeAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(DecorativeAnimation(animation: animation, value: value))
    }
}

private struct DecorativeAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
