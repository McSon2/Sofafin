# Fiche App Store — Sofafin

Tout ce qui doit être saisi dans App Store Connect. Les textes sont prêts à
coller ; les limites de caractères d'Apple sont respectées.

---

## Identité

| Champ | Valeur |
|---|---|
| Nom | `Sofafin` |
| Sous-titre (30 car. max) | `Votre Jellyfin, vu du canapé` |
| Identifiant de bundle | `com.maximesaltet.sofafin` |
| SKU | `sofafin-tvos` |
| Catégorie principale | Divertissement |
| Catégorie secondaire | Photo et vidéo |
| Prix | Gratuit |
| Politique de confidentialité | `https://maximesaltet.com/sofafin/privacy` |
| Assistance | `https://github.com/McSon2/Sofafin/issues` |
| Site | `https://github.com/McSon2/Sofafin` |

**Version : mettre `1.0` plutôt que `0.1.0`.** Une première publication numérotée
en `0.x` se lit comme un brouillon, et les mises à jour ultérieures partiraient
d'un rang inhabituel. À changer dans `MARKETING_VERSION` (`project.yml`).

---

## Description — français

> Sofafin est un client Jellyfin natif pour Apple TV. Il se connecte au serveur
> que vous hébergez et affiche votre médiathèque comme une application de salon :
> un grand visuel qui réagit au focus, des rangées qui défilent sans à-coups, et
> le lecteur d'Apple plutôt qu'un lecteur maison.
>
> ACCUEIL
> Reprises de lecture, prochains épisodes, ajouts récents, favoris, collections,
> et des rangées par genre déduites de votre médiathèque.
>
> LECTEUR
> Construit sur AVKit, avec ce que cela apporte : barre de transport du système,
> Picture in Picture, AirPlay, panneau Now Playing, sous-titres et pistes audio.
> S'y ajoutent le saut de générique, les chapitres, l'enchaînement d'épisode avec
> compte à rebours, et la reprise à la seconde près.
>
> BIBLIOTHÈQUES
> Grille avec tri et filtres, fiches de séries saison par saison, collections,
> distribution consultable.
>
> ÉTAGÈRE DU HAUT
> Vos reprises et vos prochains épisodes directement sur l'écran d'accueil de
> l'Apple TV, avec accès direct à la lecture.
>
> CONNEXION SANS CLAVIER
> Un code s'affiche à l'écran et se valide depuis un téléphone : pas de mot de
> passe à saisir à la télécommande.
>
> ACCESSIBILITÉ
> VoiceOver, Texte plus grand, Texte en gras, Augmenter le contraste et Réduire
> les animations sont pris en charge.
>
> RESPECT DE LA VIE PRIVÉE
> Sofafin ne parle qu'au serveur que vous désignez. Aucune analytique, aucun
> traceur, aucun service tiers, aucune donnée qui sort de votre réseau.
>
> Sofafin nécessite un serveur Jellyfin 10.10 ou plus récent, que vous hébergez
> vous-même. L'application n'est pas affiliée au projet Jellyfin.

**Mots-clés (100 car. max)**

```
jellyfin,média,serveur,films,séries,streaming,nas,mediatheque,plex,emby,cinema
```

**Nouveautés de cette version**

```
Première version publique.
```

---

## Description — anglais

> Sofafin is a native Jellyfin client for Apple TV. It connects to the server you
> host and shows your library the way a living-room app should: a large backdrop
> that reacts to focus, rows that scroll smoothly, and Apple's player rather than
> a home-grown one.
>
> HOME
> Continue watching, next up, recently added, favourites, collections, and genre
> rows inferred from your own library.
>
> PLAYER
> Built on AVKit, with everything that brings: the system transport bar, Picture
> in Picture, AirPlay, the Now Playing panel, subtitles and audio tracks. Plus
> skip intro, chapters, next-episode hand-off with a countdown, and resume to the
> second.
>
> LIBRARIES
> Grid with sorting and filters, series pages season by season, collections, and
> a browsable cast.
>
> TOP SHELF
> Your resumes and next episodes right on the Apple TV home screen, with direct
> access to playback.
>
> NO KEYBOARD REQUIRED
> A code appears on screen and is approved from your phone — no password typed
> with the remote.
>
> ACCESSIBILITY
> VoiceOver, Larger Text, Bold Text, Increase Contrast and Reduce Motion are all
> supported.
>
> PRIVACY
> Sofafin talks only to the server you point it at. No analytics, no trackers, no
> third-party services, no data leaving your network.
>
> Sofafin requires a Jellyfin 10.10 or newer server that you host yourself. This
> app is not affiliated with the Jellyfin project.

**Keywords (100 char. max)**

```
jellyfin,media,server,movies,shows,streaming,nas,library,plex,emby,home cinema
```

---

## Classification d'âge

Sofafin **n'a pas de contenu propre** : il affiche ce que contient le serveur de
l'utilisateur, dont ni Apple ni nous ne savons rien. Le questionnaire doit être
rempli en conséquence — « Contenu web sans restriction » **oui**, ce qui conduit
à **17+**. C'est la position des autres clients de médiathèque personnelle, et la
sous-déclarer expose à un rejet ou à un retrait ultérieur.

---

## Notes pour la revue

À coller dans « App Review Information → Notes ». Sans compte de démonstration,
un examinateur ne peut rien voir : c'est la première cause de rejet de ce type
d'application.

> Sofafin is a client for Jellyfin, a self-hosted media server. The app has no
> content of its own and no back end: it connects to a server the user provides.
>
> A demo server is available for review:
>   Address:  <à compléter>
>   Username: <à compléter>
>   Password: <à compléter>
>
> Sign-in screen → enter the address above → "Sign in with your account" →
> username and password. Quick Connect is also offered but requires a second
> device, so please use the account fields.
>
> ABOUT App Transport Security
> The app declares NSAllowsArbitraryLoads. Self-hosted media servers are
> overwhelmingly reached over plain HTTP on a local network (e.g. 192.168.x.x:8096)
> and cannot present a valid TLS certificate for a private IP address. The
> exception is required for the app to function at all. No traffic goes anywhere
> other than the server the user explicitly enters. NSAllowsLocalNetworking is
> also declared.

**Il faut un serveur de démonstration accessible depuis l'extérieur** pendant la
revue, avec quelques titres. Sans lui, l'examinateur voit un écran de connexion
et rien d'autre — rejet quasi certain au titre de la règle 2.1.

---

## Captures d'écran

Dans `Design/appstore/`, au format 3840 × 2160 exigé par Apple TV :

| Fichier | Ce qu'il montre |
|---|---|
| `1-accueil.png` | Le visuel d'accueil, métadonnées et actions |
| `2-rangees.png` | Collections et films, agrandissement au focus |
| `3-fiche.png` | Fiche d'un film : synopsis, genres, distribution |
| `4-reprise.png` | Le choix de reprise, propre à l'application |

Apple en accepte jusqu'à dix ; ces quatre couvrent l'essentiel. Une capture du
lecteur en cours de lecture serait un plus.
