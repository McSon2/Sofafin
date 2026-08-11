import Foundation
import Testing
@testable import JellyfinKit

/// Les dates que sert Jellyfin.
///
/// .NET sérialise ses dates avec **sept** décimales de seconde, quand
/// `ISO8601DateFormatter` n'en accepte que trois et rejette le reste. Sans la
/// troncature, le décodage échoue sur n'importe quel élément daté — c'est-à-dire
/// sur la médiathèque entière.
@Suite("Dates .NET")
struct DateParsingTests {

    @Test("Sept décimales, la forme que sert réellement Jellyfin")
    func sevenDigitFraction() throws {
        let date = try #require(JellyfinClient.parseJellyfinDate("2024-03-15T21:04:11.7830000Z"))
        let parts = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: date)
        #expect(parts.year == 2024)
        #expect(parts.month == 3)
        #expect(parts.day == 15)
        #expect(parts.hour == 21)
        #expect(parts.minute == 4)
        #expect(parts.second == 11)
    }

    @Test("Les longueurs de fraction que la norme accepte déjà")
    func standardFractions() throws {
        #expect(JellyfinClient.parseJellyfinDate("2024-03-15T21:04:11.783Z") != nil)
        #expect(JellyfinClient.parseJellyfinDate("2024-03-15T21:04:11Z") != nil)
    }

    @Test("Une fraction tronquée ne décale pas la seconde")
    func truncationKeepsTheSecond() throws {
        let long = try #require(JellyfinClient.parseJellyfinDate("2024-03-15T21:04:11.9999999Z"))
        let short = try #require(JellyfinClient.parseJellyfinDate("2024-03-15T21:04:11.999Z"))
        // Moins d'un millième d'écart : la troncature ne doit jamais arrondir à
        // la seconde suivante, ce qui décalerait un tri par date d'ajout.
        #expect(abs(long.timeIntervalSince(short)) < 0.001)
    }

    @Test("Fuseau explicite plutôt que Zulu")
    func explicitOffset() {
        #expect(JellyfinClient.parseJellyfinDate("2024-03-15T21:04:11.7830000+02:00") != nil)
    }

    @Test("Ce qui n'est pas une date est refusé, pas deviné", arguments: [
        "", "pas une date", "2024-03-15", "15/03/2024", "2024-13-45T99:99:99Z"
    ])
    func rejectsGarbage(_ raw: String) {
        #expect(JellyfinClient.parseJellyfinDate(raw) == nil)
    }
}
