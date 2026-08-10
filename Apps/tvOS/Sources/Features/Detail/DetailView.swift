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
                Text(overview)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
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
                        .font(Theme.Font.cardTitle)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
            }

            // Une bande-annonce se regarde d'un bout à l'autre : on la lance
            // toujours depuis le début, et sans proposer de reprise.
            if let trailer {
                Button {
                    playback = PlaybackRequest(trailer, startTime: 0)
                } label: {
                    Label("Bande-annonce", systemImage: "film")
                        .font(Theme.Font.cardTitle)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }

            Button {
                Task { await toggleFavorite() }
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(Theme.Font.cardTitle)
                    .padding(.vertical, 6)
                    .frame(width: 70)
            }
            .buttonStyle(.glass)

            Button {
                Task { await togglePlayed() }
            } label: {
                Image(systemName: isPlayed ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(Theme.Font.cardTitle)
                    .padding(.vertical, 6)
                    .frame(width: 70)
            }
            .buttonStyle(.glass)
        }
        .padding(.top, 12)
    }

    private func playLabel(for entryPoint: MediaItem) -> String {
        if current.type == .series {
            return episodes.contains(where: { $0.resumePosition != nil }) ? "Reprendre" : "Lecture"
        }
        return entryPoint.resumePosition != nil ? "Reprendre" : "Lecture"
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
            title: selectedSeason?.displayTitle ?? "Épisodes",
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
            title: "Films",
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
            title: "Dans le même esprit",
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
