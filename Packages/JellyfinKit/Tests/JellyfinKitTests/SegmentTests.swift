import Foundation
import Testing
@testable import JellyfinKit

/// Les repères qui pilotent « Passer l'intro » et la proposition de fin.
///
/// Ces bornes viennent d'un détecteur côté serveur, pas d'une source sûre : elles
/// arrivent parfois dégénérées, dans le désordre, ou se chevauchent. Le bouton
/// flottant se construit dessus, et un mauvais choix le fait apparaître au mauvais
/// moment — ou lui fait reprendre le focus pendant que l'utilisateur le presse.
@Suite("Segments d'un média")
struct SegmentTests {

    private static let second: Int64 = 10_000_000

    private func segment(_ kind: String, from start: Int64, to end: Int64) throws -> MediaSegment {
        try JSONDecoder().decode(MediaSegment.self, from: Data("""
        {"Id":"\(kind)-\(start)","ItemId":"x","Type":"\(kind)",
         "StartTicks":\(start * Self.second),"EndTicks":\(end * Self.second)}
        """.utf8))
    }

    @Test("La borne de fin est exclue : à la seconde de sortie, on n'est plus dedans")
    func endBoundaryIsExclusive() throws {
        let intro = try segment("Intro", from: 30, to: 90)
        #expect(intro.contains(30))
        #expect(intro.contains(89.9))
        #expect(!intro.contains(90))
        #expect(!intro.contains(29.9))
    }

    @Test("Le segment actif est celui qui couvre la position")
    func activeSegmentAtPosition() throws {
        let segments = [
            try segment("Intro", from: 30, to: 90),
            try segment("Outro", from: 3000, to: 3120),
        ]
        #expect(segments.active(at: 60)?.kind == .intro)
        #expect(segments.active(at: 3050)?.kind == .outro)
        // Entre les deux, aucun bouton ne doit s'afficher.
        #expect(segments.active(at: 500) == nil)
    }

    @Test("Le générique de fin donne le repère de la proposition d'épisode suivant")
    func outroStartDrivesTheProposal() throws {
        let segments = [
            try segment("Intro", from: 30, to: 90),
            try segment("Outro", from: 3000, to: 3120),
        ]
        #expect(segments.outroStart == 3000)
    }

    @Test("Sans générique repéré, il n'y a pas de repère : la fin du média fera foi")
    func noOutroMeansNoAnchor() throws {
        #expect([try segment("Intro", from: 30, to: 90)].outroStart == nil)
        #expect([MediaSegment]().outroStart == nil)
    }

    @Test("Un segment trop court pour qu'un saut ait du sens est écarté")
    func degenerateSegmentsAreRejected() throws {
        #expect(try segment("Intro", from: 30, to: 31).isUsable == false)
        #expect(try segment("Intro", from: 30, to: 30).isUsable == false)
        #expect(try segment("Intro", from: 30, to: 32).isUsable == true)
    }

    @Test("Seul le générique de fin termine le contenu")
    func onlyOutroEndsContent() {
        #expect(MediaSegmentKind.outro.endsContent)
        for kind in [MediaSegmentKind.intro, .recap, .preview, .commercial, .unknown] {
            #expect(!kind.endsContent)
        }
    }

    @Test("Un type inconnu du serveur ne fait pas échouer le décodage")
    func unknownKindDecodes() throws {
        // Jellyfin peut introduire de nouveaux types de segments : une médiathèque
        // ne doit pas devenir illisible parce qu'un greffon a été mis à jour.
        let segment = try JSONDecoder().decode(MediaSegment.self, from: Data("""
        {"Id":"1","ItemId":"x","Type":"QuelqueChoseDeNouveau","StartTicks":0,"EndTicks":10000000}
        """.utf8))
        #expect(segment.kind == .unknown)
    }
}
