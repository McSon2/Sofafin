import Foundation

/// Transformations de la playlist maître HLS servie par Jellyfin.
///
/// Ce sont des manipulations de texte, sans lecteur ni serveur : elles vivent
/// ici pour être vérifiées par les tests, alors que leur seul usage — installer
/// un délégué de chargement sur l'élément lu — appartient à l'application.
public enum HLSManifest {

    /// L'adresse de la première variante déclarée, en absolu.
    ///
    /// La donner directement au lecteur le prive de tout choix : il charge une
    /// playlist média, pas un catalogue. C'est ce qu'on veut, parce que le choix
    /// se fait mal — Jellyfin propose trois variantes de même débit dont deux
    /// replis convertis en SDR qu'il ne peut produire qu'en réencodant l'image,
    /// et le lecteur, depuis tvOS 13, retient celle qui promet le meilleur
    /// démarrage plutôt que la première. À débit égal, c'est un tirage au sort.
    ///
    /// Réécrire la playlist maître aurait préservé les pistes de sous-titres
    /// qu'elle déclare, mais suppose de la servir soi-même, et le lecteur de
    /// l'Apple TV ne lit pas la sienne dans son propre processus : ce qui
    /// fonctionne sur un Mac y échoue sans rien expliquer.
    public static func firstVariantURL(in manifest: String, relativeTo base: URL) -> URL? {
        var lines = manifest.components(separatedBy: .newlines).makeIterator()
        while let line = lines.next() {
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("#EXT-X-STREAM-INF") else { continue }
            // L'adresse suit la déclaration, éventuellement après des commentaires.
            while let candidate = lines.next() {
                let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                return URL(string: absolute(trimmed, relativeTo: base))
            }
        }
        return nil
    }

    /// Ne conserve que la première variante et rend absolues toutes les adresses.
    ///
    /// Jellyfin propose trois variantes pour un film HDR, toutes au même débit :
    /// la première garde la plage d'origine et lui permet de **recopier** le
    /// flux, les deux suivantes sont des replis convertis en SDR qu'il ne peut
    /// produire qu'en réencodant l'image. L'ordre dit laquelle vaut mieux, mais
    /// rien n'oblige le lecteur à le suivre — et il ne le suit pas : depuis
    /// tvOS 13 il retient celle qui promet le meilleur démarrage, ce qui à débit
    /// égal revient à tirer au sort.
    ///
    /// Pire, un film HDR10+ porte `SUPPLEMENTAL-CODECS="…/cdm4"`. Le lecteur ne
    /// connaît pas cette surcouche, déclare la variante inéligible et se rabat
    /// sur un repli — donc sur un réencodage 4K complet. L'étiquette est donc
    /// retirée avec les autres variantes : elle ne décrit qu'un raffinement de
    /// métadonnées, et le flux qu'elle accompagne reste du HEVC Main 10 PQ que
    /// l'appareil affiche en HDR10, comme le ferait n'importe quel téléviseur
    /// sans HDR10+.
    ///
    /// Les adresses deviennent absolues parce que la playlist réécrite n'est plus
    /// servie depuis le serveur : une adresse relative s'y résoudrait contre un
    /// schéma d'emprunt que personne ne sait joindre.
    public static func keepingOnlyFirstVariant(of manifest: String, relativeTo base: URL) -> String {
        var lines: [String] = []
        var keptVariant = false
        var skipNextURI = false

        for line in manifest.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if skipNextURI {
                // L'adresse d'une variante écartée suit sa déclaration, mais des
                // commentaires peuvent s'intercaler.
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") { skipNextURI = false }
                continue
            }

            if trimmed.hasPrefix("#EXT-X-STREAM-INF") {
                guard !keptVariant else {
                    skipNextURI = true
                    continue
                }
                keptVariant = true
                lines.append(strippingSupplementalCodecs(from: trimmed))
                continue
            }

            // Les pistes de sous-titres sont déclarées ici, et la variante retenue
            // les référence : les perdre priverait le film de ses sous-titres.
            if trimmed.hasPrefix("#EXT-X-MEDIA") {
                lines.append(absolutingURIAttribute(in: trimmed, relativeTo: base))
                continue
            }

            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                lines.append(absolute(trimmed, relativeTo: base))
                continue
            }

            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    static func strippingSupplementalCodecs(from line: String) -> String {
        guard let range = line.range(of: #"SUPPLEMENTAL-CODECS="[^"]*",?"#, options: .regularExpression) else {
            return line
        }
        var cleaned = line
        cleaned.removeSubrange(range)
        // L'attribut pouvait clore la liste : la virgule qui le précédait rendrait
        // alors la ligne invalide.
        if cleaned.hasSuffix(",") { cleaned.removeLast() }
        return cleaned.replacingOccurrences(of: ",,", with: ",")
    }

    static func absolute(_ path: String, relativeTo base: URL) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        return URL(string: path, relativeTo: base)?.absoluteString ?? path
    }

    static func absolutingURIAttribute(in line: String, relativeTo base: URL) -> String {
        guard let range = line.range(of: #"URI="[^"]*""#, options: .regularExpression) else { return line }
        let value = String(line[range]).dropFirst(5).dropLast()
        return line.replacingCharacters(in: range, with: #"URI="\#(absolute(String(value), relativeTo: base))""#)
    }
}
