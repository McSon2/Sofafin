import SwiftUI
import UIKit

/// Jetons visuels de Sofafin.
///
/// La grille est celle de Netflix — fond quasi noir, contenu qui flotte au-dessus
/// d'une image plein cadre, accent chaud unique — mais les surfaces empruntent au
/// Liquid Glass : matière translucide, arête spéculaire, ombre portée douce.
enum Theme {

    // MARK: Couleurs

    /// Chaque teinte a une variante renforcée, servie automatiquement quand
    /// « Augmenter le contraste » est actif : les couleurs sont construites depuis
    /// un `UIColor` dynamique, qui interroge la collection de traits au moment du
    /// rendu. Le faire ici plutôt qu'au point d'usage évite d'avoir à lire
    /// l'environnement dans les soixante vues qui consomment ces jetons.
    enum Palette {
        /// Jamais du noir pur : le noir absolu écrase les dégradés sur les dalles OLED.
        /// En contraste renforcé il le devient, pour gagner sur tous les textes clairs.
        static let background = adaptive(
            normal: UIColor(red: 0.043, green: 0.043, blue: 0.051, alpha: 1),
            highContrast: UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        )
        static let surface = adaptive(
            normal: UIColor(red: 0.098, green: 0.098, blue: 0.114, alpha: 1),
            highContrast: UIColor(red: 0.145, green: 0.145, blue: 0.165, alpha: 1)
        )

        static let accent = adaptive(
            normal: UIColor(red: 0.898, green: 0.075, blue: 0.129, alpha: 1),      // rouge signal
            highContrast: UIColor(red: 1.0, green: 0.169, blue: 0.216, alpha: 1)
        )
        static let accentBright = adaptive(
            normal: UIColor(red: 1.0, green: 0.231, blue: 0.267, alpha: 1),
            highContrast: UIColor(red: 1.0, green: 0.400, blue: 0.420, alpha: 1)
        )

        static let primaryText = Color.white
        /// 0,72 donne 10:1 sur le fond — confortable bien au-delà du seuil AA.
        static let secondaryText = adaptive(
            normal: UIColor(white: 1, alpha: 0.72),
            highContrast: UIColor(white: 1, alpha: 0.92)
        )
        /// Relevé de 0,45 à 0,58 : à 0,45 le rapport tombait à 4,5:1, soit la
        /// limite exacte du seuil AA — intenable à trois mètres sur une dalle qui
        /// compresse. À 0,58 il passe à 7,5:1.
        static let tertiaryText = adaptive(
            normal: UIColor(white: 1, alpha: 0.58),
            highContrast: UIColor(white: 1, alpha: 0.85)
        )

        static let focusGlow = Color.white.opacity(0.9)
        static let separator = adaptive(
            normal: UIColor(white: 1, alpha: 0.18),
            highContrast: UIColor(white: 1, alpha: 0.45)
        )

        private static func adaptive(normal: UIColor, highContrast: UIColor) -> Color {
            Color(uiColor: UIColor { traits in
                traits.accessibilityContrast == .high ? highContrast : normal
            })
        }
    }

    // MARK: Typographie

    /// Les jetons reposent sur les **styles sémantiques** de tvOS, jamais sur une
    /// taille absolue. Trois raisons, toutes imposées par les directives Apple TV :
    ///
    /// - les styles système partent déjà des minima du salon (corps à 29 pt,
    ///   libellé secondaire à 25 pt) — une échelle maison finit toujours en dessous ;
    /// - ils suivent « Texte plus grand » sans une ligne de code ;
    /// - ils suivent « Texte en gras », qu'une police à taille fixe ignore.
    enum Font {
        static let heroTitle = SwiftUI.Font.system(.largeTitle, design: .default, weight: .heavy)
        static let sectionTitle = SwiftUI.Font.system(.headline, design: .default, weight: .semibold)
        /// Libellé de bouton : les directives réclament 29 pt au minimum et en
        /// recommandent 35 à 38 — le style `headline` de tvOS tombe pile dedans.
        static let button = SwiftUI.Font.system(.headline, design: .default, weight: .semibold)
        static let cardTitle = SwiftUI.Font.system(.body, design: .default, weight: .semibold)
        static let body = SwiftUI.Font.system(.body, design: .default, weight: .regular)
        static let caption = SwiftUI.Font.system(.caption, design: .default, weight: .medium)
        static let badge = SwiftUI.Font.system(.caption, design: .default, weight: .semibold)
        /// Glyphes décoratifs des états vides. Jamais plus maigre que `medium` :
        /// un trait fin disparaît sous la compression d'un téléviseur.
        static let emptyStateGlyph = SwiftUI.Font.system(size: 96, weight: .medium)
        static let placeholderGlyph = SwiftUI.Font.system(size: 56, weight: .medium)
    }

    // MARK: Métriques

    enum Metrics {
        /// Marge latérale : la zone sûre d'un téléviseur mange les bords.
        static let screenPadding: CGFloat = 80
        static let rowSpacing: CGFloat = 52
        static let cardSpacing: CGFloat = 32

        /// Élargies pour deux raisons : les directives fixent une cible de focus à
        /// 250 × 150 pt minimum, et les titres composés dans les styles système
        /// (29 pt au lieu de 24) demandent de la place avant de se tronquer.
        static let posterWidth: CGFloat = 280
        static let posterHeight: CGFloat = 420     // 2:3
        static let landscapeWidth: CGFloat = 480
        static let landscapeHeight: CGFloat = 270  // 16:9

        /// Colonnes d'une grille d'affiches. Cinq et non six : les directives
        /// préfèrent une maille large et lisible à une grille dense de vignettes,
        /// et six colonnes de 280 pt ne tiendraient plus dans la zone sûre.
        static let gridColumns = 5

        static let cornerRadius: CGFloat = 14
        static let focusScale: CGFloat = 1.09
        /// Épaisseur plancher d'un trait. En dessous de 2 pt une ligne s'évanouit
        /// sur un téléviseur — flou de mouvement et compression s'en chargent.
        static let hairline: CGFloat = 2
    }
}

// MARK: - Dégradés récurrents

extension LinearGradient {
    /// Voile qui rend le texte lisible par-dessus une affiche, sans assombrir l'image entière.
    ///
    /// Le palier intermédiaire est monté de 0,55 à 0,72 : le synopsis et la ligne
    /// de métadonnées du billboard se posent précisément là, et une image claire
    /// les faisait passer sous le seuil de contraste.
    static let heroScrim = LinearGradient(
        stops: [
            .init(color: Theme.Palette.background.opacity(0.0), location: 0.0),
            .init(color: Theme.Palette.background.opacity(0.72), location: 0.45),
            .init(color: Theme.Palette.background.opacity(0.96), location: 0.78),
            .init(color: Theme.Palette.background, location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Même principe, appliqué horizontalement : le texte vit à gauche, l'image respire à droite.
    static let heroSideScrim = LinearGradient(
        stops: [
            .init(color: Theme.Palette.background.opacity(0.94), location: 0.0),
            .init(color: Theme.Palette.background.opacity(0.62), location: 0.38),
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
