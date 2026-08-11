import JellyfinKit
import SwiftUI

/// Fiche d'un film ou d'une série : le contenu se lit par-dessus son propre
/// visuel, avec les actions immédiatement accessibles.
struct DetailView: View {
    @Environment(AppSession.self) private var session
    let item: MediaItem

    @State private var detail: MediaItem?
    @State private var seasons: [MediaItem] = []
    @State private var episodes: [MediaItem] = []
    @State private var collectionItems: [MediaItem] = []
    @State private var trailer: MediaItem?
    @State private var similar: [MediaItem] = []
    @State private var selectedSeason: MediaItem?
    @State private var playback: PlaybackRequest?
    @State private var resumeCandidate: MediaItem?
    @State private var pushedItem: MediaItem?
    @State private var pushedPerson: Person?
    @State private var isFavorite = false
    @State private var isPlayed = false
    /// Portée de focus de la fiche : elle désigne le bouton de lecture comme cible
    /// à l'ouverture. Sans elle, le moteur choisit seul et tombe régulièrement sur
    /// une vignette de la distribution, en bas de l'écran.
    @Namespace private var headerFocus

    /// Sujet réellement affiché. Un épisode n'a pas de fiche à lui : on présente
    /// sa série, saison ouverte sur la sienne, pour que l'utilisateur ait sous les
    /// yeux la suite et les autres saisons plutôt qu'un cul-de-sac.
    private var current: MediaItem { detail ?? item }

    /// L'épisode d'origine, quand on est arrivé ici depuis une rangée d'épisodes.
    private var originEpisode: MediaItem? { item.type == .episode ? item : nil }

    private var subjectId: String {
        item.type == .episode ? (item.seriesId ?? item.id) : item.id
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Palette.background.ignoresSafeArea()
            backdrop

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 46) {
                    // Section de focus sur tout l'en-tête, et non sur les seuls
                    // boutons : le moteur cherche une cible dans la bande située
                    // au-dessus de la vignette quittée. Une section étroite et
                    // calée à gauche ne couvre pas les vignettes de droite, et le
                    // focus reste coincé passé la troisième.
                    header
                        .padding(.horizontal, Theme.Metrics.screenPadding)
                        .padding(.top, 300)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusSection()

                    if current.type == .series {
                        seasonPicker
                        episodeList
                    }

                    if current.type == .boxSet {
                        collectionRow
                    }

                    castRow
                    similarRow
                }
                .padding(.bottom, 90)
            }
            .scrollClipDisabled()
            .focusScope(headerFocus)
        }
        .ignoresSafeArea()
        .navigationDestination(item: $pushedItem) { next in
            DetailView(item: next)
        }
        .navigationDestination(item: $pushedPerson) { person in
            PersonView(person: person)
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(item: request.item, startTime: request.startTime)
        }
        .resumeChoice(for: $resumeCandidate) { playback = $0 }
        .task { await load() }
        // Marquer un épisode comme vu depuis le menu d'une vignette change l'état
        // côté serveur, mais la fiche était le seul écran à ne pas s'y abonner :
        // son coin « non vu » restait donc affiché jusqu'à ce qu'on la rouvre.
        .task(id: session.libraryRevision) { await refreshUserState() }
    }

    // MARK: Visuel

    private var backdrop: some View {
        RemoteImage(url: session.api.backdropURL(for: current))
            .frame(height: 820)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(LinearGradient.heroSideScrim)
            .overlay(LinearGradient.heroScrim)
            .ignoresSafeArea()
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(current.displayTitle)
                .font(Theme.Font.heroTitle)
                .foregroundStyle(Theme.Palette.primaryText)
                .shadow(color: .black.opacity(0.6), radius: 16, y: 6)
                .lineLimit(2)

            if let tagline = current.taglines?.first, !tagline.isEmpty {
                Text(tagline)
                    .font(Theme.Font.body)
                    .italic()
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            MetadataLine(item: current)

            if let genres = current.genres, !genres.isEmpty {
                Text(genres.prefix(4).joined(separator: " · "))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }

            if let overview = current.overview, !overview.isEmpty {
                // Borné à cinq lignes : un synopsis de quinze lignes repousse les
                // saisons, les épisodes et la distribution hors de l'écran, et la
                // télévision n'est pas un support de lecture longue.
                Text(overview)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(5)
                    .frame(maxWidth: 1000, alignment: .leading)
            }

            actions
        }
    }

    private var actions: some View {
        HStack(spacing: 20) {
            // Rien à lire — collection vide ou entièrement vue — et le bouton
            // disparaît plutôt que de promettre une lecture impossible.
            if let entryPoint = playbackEntryPoint {
                Button {
                    startPlayback(entryPoint)
                } label: {
                    Label(playLabel(for: entryPoint), systemImage: "play.fill")
                        .font(Theme.Font.button)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                // Cible de focus à l'ouverture de la fiche : c'est le geste
                // attendu neuf fois sur dix, et le laisser au moteur ferait
                // atterrir le focus sur la première vignette de la distribution.
                .prefersDefaultFocus(true, in: headerFocus)
                .accessibilityHint(playbackHint(for: entryPoint))
            }

            // Une bande-annonce se regarde d'un bout à l'autre : on la lance
            // toujours depuis le début, et sans proposer de reprise.
            if let trailer {
                Button {
                    playback = PlaybackRequest(trailer, startTime: 0)
                } label: {
                    Label("Bande-annonce", systemImage: "film")
                        .font(Theme.Font.button)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }

            // Ces deux boutons n'ont que leur glyphe : sans libellé explicite,
            // VoiceOver n'annonce rien d'autre que « bouton ». Le libellé dit
            // l'action, la valeur dit l'état courant.
            Button {
                Task { await toggleFavorite() }
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(Theme.Font.button)
                    .padding(.vertical, 6)
                    .frame(width: 70)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(isFavorite ? L("Retirer des favoris") : L("Ajouter aux favoris"))
            .accessibilityValue(isFavorite ? L("Favori") : L("Pas en favori"))

            Button {
                Task { await togglePlayed() }
            } label: {
                Image(systemName: isPlayed ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(Theme.Font.button)
                    .padding(.vertical, 6)
                    .frame(width: 70)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(isPlayed ? L("Marquer comme non vu") : L("Marquer comme vu"))
            .accessibilityValue(isPlayed ? L("Vu") : L("Non vu"))
        }
        .padding(.top, 12)
    }

    /// Ce que lance réellement le bouton — jamais évident sur une série, où il
    /// reprend un épisode précis que rien à l'écran ne nomme.
    private func playbackHint(for entryPoint: MediaItem) -> String {
        guard current.type != .movie else { return "" }
        if let code = entryPoint.episodeCode, let name = entryPoint.name {
            return L("Lance \(code), \(name)")
        }
        return L("Lance \(entryPoint.displayTitle)")
    }

    private func playLabel(for entryPoint: MediaItem) -> String {
        if current.type == .series {
            return episodes.contains(where: { $0.resumePosition != nil }) ? L("Reprendre") : L("Lecture")
        }
        return entryPoint.resumePosition != nil ? L("Reprendre") : L("Lecture")
    }

    /// Ce que lance le bouton de lecture — jamais le sujet de la fiche quand celui-ci
    /// n'est qu'un contenant, et `nil` quand il n'a plus rien à proposer.
    private var playbackEntryPoint: MediaItem? {
        switch current.type {
        case .series:
            // L'épisode par lequel on est arrivé prime sur toute heuristique.
            if let originEpisode { return originEpisode }
            if let inProgress = episodes.first(where: { $0.resumePosition != nil }) { return inProgress }
            if let firstUnwatched = episodes.first(where: { !$0.isPlayed }) { return firstUnwatched }
            return episodes.first ?? current
        case .boxSet:
            // On reprend le film entamé, sinon on attaque le premier qui reste à
            // voir. Les séries d'une collection sont écartées : elles ne se lisent
            // pas davantage qu'elle, il faut d'abord passer par leur fiche.
            let films = collectionItems.filter { $0.type == .movie }
            return films.first { $0.resumePosition != nil } ?? films.first { !$0.isPlayed }
        default:
            return current
        }
    }

    // MARK: Saisons et épisodes

    private var seasonPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(seasons) { season in
                    SelectableChip(
                        title: season.displayTitle,
                        isSelected: selectedSeason?.id == season.id
                    ) {
                        selectedSeason = season
                        Task { await loadEpisodes(for: season) }
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private var episodeList: some View {
        MediaRow(
            title: selectedSeason?.displayTitle ?? L("Épisodes"),
            items: episodes,
            layout: .landscape,
            scrollTo: originEpisode?.id ?? firstUnwatchedEpisodeId,
            onSelect: { startPlayback($0) }
        )
    }

    /// Épisode sur lequel ouvrir la rangée : celui d'où l'on vient, sinon le premier
    /// qui reste à voir — plutôt que de laisser l'utilisateur faire défiler une
    /// saison entière pour retrouver où il en était.
    private var firstUnwatchedEpisodeId: String? {
        episodes.first { $0.resumePosition != nil }?.id
            ?? episodes.first { !$0.isPlayed }?.id
    }

    /// Propose de reprendre quand le titre est entamé, sinon lance directement.
    private func startPlayback(_ item: MediaItem) {
        if item.resumePosition != nil {
            resumeCandidate = item
        } else {
            playback = PlaybackRequest(item)
        }
    }

    // MARK: Collection

    /// Les films d'une saga, dans l'ordre de sortie. Les ouvrir plutôt que les lancer :
    /// on parcourt une collection pour choisir, pas pour reprendre où l'on en était.
    private var collectionRow: some View {
        MediaRow(
            title: L("Films"),
            items: collectionItems,
            layout: .poster,
            onOpenDetails: { pushedItem = $0 },
            onSelect: { pushedItem = $0 }
        )
    }

    // MARK: Distribution

    @ViewBuilder
    private var castRow: some View {
        let cast = (current.people ?? []).filter { $0.type == "Actor" }.prefix(12)
        if !cast.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text("Distribution")
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .padding(.horizontal, Theme.Metrics.screenPadding)

                ScrollView(.horizontal) {
                    HStack(spacing: 28) {
                        ForEach(Array(cast), id: \.id) { person in
                            Button {
                                pushedPerson = person
                            } label: {
                                VStack(spacing: 12) {
                                    RemoteImage(url: session.api.personImageURL(for: person))
                                        .frame(width: 160, height: 160)
                                        .clipShape(Circle())
                                    Text(person.name ?? "")
                                        .font(Theme.Font.badge)
                                        .foregroundStyle(Theme.Palette.primaryText)
                                        .lineLimit(1)
                                    if let role = person.role, !role.isEmpty {
                                        Text(role)
                                            .font(Theme.Font.badge)
                                            .foregroundStyle(Theme.Palette.tertiaryText)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 180)
                            }
                            .buttonStyle(MediaCardButtonStyle())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                [person.name, person.role]
                                    .compactMap(\.self)
                                    .filter { !$0.isEmpty }
                                    .joined(separator: L(", rôle : "))
                            )
                            .accessibilityHint("Affiche les titres avec cette personne")
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.screenPadding)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
                .focusSection()
            }
        }
    }

    @ViewBuilder
    private var similarRow: some View {
        MediaRow(
            title: L("Dans le même esprit"),
            items: similar,
            layout: .poster,
            onOpenDetails: { pushedItem = $0 },
            onSelect: { pushedItem = $0 }
        )
    }

    // MARK: Chargement

    private func load() async {
        let subject = subjectId
        let full = try? await session.api.item(id: subject)
        detail = full
        isFavorite = (full ?? item).isFavorite
        isPlayed = (full ?? item).isPlayed

        similar = (try? await session.api.similar(to: subject, limit: 12)) ?? []

        switch (full ?? item).type {
        case .series:
            await loadSeasons(of: subject)
        case .boxSet:
            collectionItems = (try? await session.api.collectionItems(collectionId: subject)) ?? []
        default:
            break
        }

        // Une collection n'a pas de bande-annonce à elle : c'est un contenant.
        if (full ?? item).type != .boxSet {
            trailer = await session.api.localTrailers(itemId: subject).first
        }
    }

    /// Recharge ce qui porte un état modifiable — vu, favori, progression — et
    /// **rien d'autre**.
    ///
    /// Volontairement plus étroit que `load()` : rejouer celui-ci relancerait
    /// `loadSeasons`, qui choisit la saison à ouvrir et ramènerait l'utilisateur
    /// sur celle de départ alors qu'il en parcourait une autre. Les saisons, les
    /// titres similaires et la bande-annonce ne bougent jamais du fait d'un
    /// « marquer comme vu » : les recharger ne ferait que faire clignoter l'écran.
    private func refreshUserState() async {
        // Au premier montage, `load()` s'en charge déjà : ce point d'entrée ne sert
        // qu'aux révisions suivantes.
        guard detail != nil else { return }

        if let full = try? await session.api.item(id: subjectId) {
            detail = full
            isFavorite = full.isFavorite
            isPlayed = full.isPlayed
        }

        switch current.type {
        case .series:
            // La saison affichée, pas celle d'origine.
            if let season = selectedSeason { await loadEpisodes(for: season) }
        case .boxSet:
            collectionItems = (try? await session.api.collectionItems(collectionId: subjectId)) ?? []
        default:
            break
        }
    }

    private func loadSeasons(of seriesId: String) async {
        seasons = (try? await session.api.seasons(seriesId: seriesId)) ?? []

        // On ouvre la saison de l'épisode d'où l'on vient, sinon la première.
        let target = originEpisode.flatMap { episode in
            seasons.first { $0.id == episode.seasonId }
        } ?? seasons.first

        if let target {
            selectedSeason = target
            await loadEpisodes(for: target)
        }
    }

    private func loadEpisodes(for season: MediaItem) async {
        episodes = (try? await session.api.episodes(seriesId: subjectId, seasonId: season.id)) ?? []
    }

    private func toggleFavorite() async {
        isFavorite.toggle()
        try? await session.api.setFavorite(isFavorite, itemId: current.id)
        session.libraryDidChange()
    }

    private func togglePlayed() async {
        isPlayed.toggle()
        if isPlayed {
            try? await session.api.markPlayed(itemId: current.id)
        } else {
            try? await session.api.markUnplayed(itemId: current.id)
        }
        session.libraryDidChange()
    }
}
