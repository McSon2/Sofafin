import SwiftUI

/// Jetons visuels de Jellyflix.
///
/// La grille est celle de Netflix — fond quasi noir, contenu qui flotte au-dessus
/// d'une image plein cadre, accent chaud unique — mais les surfaces empruntent au
/// Liquid Glass : matière translucide, arête spéculaire, ombre portée douce.
enum Theme {

    // MARK: Couleurs

    enum Palette {
        /// Jamais du noir pur : le noir absolu écrase les dégradés sur les dalles OLED.
        static let background = Color(red: 0.043, green: 0.043, blue: 0.051)
        static let surface = Color(red: 0.098, green: 0.098, blue: 0.114)

        static let accent = Color(red: 0.898, green: 0.075, blue: 0.129)      // rouge signal
        static let accentBright = Color(red: 1.0, green: 0.231, blue: 0.267)

        static let primaryText = Color.white
        static let secondaryText = Color.white.opacity(0.72)
        static let tertiaryText = Color.white.opacity(0.45)

        static let focusGlow = Color.white.opacity(0.9)
        static let separator = Color.white.opacity(0.12)
    }

    // MARK: Typographie

    enum Font {
        static let heroTitle = SwiftUI.Font.system(size: 76, weight: .heavy, design: .default)
        static let sectionTitle = SwiftUI.Font.system(size: 30, weight: .semibold)
        static let cardTitle = SwiftUI.Font.system(size: 24, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 26, weight: .regular)
        static let caption = SwiftUI.Font.system(size: 22, weight: .medium)
        static let badge = SwiftUI.Font.system(size: 18, weight: .semibold)
    }

    // MARK: Métriques

    enum Metrics {
        /// Marge latérale : la zone sûre d'un téléviseur mange les bords.
        static let screenPadding: CGFloat = 80
        static let rowSpacing: CGFloat = 52
        static let cardSpacing: CGFloat = 32

        static let posterWidth: CGFloat = 240
        static let posterHeight: CGFloat = 360     // 2:3
        static let landscapeWidth: CGFloat = 440
        static let landscapeHeight: CGFloat = 248  // 16:9

        static let cornerRadius: CGFloat = 14
        static let focusScale: CGFloat = 1.09
    }
}

// MARK: - Dégradés récurrents

extension LinearGradient {
    /// Voile qui rend le texte lisible par-dessus une affiche, sans assombrir l'image entière.
    static let heroScrim = LinearGradient(
        stops: [
            .init(color: Theme.Palette.background.opacity(0.0), location: 0.0),
            .init(color: Theme.Palette.background.opacity(0.55), location: 0.45),
            .init(color: Theme.Palette.background.opacity(0.94), location: 0.78),
            .init(color: Theme.Palette.background, location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Même principe, appliqué horizontalement : le texte vit à gauche, l'image respire à droite.
    static let heroSideScrim = LinearGradient(
        stops: [
            .init(color: Theme.Palette.background.opacity(0.92), location: 0.0),
            .init(color: Theme.Palette.background.opacity(0.55), location: 0.38),
            .init(color: .clear, location: 0.72)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Arête spéculaire d'une surface de verre : lumière en haut, extinction en bas.
    static let glassEdge = LinearGradient(
        colors: [
            Color.white.opacity(0.55),
            Color.white.opacity(0.12),
            Color.white.opacity(0.04)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
