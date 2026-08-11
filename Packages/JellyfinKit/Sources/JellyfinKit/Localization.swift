import Foundation

/// Traduction des quelques textes que ce paquet destine à l'écran.
///
/// Le principe est le même que côté application, mais les ressources sont
/// **celles du paquet** (`Bundle.module`) : un paquet Swift embarque ses propres
/// traductions et ne voit pas celles de l'application qui l'utilise.
///
/// La langue retenue est lue dans les préférences partagées plutôt que reçue en
/// paramètre : ces textes sont produits par des propriétés calculées de modèles
/// — `runtimeLabel`, `rowSubtitle` — appelées depuis des dizaines d'endroits, et
/// les faire toutes transporter une locale rendrait le modèle illisible pour un
/// bénéfice nul.
enum PackageLocalization {
    static var languageBundle: Bundle {
        guard let code = UserDefaults.standard.string(forKey: "appLanguage"),
              code != "system",
              let path = Bundle.module.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .module }
        return bundle
    }

    static var locale: Locale {
        guard let code = UserDefaults.standard.string(forKey: "appLanguage"), code != "system"
        else { return .current }
        return Locale(identifier: code)
    }
}

/// Chaîne traduite, tirée des ressources du paquet.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: PackageLocalization.languageBundle, locale: PackageLocalization.locale)
}
