import SwiftUI

/// Surface en verre.
///
/// tvOS 26 expose Liquid Glass sur les boutons (`.buttonStyle(.glass)`) mais pas,
/// contrairement à iOS et macOS, le modificateur `glassEffect` applicable à n'importe
/// quelle vue. On reconstruit donc l'effet à partir de ses trois composantes visibles :
/// une matière qui laisse transparaître le fond, une arête spéculaire qui capte la
/// lumière, et une ombre portée qui décolle la surface du contenu.
struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.Metrics.cornerRadius
    var material: Material = .ultraThinMaterial
    var tint: Color = .white
    var tintOpacity: Double = 0.06
    var isHighlighted: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(material)
                    .overlay(shape.fill(tint.opacity(tintOpacity)))
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient.glassEdge,
                        lineWidth: isHighlighted ? 2.5 : 1.2
                    )
                    .opacity(isHighlighted ? 1.0 : 0.7)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.45), radius: isHighlighted ? 26 : 14, y: isHighlighted ? 14 : 8)
    }
}

extension View {
    func liquidGlass(
        cornerRadius: CGFloat = Theme.Metrics.cornerRadius,
        material: Material = .ultraThinMaterial,
        tint: Color = .white,
        tintOpacity: Double = 0.06,
        isHighlighted: Bool = false
    ) -> some View {
        modifier(LiquidGlassBackground(
            cornerRadius: cornerRadius,
            material: material,
            tint: tint,
            tintOpacity: tintOpacity,
            isHighlighted: isHighlighted
        ))
    }
}

// MARK: - Réaction au focus

/// Le vocabulaire de focus d'une interface de télévision : l'élément visé grandit,
/// s'éclaire et se détache par son ombre. Volontairement **sans contour** — une
/// bordure tracée autour d'une carte suit mal ses coins, déborde sur le titre et
/// alourdit l'écran ; ni tvOS ni les services de streaming n'en utilisent.
struct FocusLift: ViewModifier {
    let isFocused: Bool
    var scale: CGFloat = Theme.Metrics.focusScale

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? scale : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.65 : 0.3),
                    radius: isFocused ? 34 : 12,
                    y: isFocused ? 20 : 6)
            .animation(.spring(response: 0.34, dampingFraction: 0.74), value: isFocused)
    }
}

extension View {
    func focusLift(_ isFocused: Bool, scale: CGFloat = Theme.Metrics.focusScale) -> some View {
        modifier(FocusLift(isFocused: isFocused, scale: scale))
    }
}
