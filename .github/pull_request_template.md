## Ce que ça change

<!-- Ce qui n'allait pas, et pourquoi cette solution plutôt qu'une autre. -->

## Vérifié

- [ ] `swift test` passe dans `Packages/JellyfinKit`
- [ ] `xcodebuild … clean build` passe — **`clean` obligatoire** : le build
      incrémental de ce projet annonce « BUILD SUCCEEDED » sans recompiler
- [ ] Testé sur un appareil ou un simulateur, en décrivant le parcours suivi

## Les règles que je n'ai pas défaites

<!-- Voir CONTRIBUTING.md. Cocher ce qui s'applique au changement. -->

- [ ] Aucune taille de police absolue : les jetons restent sémantiques
- [ ] Aucun rechargement qui démonte l'écran et détruit la position du focus
- [ ] Tout élément focusable a une réaction visible
- [ ] Aucun `MainActor.assumeIsolated` dans un rappel dont la file n'est pas
      choisie par nous, ni de fermeture non `@Sendable` confiée au système
- [ ] Les chaînes visibles sont des littéraux localisables, ou passent par `L()`
