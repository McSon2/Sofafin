import Foundation
import SwiftUI

/// Langue de l'interface.
///
/// tvOS n'offre aucun réglage de langue par application : le système impose la
/// sienne. Une médiathèque se regarde pourtant souvent à plusieurs, et la langue
/// de l'appareil n'est pas toujours celle qu'on veut lire à l'écran — d'où ce
/// choix explicite, gardé dans les préférences.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Suit la langue de l'Apple TV.
    case system
    case french = "fr"
    case english = "en"

    var id: String { rawValue }

    /// Libellé affiché dans les réglages. Chaque langue est nommée **dans sa
    /// propre langue** : c'est la convention d'Apple, et la seule qui permette de
    /// s'y retrouver quand on ne comprend pas la langue courante.
    var label: String {
        switch self {
        case .system: return String(localized: "Langue de l'Apple TV")
        case .french: return "Français"
        case .english: return "English"
        }
    }

    /// `nil` pour `system` : on laisse alors le système résoudre.
    var locale: Locale? {
        self == .system ? nil : Locale(identifier: rawValue)
    }

    /// Paquet de ressources de la langue choisie.
    ///
    /// Indispensable pour tout ce qui ne passe pas par SwiftUI — les titres des
    /// menus du lecteur, par exemple, sont réclamés par UIKit et n'ont aucune
    /// notion de l'environnement de la vue.
    var bundle: Bundle {
        guard self != .system,
              let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}

/// Langue retenue, lisible depuis n'importe où.
///
/// Le réglage vit dans `UserDefaults` plutôt que dans un état SwiftUI : les
/// chaînes du lecteur sont fabriquées loin de toute vue, et doivent pouvoir
/// interroger ce choix sans qu'on le leur passe de main en main.
///
/// Volontairement **sans isolation** : les libellés des filtres, des tris et des
/// descriptions VoiceOver sont des propriétés calculées de types qui n'ont aucune
/// raison d'appartenir au fil principal. `UserDefaults` étant sûr d'accès
/// concurrent et rien n'étant conservé ici, il n'y a pas d'état à protéger.
enum Localization {
    private static let key = "appLanguage"

    static var current: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Chaîne traduite dans la langue choisie par l'utilisateur.
///
/// À utiliser partout où SwiftUI ne peut pas s'en charger seul : `Text("…")` et
/// consorts résolvent déjà leurs littéraux à partir de l'environnement, et n'ont
/// pas besoin de cette fonction.
func L(_ key: String.LocalizationValue) -> String {
    let language = Localization.current
    return String(localized: key, bundle: language.bundle, locale: language.locale ?? .current)
}
