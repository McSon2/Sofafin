import Foundation
import Testing
@testable import JellyfinKit

/// Le profil d'appareil envoyé au serveur.
///
/// C'est lui qui décide de tout ce qui suit : lecture directe, remux ou
/// réencodage. Il part en JSON avec des clés en capitale initiale que le serveur
/// attend au caractère près — une faute de frappe n'échoue pas, elle fait
/// simplement ignorer la déclaration, et le serveur se rabat sur un transcodage
/// complet sans rien dire.
@Suite("Profil d'appareil")
struct DeviceProfileTests {

    private func encoded() throws -> [String: Any] {
        let data = try JSONEncoder().encode(DeviceProfileFactory.appleTV())
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Les clés attendues par le serveur sont en capitale initiale")
    func topLevelKeys() throws {
        let json = try encoded()
        for key in ["Name", "MaxStreamingBitrate", "DirectPlayProfiles",
                    "TranscodingProfiles", "CodecProfiles", "SubtitleProfiles"] {
            #expect(json[key] != nil, "clé absente du profil : \(key)")
        }
    }

    @Test("Le HDR de l'Apple TV est déclaré, sinon le serveur convertit en SDR")
    func hdrIsDeclared() throws {
        let json = try encoded()
        let profiles = try #require(json["CodecProfiles"] as? [[String: Any]])
        let hevc = try #require(profiles.first { $0["Codec"] as? String == "hevc" })
        let conditions = try #require(hevc["Conditions"] as? [[String: Any]])
        let range = try #require(conditions.first { $0["Property"] as? String == "VideoRangeType" })
        let value = try #require(range["Value"] as? String)

        for expected in ["HDR10", "HLG", "DOVI"] {
            #expect(value.contains(expected), "plage non déclarée : \(expected)")
        }
        // Non requis : la condition dit ce qu'on sait rendre, elle n'exige rien.
        // À `true`, un fichier au type de plage inconnu serait refusé.
        #expect(range["IsRequired"] as? Bool == false)
    }

    @Test("Le Matroska n'est pas en lecture directe : AVFoundation ne le lit pas")
    func matroskaIsNotDirectPlay() throws {
        let json = try encoded()
        let profiles = try #require(json["DirectPlayProfiles"] as? [[String: Any]])
        let video = try #require(profiles.first { $0["Type"] as? String == "Video" })
        let containers = try #require(video["Container"] as? String)
        #expect(!containers.contains("mkv"))
        #expect(containers.contains("mp4"))
    }

    @Test("Le transcodage passe par HLS en fragments MP4, ce qui permet le remux")
    func transcodingUsesFragmentedMP4() throws {
        let json = try encoded()
        let profiles = try #require(json["TranscodingProfiles"] as? [[String: Any]])
        let video = try #require(profiles.first { $0["Type"] as? String == "Video" })
        #expect(video["Protocol"] as? String == "hls")
        #expect(video["Container"] as? String == "mp4")
        // Couper ailleurs que sur une image clé produit des segments que le
        // lecteur refuse.
        #expect(video["BreakOnNonKeyFrames"] as? Bool == false)
    }

    @Test("Le débit demandé laisse passer un flux 4K sans le contraindre")
    func bitrateAllowsUHD() throws {
        let json = try encoded()
        let bitrate = try #require(json["MaxStreamingBitrate"] as? Int)
        #expect(bitrate >= 100_000_000)
    }
}
