import SwiftUI

/// Profondeur et reflet sur une vignette au focus.
///
/// Les directives Apple TV réclament un effet de parallaxe sur les cartes : la
/// couche d'image doit se détacher de son cadre et capter la lumière, pour dire
/// « c'est ici » par autre chose que la taille.
///
/// La version système — celle des images LSR de l'écran d'accueil — suit le doigt
/// sur la surface tactile, et n'est pilotable que depuis le moteur de focus
/// d'UIKit (`didUpdateFocus(in:with:)`). SwiftUI n'y donne aucun accès : une carte
/// est ici un `Button`, et le focus qu'on observe est celui de SwiftUI. On
/// reconstruit donc les deux composantes qui restent atteignables :
///
/// - **la profondeur**, en agrandissant l'image *à l'intérieur* de son cadre fixe :
///   la couche image s'avance sous la découpe, exactement ce que produit la
///   séparation avant-plan / arrière-plan d'une pile de calques ;
/// - **le reflet spéculaire**, une bande claire en diagonale qui balaie la carte
///   à l'arrivée du focus.
///
/// Reste hors de portée : le suivi du doigt, qui demanderait de réécrire les
/// vignettes en UIKit — au prix de deux systèmes de focus concurrents dans la
/// même hiérarchie.
///
/// « Réduire les animations » désarme l'ensemble : les directives citent la
/// parallaxe comme le premier effet à couper.
struct FocusParallax: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isFocused: Bool
    /// Rayon du cadre, pour que le reflet épouse la découpe de la carte.
    var cornerRadius: CGFloat = Theme.Metrics.cornerRadius

    /// Assez pour que l'image s'avance visiblement, assez peu pour qu'aucun visage
    /// ne sorte du cadre : au-delà, une affiche se retrouve décapitée au focus.
    private var depthScale: CGFloat { isActive ? 1.06 : 1.0 }
    private var isActive: Bool { isFocused && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .scaleEffect(depthScale)
            // Le rognage vient après l'agrandissement : le cadre ne bouge pas,
            // c'est l'image qui avance derrière lui.
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if isActive { specularSheen }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: isFocused)
    }

    /// Bande lumineuse en diagonale, dans le sens où tvOS éclaire ses surfaces :
    /// lumière en haut à gauche, extinction en bas à droite.
    private var specularSheen: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.0), location: 0.0),
                        .init(color: .white.opacity(0.22), location: 0.42),
                        .init(color: .white.opacity(0.0), location: 0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

extension View {
    /// À poser sur **l'image** d'une vignette, jamais sur la carte entière : c'est
    /// la couche qui doit s'avancer, pas le titre ni la ligne de métadonnées.
    func focusParallax(
        _ isFocused: Bool,
        cornerRadius: CGFloat = Theme.Metrics.cornerRadius
    ) -> some View {
        modifier(FocusParallax(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}
