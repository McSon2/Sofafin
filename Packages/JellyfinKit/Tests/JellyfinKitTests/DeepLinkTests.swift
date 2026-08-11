import Foundation
import Testing
@testable import JellyfinKit

/// Les liens de l'étagère du haut.
///
/// C'est le seul canal par lequel l'extension peut demander quelque chose à
/// l'application, et elles vivent dans deux processus distincts : une erreur ici
/// ne se voit qu'en pressant un élément de l'étagère.
@Suite("Liens internes")
struct DeepLinkTests {

    @Test("Un lien de lecture fait l'aller-retour intact")
    func playRoundTrip() {
        let url = DeepLink.play("abc123")
        #expect(DeepLink.destination(from: url) == .play(itemId: "abc123"))
    }

    @Test("Un lien de fiche fait l'aller-retour intact")
    func detailsRoundTrip() {
        let url = DeepLink.details("abc123")
        #expect(DeepLink.destination(from: url) == .details(itemId: "abc123"))
    }

    @Test("Les identifiants de Jellyfin sont des UUID sans tirets")
    func realWorldIdentifier() {
        let id = "67ea87503c00d21a2228bc3e7e603332"
        #expect(DeepLink.destination(from: DeepLink.play(id)) == .play(itemId: id))
    }

    @Test("Ce qui ne vient pas de nous est ignoré", arguments: [
        "https://exemple.fr/play/abc",   // un autre schéma
        "sofafin://",                    // ni verbe ni identifiant
        "sofafin://play",                // verbe sans identifiant
        "sofafin://play/",               // identifiant vide
        "sofafin://autre/abc",           // verbe inconnu
    ])
    func rejectsForeignOrIncomplete(_ raw: String) {
        let url = URL(string: raw)
        #expect(url.flatMap(DeepLink.destination(from:)) == nil)
    }
}
