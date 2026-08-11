# Sofafin

**Un client Jellyfin natif pour Apple TV.** Écrit en SwiftUI, bâti sur AVKit, pensé
pour être regardé depuis un canapé plutôt qu'inspecté de près.

[![Plateforme](https://img.shields.io/badge/plateforme-tvOS%2026%2B-black)](https://developer.apple.com/tvos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![Licence](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

---

## Pourquoi

Jellyfin sait déjà servir une médiathèque. Ce qui manquait sur Apple TV, c'était un
client qui se comporte comme les applications que le système propose lui-même : un
grand visuel qui réagit au focus, des rangées qui défilent sans à-coups, et surtout
**le lecteur d'Apple plutôt qu'un lecteur maison**.

C'est le parti pris central du projet : `AVPlayerViewController`, avec ses points
d'extension officiels. On y gagne la barre de transport système, Picture in Picture,
AirPlay, le panneau Now Playing, les sous-titres et la sélection audio — tout ce
qu'aucune implémentation maison n'égalerait vraiment.

## Ce que ça fait

- **Accueil** — grand visuel qui suit le focus, reprises de lecture, prochains
  épisodes, ajouts récents, favoris, collections, et des rangées par genre déduites
  de votre médiathèque
- **Lecteur** — saut de générique, chapitres, enchaînement d'épisode avec compte à
  rebours, panneaux d'information au glissement vers le bas, Picture in Picture,
  reprise à la seconde près
- **Bibliothèques** — grille avec tri et filtres, fiches de séries saison par saison,
  collections, distribution cliquable
- **Étagère du haut** — reprises et prochains épisodes directement sur l'écran
  d'accueil du système, avec liens profonds vers la lecture ou la fiche
- **Connexion rapide** — le code s'affiche à l'écran et se valide depuis un téléphone,
  plutôt que de taper un mot de passe à la télécommande
- **Accessibilité** — VoiceOver, Texte plus grand, Texte en gras, Augmenter le
  contraste et Réduire les animations

## Ce que ça ne fait pas

Autant le dire franchement :

- **Pas de lecture directe des fichiers Matroska.** AVFoundation ne lit pas le MKV.
  Le serveur le **remuxe** à la volée (le conteneur change, ni l'image ni le son ne
  sont retouchés) — quelques pour cent de processeur, pas un réencodage. Un client
  qui embarque son propre décodeur, comme Infuse, n'a pas cette contrainte ; il perd
  en échange l'intégration système.
- **Pas de gestion du serveur.** Ni utilisateurs, ni tâches planifiées, ni greffons.
- **Pas de musique, de livres ni de télévision en direct.** Films et séries.
- **Pas de téléchargement hors ligne.**

## Installation

Aucune version binaire n'est distribuée pour l'instant : il faut compiler.

### Ce qu'il vous faut

- macOS avec **Xcode 26** ou plus récent
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- Un serveur **Jellyfin 10.10+** joignable depuis l'Apple TV
- Pour installer sur un vrai Apple TV : un compte développeur Apple, même gratuit

### Compiler

```bash
git clone https://github.com/McSon2/Sofafin.git
cd Sofafin
xcodegen generate
open Sofafin.xcodeproj
```

Le projet Xcode est **généré** depuis `project.yml` : ne le modifiez pas à la main,
il est écrasé. Relancez `xcodegen generate` après chaque ajout de fichier.

Le simulateur fonctionne sans signature. Pour une installation sur un appareil réel,
déclarez votre identifiant d'équipe **sans le versionner** :

```bash
echo 'DEVELOPMENT_TEAM = VOTREEQUIPE' > Signing.local.xcconfig
xcodegen generate
```

### Première connexion

Au lancement, saisissez l'adresse de votre serveur (`192.168.1.10:8096`, ou un nom
de domaine). Le protocole et le port sont devinés si vous les omettez. Puis
choisissez la connexion rapide — le code affiché se valide depuis Jellyfin sur un
autre appareil, dans **Profil → Connexion rapide**.

## Réglage du serveur, à connaître

Si un film **HDR ou Dolby Vision** refuse de démarrer, ou si votre serveur chauffe
alors qu'il devrait seulement remuxer, regardez la conversion HDR → SDR de Jellyfin
(*tone mapping*, dans Lecture → Transcodage) :

- elle **interdit la copie du flux vidéo** et impose un réencodage complet, coûteux
  sur une petite machine ;
- sa variante OpenCL exige un environnement d'exécution que beaucoup d'installations
  n'ont pas, auquel cas ffmpeg s'arrête avant la première image et chaque segment
  répond `HTTP 500`.

L'Apple TV 4K affiche nativement HDR10, HLG et Dolby Vision : **la désactiver donne
une meilleure image et une machine au repos.**

## Architecture

```
Packages/JellyfinKit/     cœur partagé, sans dépendance à l'interface
  JellyfinClient          client HTTP, autorisation, décodage
  Endpoints+*             authentification, bibliothèque, images
  Playback                profil d'appareil, négociation, rapports de session
  CredentialStore         session persistée dans le groupe d'applications
  DeepLink                sofafin://play/<id> et sofafin://item/<id>

Apps/tvOS/Sources/
  AppSession              état global : phase d'authentification, client, bibliothèques
  Design/                 jetons, surfaces de verre, vignettes, rangées, accessibilité
  Features/               Onboarding, Home, Detail, Library, Search, Settings, Player

Apps/TopShelf/            extension de l'étagère du haut (processus séparé)
```

Toute la logique vit dans un paquet Swift sans interface, partagé avec l'extension
et déjà multiplateforme : **un portage macOS ne demanderait de réécrire que les vues.**

`docs/NOTES-PLATEFORME.md`, à la racine, documente les décisions structurantes et les pièges de la
plateforme déjà payés — lecture recommandée avant de toucher au lecteur.

## Contribuer

Les contributions sont bienvenues. Lisez [CONTRIBUTING.md](CONTRIBUTING.md) : il
décrit la mise en route, les conventions du projet, et les quelques règles tvOS
qu'il ne faut pas défaire par inadvertance.

Le plus utile en ce moment :

- **Portage macOS** — `JellyfinKit` est prêt, seules les vues manquent
- **Sous-titres externes en lecture directe**
- **Traductions** — l'interface est aujourd'hui en français uniquement
- **Tests sur des médiathèques variées** — les codecs exotiques sont la principale
  source de surprises

## Vie privée

L'application ne parle **qu'au serveur que vous désignez**. Aucune analytique, aucun
traceur, aucun service tiers, aucune donnée qui sort de votre réseau. Le jeton de
session — révocable depuis Jellyfin, jamais votre mot de passe — est conservé
localement pour vous éviter de vous reconnecter.

## Licence

[MIT](LICENSE).

Ce projet n'est pas affilié au projet Jellyfin. Jellyfin est une marque de ses
propriétaires respectifs.
