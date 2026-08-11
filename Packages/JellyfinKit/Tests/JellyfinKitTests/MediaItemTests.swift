import Foundation
import Testing
@testable import JellyfinKit

/// Ce que le modèle déduit pour l'affichage.
///
/// Ces propriétés paraissent anodines, mais elles décident de ce qui apparaît
/// dans « Reprendre la lecture », du coin « non vu » d'une vignette et du titre
/// sous une affiche. Une erreur ici est invisible en compilation et très visible
/// à l'écran.
@Suite("Propriétés d'affichage d'un élément")
struct MediaItemTests {

    /// Un élément décodé depuis du JSON, comme le ferait le client : c'est la
    /// seule façon de construire un `MediaItem`, dont les champs sont constants.
    private func item(_ json: String) throws -> MediaItem {
        try JSONDecoder().decode(MediaItem.self, from: Data(json.utf8))
    }

    private static let hour = 36_000_000_000     // 1 h en unités de 100 ns
    private static let minute = 600_000_000

    // MARK: Reprise

    @Test("Une progression sur un titre non terminé est une reprise")
    func resumeOnStartedItem() throws {
        let media = try item("""
        {"Id":"1","Name":"Film","Type":"Movie",
         "UserData":{"PlaybackPositionTicks":\(Self.hour),"Played":false}}
        """)
        #expect(media.resumePosition == 3600)
    }

    @Test("Un titre déjà vu n'est pas une reprise, même s'il garde une position")
    func playedItemIsNotResumable() throws {
        // Jellyfin conserve une position résiduelle sur les titres terminés :
        // sans ce filtre, un film vu réapparaîtrait indéfiniment dans la rangée.
        let media = try item("""
        {"Id":"1","Name":"Film","Type":"Movie",
         "UserData":{"PlaybackPositionTicks":\(Self.hour),"Played":true}}
        """)
        #expect(media.resumePosition == nil)
    }

    @Test("Une position nulle n'est pas une reprise")
    func zeroPositionIsNotResumable() throws {
        let media = try item("""
        {"Id":"1","Name":"Film","Type":"Movie",
         "UserData":{"PlaybackPositionTicks":0,"Played":false}}
        """)
        #expect(media.resumePosition == nil)
    }

    @Test("La fraction de progression reste dans [0, 1]")
    func progressStaysWithinBounds() throws {
        let media = try item("""
        {"Id":"1","Name":"Film","Type":"Movie","RunTimeTicks":\(Self.hour * 2),
         "UserData":{"PlaybackPositionTicks":\(Self.hour),"Played":false}}
        """)
        #expect(media.progressFraction == 0.5)

        // Une position au-delà de la durée — l'arrondi d'un rapport de fin de
        // lecture y suffit — ne doit pas produire une barre qui déborde.
        let overrun = try item("""
        {"Id":"1","Name":"Film","Type":"Movie","RunTimeTicks":\(Self.hour),
         "UserData":{"PlaybackPositionTicks":\(Self.hour * 3),"Played":false}}
        """)
        #expect(overrun.progressFraction == 1.0)
    }

    @Test("Sans durée connue, pas de barre de progression")
    func noProgressWithoutRuntime() throws {
        let media = try item("""
        {"Id":"1","Name":"Film","Type":"Movie",
         "UserData":{"PlaybackPositionTicks":\(Self.hour),"Played":false}}
        """)
        #expect(media.progressFraction == nil)
    }

    // MARK: Titres

    @Test("Un épisode s'annonce sous le nom de sa série")
    func episodeShowsSeriesName() throws {
        let media = try item("""
        {"Id":"1","Name":"Le Titre","Type":"Episode","SeriesName":"La Série",
         "IndexNumber":5,"ParentIndexNumber":2}
        """)
        #expect(media.rowTitle == "La Série")
        #expect(media.episodeCode == "S02E05")
        #expect(media.rowSubtitle == "S02E05 · Le Titre")
    }

    @Test("Un code d'épisode incomplet n'est pas fabriqué")
    func episodeCodeNeedsBothNumbers() throws {
        let media = try item("""
        {"Id":"1","Name":"Le Titre","Type":"Episode","SeriesName":"La Série","IndexNumber":5}
        """)
        #expect(media.episodeCode == nil)
    }

    @Test("Un film s'annonce par son année")
    func movieSubtitleIsTheYear() throws {
        let media = try item("""
        {"Id":"1","Name":"Film","Type":"Movie","ProductionYear":1999}
        """)
        #expect(media.rowTitle == "Film")
        #expect(media.rowSubtitle == "1999")
    }

    @Test("Un titre absent ne laisse jamais l'écran vide")
    func missingNameFallsBack() throws {
        let media = try item(#"{"Id":"1","Type":"Movie","OriginalTitle":"Original"}"#)
        #expect(media.displayTitle == "Original")
    }

    // MARK: Durée

    @Test("La durée passe aux heures au-delà de soixante minutes")
    func runtimeLabelFormat() throws {
        let long = try item("""
        {"Id":"1","Name":"F","Type":"Movie","RunTimeTicks":\(Self.hour + Self.minute * 52)}
        """)
        #expect(long.runtimeLabel == "1 h 52")

        let short = try item("""
        {"Id":"1","Name":"F","Type":"Movie","RunTimeTicks":\(Self.minute * 45)}
        """)
        #expect(short.runtimeLabel == "45 min")
    }

    @Test("Une durée nulle ou absente ne s'affiche pas")
    func noRuntimeLabelWithoutRuntime() throws {
        #expect(try item(#"{"Id":"1","Name":"F","Type":"Movie"}"#).runtimeLabel == nil)
        #expect(try item(#"{"Id":"1","Name":"F","Type":"Movie","RunTimeTicks":0}"#).runtimeLabel == nil)
    }
}
