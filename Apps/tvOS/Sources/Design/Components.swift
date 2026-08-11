import JellyfinKit
import SwiftUI

// MARK: - Image distante

/// Image de la médiathèque, avec un fond de remplacement qui garde la mise en page
/// stable pendant le chargement — indispensable dans une rangée qui défile.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    /// L'initialiseur n'est pas décoratif : c'est le seul point du cycle de vie
    /// d'une vue qu'une pile paresseuse exécute **pendant son préchargement**,
    /// avant que la vignette n'entre à l'écran. Y lancer la requête réseau, plutôt
    /// que d'attendre l'apparition, est ce qui donne son avance au défilement.
    /// Voir `ImagePrefetcher`.
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
        ImagePrefetcher.shared.prefetch(url)
    }

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure, .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Theme.Palette.surface, Theme.Palette.surface.opacity(0.45)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            // `medium` et non `light` : un glyphe maigre s'efface sur un
            // téléviseur, où le flou de mouvement et la compression mangent les
            // traits fins.
            Image(systemName: "film")
                .font(Theme.Font.placeholderGlyph)
                .foregroundStyle(Theme.Palette.tertiaryText)
        }
    }
}

// MARK: - Style de carte

/// Style de bouton des vignettes. tvOS fournit `.card`, mais son relief fixe ne
/// s'accorde pas avec les surfaces de verre : on refait le lift avec nos jetons.
struct MediaCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MediaCardBody(configuration: configuration)
    }

    /// Vue intermédiaire : c'est le seul moyen de lire `isFocused` depuis
    /// l'environnement, un `ButtonStyle` n'y ayant pas accès directement.
    struct MediaCardBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .brightness(isFocused ? 0.06 : 0)
                .focusLift(isFocused)
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == MediaCardButtonStyle {
    static var mediaCard: MediaCardButtonStyle { MediaCardButtonStyle() }
}

// MARK: - Menu contextuel des vignettes

/// Options d'une vignette, ouvertes par un appui long sur la télécommande —
/// la convention tvOS pour tout ce qui ne tient pas dans l'action principale.
struct MediaCardMenu: View {
    @Environment(AppSession.self) private var session
    let item: MediaItem
    let onPlay: () -> Void
    let onOpenDetails: (() -> Void)?

    @State private var isPlayed: Bool
    @State private var isFavorite: Bool

    init(item: MediaItem, onPlay: @escaping () -> Void, onOpenDetails: (() -> Void)?) {
        self.item = item
        self.onPlay = onPlay
        self.onOpenDetails = onOpenDetails
        _isPlayed = State(initialValue: item.isPlayed)
        _isFavorite = State(initialValue: item.isFavorite)
    }

    var body: some View {
        // Une collection ne se lit pas : proposer « Lecture » ouvrirait sa fiche,
        // ce que fait déjà l'entrée suivante.
        if item.type != .boxSet {
            Button(action: onPlay) {
                Label(item.resumePosition != nil ? "Reprendre" : "Lecture", systemImage: "play.fill")
            }
        }

        if let onOpenDetails {
            Button(action: onOpenDetails) {
                Label(detailsLabel, systemImage: "info.circle")
            }
        }

        Button {
            isPlayed.toggle()
            let played = isPlayed
            Task {
                if played {
                    try? await session.api.markPlayed(itemId: item.id)
                } else {
                    try? await session.api.markUnplayed(itemId: item.id)
                }
                session.libraryDidChange()
            }
        } label: {
            Label(
                isPlayed ? "Marquer comme non vu" : "Marquer comme vu",
                systemImage: isPlayed ? "eye.slash" : "checkmark.circle"
            )
        }

        Button {
            isFavorite.toggle()
            let favorite = isFavorite
            Task {
                try? await session.api.setFavorite(favorite, itemId: item.id)
                session.libraryDidChange()
            }
        } label: {
            Label(
                isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                systemImage: isFavorite ? "heart.slash" : "heart"
            )
        }
    }

    private var detailsLabel: String {
        switch item.type {
        case .episode: return L("Voir la série")
        case .boxSet: return L("Voir la collection")
        default: return L("Voir la fiche")
        }
    }
}

// MARK: - Pastille sélectionnable

/// Bouton de filtre ou d'onglet secondaire.
///
/// Les deux styles de verre de tvOS sont des `PrimitiveButtonStyle`, qu'on ne peut
/// pas stocker derrière un type effacé : on choisit donc la branche à la construction.
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    /// Symbole affiché à droite du libellé quand la pastille est active — sert au
    /// sens de tri, qu'un simple état sélectionné ne suffirait pas à exprimer.
    var activeSymbol: String?
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) { label }.buttonStyle(.glassProminent)
        } else {
            Button(action: action) { label }.buttonStyle(.glass)
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if isSelected, let activeSymbol {
                Image(systemName: activeSymbol)
                    .font(Theme.Font.badge)
            }
        }
        .font(Theme.Font.badge)
    }
}

/// Menu déroulant en verre, dont le libellé porte la valeur retenue.
///
/// tvOS n'expose pas `controlSize` : un bouton système garde sa taille quoi qu'on
/// fasse. Aligner huit pastilles sur une ligne était donc perdu d'avance — un menu
/// unique tient la même information dans un seul bouton, et affiche l'état
/// sélectionné plutôt que de le faire deviner.
struct GlassMenu<Content: View>: View {
    let title: String
    let value: String
    var symbol: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 10) {
                // Opacité et non couleur fixe : sous le focus, le bouton devient
                // blanc et le texte passe au noir. Un gris figé y resterait
                // illisible.
                Text(title)
                    .opacity(0.55)
                Text(value)
                if let symbol {
                    Image(systemName: symbol)
                        .font(Theme.Font.badge)
                }
            }
            .font(Theme.Font.badge)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.glass)
        // Sans cela VoiceOver annonce « Trier par, Année, flèche vers le bas » en
        // trois fragments, sans dire que le second est la valeur retenue.
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint("Ouvre la liste des options")
    }
}

/// Entrée de menu avec coche : sur un téléviseur, l'état courant doit rester
/// lisible sans avoir à mémoriser ce qu'on a choisi.
struct MenuCheckItem: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

// MARK: - Barre de progression de reprise

struct ResumeProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.28))
                Capsule()
                    .fill(Theme.Palette.accentBright)
                    .frame(width: max(6, geometry.size.width * fraction))
            }
        }
        .frame(height: 6)
        // La progression est énoncée par la description de la vignette.
        .accessibilityHidden(true)
    }
}

// MARK: - Vignettes

/// Vignette portrait 2:3, la maille de base d'une grille de films.
struct PosterCard: View {
    @Environment(AppSession.self) private var session
    let item: MediaItem
    var onFocus: ((MediaItem) -> Void)?
    var onOpenDetails: (() -> Void)?
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                RemoteImage(url: session.api.posterURL(for: item))
                    .frame(width: Theme.Metrics.posterWidth, height: Theme.Metrics.posterHeight)
                    // Remplace le simple `clipShape` : la découpe est désormais
                    // appliquée après l'agrandissement de profondeur.
                    .focusParallax(isFocused)
                    .overlay(alignment: .bottom) {
                        if let fraction = item.progressFraction {
                            ResumeProgressBar(fraction: fraction)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 10)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        // Un titre entamé n'est pas « à voir » : sa barre de
                        // progression l'annonce déjà, le coin ferait doublon.
                        if !item.isPlayed, item.resumePosition == nil {
                            UnwatchedBadge(count: item.userData?.unplayedItemCount)
                        }
                    }

                // `reservesSpace` et non un simple `lineLimit` : une pile
                // horizontale paresseuse donne à toute la rangée la hauteur de sa
                // **première** sous-vue. Une carte dont le titre manquerait, ou
                // qu'on passerait un jour à deux lignes, imposerait donc sa
                // hauteur aux autres — qui se retrouveraient rognées. Réserver la
                // place rend la hauteur identique quel que soit le contenu, tout
                // en suivant la taille de texte choisie par l'utilisateur.
                Text(item.rowTitle)
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1, reservesSpace: true)
                CardFooter(item: item)
            }
            .frame(width: Theme.Metrics.posterWidth, alignment: .leading)
        }
        .buttonStyle(.mediaCard)
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused { onFocus?(item) }
        }
        .contextMenu {
            MediaCardMenu(item: item, onPlay: action, onOpenDetails: onOpenDetails)
        }
        // La carte parle d'une seule voix : le titre tronqué, la barre de
        // progression et le coin de couleur sont des fragments visuels dont
        // l'énumération n'apprendrait rien. `accessibilityDescription` les dit en
        // une phrase, dans l'ordre où ils comptent.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityDescription)
        .accessibilityHint(item.accessibilityActionHint)
    }
}

/// Vignette paysage 16:9 — épisodes et reprises de lecture, où l'image de scène
/// informe mieux que l'affiche.
struct LandscapeCard: View {
    @Environment(AppSession.self) private var session
    let item: MediaItem
    var onFocus: ((MediaItem) -> Void)?
    var onOpenDetails: (() -> Void)?
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                RemoteImage(url: session.api.thumbURL(for: item))
                    .frame(width: Theme.Metrics.landscapeWidth, height: Theme.Metrics.landscapeHeight)
                    .focusParallax(isFocused)
                    .overlay(alignment: .bottom) {
                        if let fraction = item.progressFraction {
                            ResumeProgressBar(fraction: fraction)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        // Un titre entamé n'est pas « à voir » : sa barre de
                        // progression l'annonce déjà, le coin ferait doublon.
                        if !item.isPlayed, item.resumePosition == nil {
                            UnwatchedBadge(count: item.userData?.unplayedItemCount)
                        }
                    }

                // Voir `PosterCard` : la hauteur de la rangée entière est celle de
                // sa première carte.
                Text(item.rowTitle)
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1, reservesSpace: true)
                CardFooter(item: item)
            }
            .frame(width: Theme.Metrics.landscapeWidth, alignment: .leading)
        }
        .buttonStyle(.mediaCard)
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused { onFocus?(item) }
        }
        .contextMenu {
            MediaCardMenu(item: item, onPlay: action, onOpenDetails: onOpenDetails)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityDescription)
        .accessibilityHint(item.accessibilityActionHint)
    }
}

/// Ligne sous une vignette : le repère de gauche (année, ou série et numéro
/// d'épisode) et la note poussée à l'opposé, pour que l'œil trouve toujours
/// chaque information au même endroit d'une carte à l'autre.
struct CardFooter: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 8) {
            // L'espace insécable tenait lieu de réservation de place quand le
            // sous-titre manque ; `reservesSpace` le dit au moteur de mise en page
            // plutôt qu'au moteur de rendu.
            Text(item.rowSubtitle ?? "")
                .lineLimit(1, reservesSpace: true)

            Spacer(minLength: 8)

            if let rating = item.communityRating {
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .font(Theme.Font.badge)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                }
                .layoutPriority(1)
            }
        }
        .font(Theme.Font.badge)
        .foregroundStyle(Theme.Palette.tertiaryText)
    }
}

/// Coin replié dans l'angle supérieur droit d'une vignette, qui signale un titre
/// **pas encore vu**.
///
/// C'est le marquage utile : dans une médiathèque, le regard cherche ce qui reste à
/// voir. Signaler l'inverse constellerait l'écran de coches sur tout le déjà-vu.
struct UnwatchedBadge: View {
    /// Nombre d'épisodes restants, pour une série.
    var count: Int?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Triangle()
                .fill(Theme.Palette.accent)
                .frame(width: 60, height: 60)

            if let count, count > 0 {
                Text("\(count)")
                    .font(Theme.Font.badge)
                    .foregroundStyle(.white)
                    .padding(.top, 6)
                    .padding(.trailing, 8)
            }
        }
        // Le compte est déjà énoncé par la description de la vignette, dont ce coin
        // est la traduction visuelle : le relire en ferait un doublon.
        .accessibilityHidden(true)
    }
}

/// Triangle rectangle appuyé dans l'angle supérieur droit.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Rangée

enum RowLayout {
    case poster
    case landscape
}

/// Rangée horizontale titrée, telle qu'on la connaît sur les services de streaming.
struct MediaRow: View {
    let title: String
    let items: [MediaItem]
    var layout: RowLayout = .poster
    var onFocus: ((MediaItem) -> Void)?
    var onOpenDetails: ((MediaItem) -> Void)?
    /// Identifiant sur lequel positionner la rangée à l'ouverture — l'épisode en
    /// cours, plutôt que d'imposer de faire défiler une saison entière.
    var scrollTo: String?
    let onSelect: (MediaItem) -> Void

    /// Position de la rangée. Remplace `ScrollViewReader` : celui-ci ne sait
    /// désigner une cible qu'en résolvant les vues de la pile, ce qui suppose
    /// qu'elles existent déjà. `ScrollPosition` s'exprime en identifiants, que le
    /// conteneur sait rejoindre même quand la vignette visée n'a pas encore été
    /// construite — le cas normal dans une pile paresseuse.
    @State private var position = ScrollPosition()

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .padding(.horizontal, Theme.Metrics.screenPadding)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Metrics.cardSpacing) {
                        ForEach(items) { item in
                            switch layout {
                            case .poster:
                                PosterCard(
                                    item: item,
                                    onFocus: onFocus,
                                    onOpenDetails: onOpenDetails.map { open in { open(item) } }
                                ) { onSelect(item) }
                            case .landscape:
                                LandscapeCard(
                                    item: item,
                                    onFocus: onFocus,
                                    onOpenDetails: onOpenDetails.map { open in { open(item) } }
                                ) { onSelect(item) }
                            }
                        }
                    }
                    // Désigne la pile comme la couche dont les enfants sont des
                    // cibles de défilement — sans quoi `scrollTo(id:)` n'a rien à
                    // viser. À poser avant les marges : appliqué après, il ne
                    // verrait plus qu'une vue unique au lieu de la rangée.
                    .scrollTargetLayout()
                    .padding(.horizontal, Theme.Metrics.screenPadding)
                    // Sans cette marge, l'agrandissement au focus est rogné par le ScrollView.
                    .padding(.vertical, 40)
                }
                .scrollPosition($position)
                .onChange(of: scrollTo, initial: true) { _, target in
                    guard let target else { return }
                    position.scrollTo(id: target, anchor: .leading)
                }
                .scrollClipDisabled()
                // Sans section de focus, quitter la rangée vers le haut ne trouve
                // aucune cible dès que la vignette visée n'a rien juste au-dessus
                // d'elle : le focus reste bloqué. Déclarer la section donne au
                // moteur un repli vers la rangée voisine, quelle que soit la
                // position horizontale.
                .focusSection()
            }
        }
    }
}

// MARK: - Métadonnées

/// Ligne « 2024 · 1 h 52 · 12 · 7,8 ★ » sous un titre.
struct MetadataLine: View {
    let item: MediaItem
    var showRating: Bool = true

    var body: some View {
        HStack(spacing: 16) {
            if let year = item.productionYear {
                Text(String(year))
            }
            if let runtime = item.runtimeLabel {
                Text(runtime)
            }
            if let rating = item.officialRating {
                Text(rating)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.Palette.secondaryText,
                                          lineWidth: Theme.Metrics.hairline)
                    )
                    .accessibilityLabel("Classification \(rating)")
            }
            if showRating, let community = item.communityRating {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", community))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Noté \(String(format: "%.1f", community)) sur 10")
            }
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Palette.secondaryText)
    }
}

// MARK: - États

struct LoadingView: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(.white)
            .scaleEffect(1.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Chargement en cours")
    }
}

/// Écran de repli : rien à montrer, ou rien reçu.
///
/// Quand la cause est une panne et non un vide réel, l'écran porte le moyen d'en
/// sortir. La télécommande Siri n'a pas de geste de rafraîchissement — pas de
/// tirer-pour-recharger sur un téléviseur — donc l'action doit être un bouton
/// visible, sans quoi l'utilisateur n'a d'autre recours que de quitter l'app.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?
    var retryTitle: String = "Réessayer"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            // `medium` au lieu de `thin` : les directives proscrivent le trait fin,
            // qui ne survit pas à la distance de salon.
            Image(systemName: icon)
                .font(Theme.Font.emptyStateGlyph)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.Palette.primaryText)
            if let message {
                Text(message)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
            }
            if let onRetry {
                Button(action: onRetry) {
                    Label(retryTitle, systemImage: "arrow.clockwise")
                        .font(Theme.Font.button)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
