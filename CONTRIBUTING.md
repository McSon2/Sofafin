# Contribuer à Jellyflix

Merci de vous y intéresser. Ce document dit comment démarrer, et surtout **ce qu'il
ne faut pas défaire sans le savoir** : plusieurs choix du projet paraissent
arbitraires alors qu'ils corrigent un piège précis de la plateforme.

## Mise en route

```bash
brew install xcodegen
git clone https://github.com/McSon2/Jellyflix.git
cd Jellyflix
xcodegen generate
```

Le projet Xcode est **généré** depuis `project.yml`. Ne le modifiez jamais à la
main : il est écrasé. Relancez `xcodegen generate` après tout ajout de fichier.

Pour signer sur un appareil réel, sans versionner votre identité :

```bash
echo 'DEVELOPMENT_TEAM = VOTREEQUIPE' > Signing.local.xcconfig
```

### Compiler

```bash
xcodebuild -project Jellyflix.xcodeproj -scheme Jellyflix-tvOS \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -configuration Debug clean build
```

**Toujours `clean build`.** Le build incrémental de ce projet est trompeur : il
annonce « BUILD SUCCEEDED » sans recompiler, même quand les sources sont plus
récentes que le binaire. On installe alors une version périmée en croyant tester sa
correction. En cas de doute, vérifiez qu'un symbole récent est bien présent :

```bash
nm …/Jellyflix-tvOS.app/Jellyflix-tvOS.debug.dylib | grep -c MonNouveauType
```

En Debug, Xcode place le code applicatif dans `Jellyflix-tvOS.debug.dylib`, **pas**
dans l'exécutable — dont la date ne bouge jamais.

## Ce qu'il ne faut pas défaire

Ces règles viennent des directives d'interface d'Apple TV et de plantages déjà
diagnostiqués. `docs/NOTES-PLATEFORME.md` en donne le détail et les symptômes.

**La typographie n'a aucune taille absolue.** Les jetons de `Theme.Font` reposent
sur les styles sémantiques de tvOS : ils partent des minima lisibles à trois mètres
et suivent seuls « Texte plus grand » et « Texte en gras ». Une `.system(size:)`
réintroduite dans une vue casse les trois d'un coup.

**Un rechargement ne démonte jamais l'écran.** Remplacer une grille par un
indicateur de chargement détruit la position du focus, que l'utilisateur ne peut pas
retrouver sans tout reparcourir. Voir le paramètre `silently:` des modèles.

**`focusable()` sans réaction visuelle est un bug.** Le focus est le seul repère de
position sur un téléviseur : toujours accompagner d'un `focusLift`.

**`MainActor.assumeIsolated` dans un rappel dont vous ne choisissez pas la file.**
Il n'endort pas le compilateur, il *affirme* — et l'affirmation fausse arrête le
processus **sans exception ni trace**, seul le numéro du fil trahissant la cause.
Vaut pour les observations KVO et les rappels de `MPRemoteCommandCenter`. Écrivez
`Task { @MainActor in … }`. Même piège pour toute fermeture confiée au système
depuis un contexte `@MainActor` : marquez-la `@Sendable`.

**Le lecteur s'enrichit par les points d'extension d'AVKit**, jamais en réécrivant
les contrôles. `contextualActions`, `nextContentProposal`, `customInfoViewControllers`,
`transportBarCustomMenuItems`. Chacun a son piège, tous documentés.

## Style

- **Swift 6, concurrence stricte.** Le projet compile sans avertissement ; gardons-le
  ainsi.
- **Commentaires en français**, comme le reste du code. Expliquez **pourquoi**, pas
  ce que le code fait déjà lire. Un commentaire qui décrit un piège évité vaut dix
  qui paraphrasent.
- **Messages de commit** : une ligne de résumé à l'impératif, puis le contexte —
  ce qui n'allait pas, et pourquoi cette solution.

## Signaler un problème

Pour un **problème de lecture**, joignez les lignes `LECTURE ·` du journal : elles
donnent le mode de lecture négocié, l'URL du flux et les codes HTTP des segments
refusés.

```bash
xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "com.maximesaltet.jellyflix"'
```

Précisez aussi la version de Jellyfin, et les caractéristiques du fichier (conteneur,
codec vidéo, profil, plage HDR, pistes de sous-titres) — visibles dans sa fiche côté
serveur. Les codecs exotiques sont la première source de surprises.

Avant d'ouvrir un ticket sur un fichier qui ne démarre pas, vérifiez la conversion
HDR → SDR de votre serveur : c'est la cause la plus fréquente, et elle est côté
serveur. Voir la section correspondante du README.

## Portée des contributions

Sont hors périmètre, pour garder le projet lisible :

- l'administration du serveur (utilisateurs, greffons, tâches) ;
- la musique, les livres et la télévision en direct ;
- le remplacement d'AVKit par un lecteur tiers — c'est le choix fondateur du projet,
  et l'intégration système en dépend entièrement.
