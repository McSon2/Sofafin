import Foundation
import Testing
@testable import JellyfinKit

/// La réécriture de la playlist maître.
///
/// C'est elle qui décide si le serveur recopie le flux ou réencode un 4K entier :
/// laisser passer une variante de repli suffit à faire choisir la mauvaise au
/// lecteur. Une playlist mal formée, elle, ne produit aucune erreur — juste un
/// écran noir.
@Suite("Playlist maître HLS")
struct HLSManifestTests {

    private let base = URL(string: "http://serveur:8096/videos/abc/master.m3u8")!

    /// Ce que sert Jellyfin pour un film HDR10+ : la bonne variante d'abord, puis
    /// deux replis convertis en SDR.
    private var manifesteHDR: String {
        """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="FR",DEFAULT=YES,URI="abc/Subtitles/3/subtitles.m3u8?x=1",LANGUAGE="fra"
        #EXT-X-STREAM-INF:BANDWIDTH=6684329,VIDEO-RANGE=PQ,CODECS="hvc1.2.4.L153.B0,ac-3",SUPPLEMENTAL-CODECS="hvc1.2.4.L153.B0/cdm4",RESOLUTION=3840x2160
        main.m3u8?VideoCodec=hevc
        #EXT-X-STREAM-INF:BANDWIDTH=6684329,VIDEO-RANGE=SDR,CODECS="hvc1.2.4.L150.B0,ac-3",RESOLUTION=3840x2160
        main.m3u8?VideoCodec=hevc&AllowVideoStreamCopy=false
        #EXT-X-STREAM-INF:BANDWIDTH=6684329,VIDEO-RANGE=SDR,CODECS="avc1.424029,ac-3",RESOLUTION=3840x2160
        main.m3u8?VideoCodec=h264&AllowVideoStreamCopy=false
        """
    }

    private func lines(_ manifest: String) -> [String] {
        HLSManifest.keepingOnlyFirstVariant(of: manifest, relativeTo: base)
            .components(separatedBy: .newlines)
    }

    @Test("L'adresse retenue est celle de la première variante")
    func firstVariantIsResolved() {
        // C'est elle que le serveur recopie ; les suivantes sont des replis qu'il
        // ne peut produire qu'en réencodant l'image.
        let url = HLSManifest.firstVariantURL(in: manifesteHDR, relativeTo: base)
        #expect(url?.absoluteString == "http://serveur:8096/videos/abc/main.m3u8?VideoCodec=hevc")
    }

    @Test("Une adresse de variante déjà absolue est rendue telle quelle")
    func absoluteVariantIsKept() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1
        https://ailleurs.example/main.m3u8
        """
        #expect(HLSManifest.firstVariantURL(in: manifest, relativeTo: base)?.absoluteString
            == "https://ailleurs.example/main.m3u8")
    }

    @Test("Un manifeste sans variante ne donne pas d'adresse")
    func noVariantGivesNoURL() {
        // Le serveur a répondu quelque chose d'inattendu : mieux vaut le dire que
        // rendre une adresse fabriquée, qui échouerait plus loin et plus obscurément.
        #expect(HLSManifest.firstVariantURL(in: "#EXTM3U\n#EXT-X-VERSION:7", relativeTo: base) == nil)
    }

    @Test("Les commentaires entre la déclaration et l'adresse sont ignorés")
    func commentsBetweenDeclarationAndURLAreSkipped() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1
        # une note du serveur
        main.m3u8
        """
        #expect(HLSManifest.firstVariantURL(in: manifest, relativeTo: base)?.lastPathComponent == "main.m3u8")
    }

    @Test("Une seule variante subsiste, et c'est la première")
    func onlyTheFirstVariantSurvives() {
        let result = lines(manifesteHDR)
        let variants = result.filter { $0.hasPrefix("#EXT-X-STREAM-INF") }
        #expect(variants.count == 1)
        #expect(variants[0].contains("VIDEO-RANGE=PQ"))
        // Les replis se reconnaissent à ce paramètre : le serveur y annonce qu'il
        // ne recopiera pas le flux.
        #expect(!result.contains { $0.contains("AllowVideoStreamCopy=false") })
    }

    @Test("L'étiquette que le lecteur ne sait pas lire est retirée")
    func supplementalCodecsAreStripped() {
        let result = lines(manifesteHDR)
        #expect(!result.contains { $0.contains("SUPPLEMENTAL-CODECS") })
        // Le codec principal, lui, doit rester : c'est ce qui décrit le flux.
        #expect(result.contains { $0.contains(#"CODECS="hvc1.2.4.L153.B0,ac-3""#) })
    }

    @Test("Retirer l'étiquette ne laisse pas d'attributs mal formés")
    func strippingLeavesValidAttributes() {
        for line in lines(manifesteHDR) where line.hasPrefix("#EXT-X-STREAM-INF") {
            #expect(!line.contains(",,"))
            #expect(!line.hasSuffix(","))
        }
        // Le cas où l'étiquette termine la liste d'attributs.
        let final = HLSManifest.strippingSupplementalCodecs(
            from: #"#EXT-X-STREAM-INF:BANDWIDTH=1,SUPPLEMENTAL-CODECS="hvc1/cdm4""#
        )
        #expect(final == "#EXT-X-STREAM-INF:BANDWIDTH=1")
    }

    @Test("Toutes les adresses deviennent absolues")
    func addressesBecomeAbsolute() {
        // La playlist réécrite n'est plus servie par le serveur : une adresse
        // relative s'y résoudrait contre un schéma d'emprunt injoignable.
        for line in lines(manifesteHDR) where !line.hasPrefix("#") && !line.isEmpty {
            #expect(line.hasPrefix("http://serveur:8096/"))
        }
        // L'adresse des sous-titres est relative au dossier de la playlist, et
        // Jellyfin la préfixe de l'identifiant de source : le segment répété est
        // attendu, pas un doublon à corriger.
        let media = lines(manifesteHDR).first { $0.hasPrefix("#EXT-X-MEDIA") }
        #expect(media?.contains(#"URI="http://serveur:8096/videos/abc/abc/Subtitles/3/subtitles.m3u8?x=1""#) == true)
    }

    @Test("Les pistes de sous-titres sont conservées")
    func subtitleRenditionsSurvive() {
        #expect(lines(manifesteHDR).filter { $0.hasPrefix("#EXT-X-MEDIA") }.count == 1)
    }

    @Test("Une playlist à variante unique traverse sans dommage")
    func singleVariantIsUntouched() {
        // C'est le cas d'un film SDR : rien à retirer, et rien ne doit disparaître.
        let sdr = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=4000000,VIDEO-RANGE=SDR,CODECS="avc1.640028,mp4a.40.2"
        main.m3u8?VideoCodec=h264
        """
        let result = lines(sdr)
        #expect(result.filter { $0.hasPrefix("#EXT-X-STREAM-INF") }.count == 1)
        #expect(result.contains("http://serveur:8096/videos/abc/main.m3u8?VideoCodec=h264"))
    }

    @Test("Une adresse déjà absolue n'est pas préfixée deux fois")
    func absoluteAddressesAreLeftAlone() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1
        https://ailleurs.example/main.m3u8
        """
        #expect(lines(manifest).contains("https://ailleurs.example/main.m3u8"))
    }

    @Test("Un manifeste sans variante ne perd pas ses en-têtes")
    func headerOnlyManifestIsPreserved() {
        // Un serveur en erreur peut renvoyer un squelette : mieux vaut le
        // transmettre tel quel et laisser le lecteur signaler l'échec que
        // produire une playlist vide, qui ne dit rien.
        let result = HLSManifest.keepingOnlyFirstVariant(
            of: "#EXTM3U\n#EXT-X-VERSION:7", relativeTo: base
        )
        #expect(result == "#EXTM3U\n#EXT-X-VERSION:7")
    }
}
