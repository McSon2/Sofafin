# Notes de plateforme

Ce document rassemble les décisions structurantes du projet et les pièges de tvOS
déjà payés — à lire avant de toucher au lecteur.

Sofafin est un client Jellyfin natif pour Apple TV, destiné à remplacer Infuse. Interface inspirée
de Netflix (billboard plein cadre, rangées horizontales, focus qui fait vivre l'écran)
sur les matières de Liquid Glass.

Cible **tvOS 26 d'abord**, portage macOS ensuite — d'où l'isolement de toute la
logique dans un Swift Package, les vues étant la seule couche à réécrire.

Développé contre un serveur Jellyfin 10.11. L'adresse du vôtre se règle à
l'écran de connexion ; aucune n'est inscrite dans le dépôt.

---

## Commandes

Le projet Xcode est **généré** : ne jamais l'éditer à la main, il est écrasé.

```bash
xcodegen generate     # après modification de project.yml ET à chaque fichier ajouté

xcodebuild -project Sofafin.xcodeproj -scheme Sofafin-tvOS \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -configuration Debug clean build
```

> **Toujours `clean build`.** Le build incrémental de ce projet est cassé :
> `xcodebuild build` répond « BUILD SUCCEEDED » **sans recompiler**, même quand les
> sources sont plus récentes que le binaire — on installe alors en boucle une
> version périmée en croyant tester ses corrections. Vérifier après coup qu'un
> symbole récemment ajouté est bien présent :
>
> ```bash
> nm .../Sofafin-tvOS.app/Sofafin-tvOS.debug.dylib | grep -c MonNouveauType
> ```
>
> Attention : en Debug, Xcode 26 place le code applicatif dans
> `Sofafin-tvOS.debug.dylib`, **pas** dans l'exécutable `Sofafin-tvOS` — dont
> la date ne bouge jamais. Inspecter le mauvais fichier fait conclure à tort.
>
> Ne pas passer `CODE_SIGNING_ALLOWED=NO` : cela supprime les droits, donc le
> groupe d'applications, donc le Top Shelf.

Installer sur un simulateur (`install` par-dessus **préserve** la session ;
`uninstall` l'efface — à éviter) :

```bash
APP=~/Library/Developer/Xcode/DerivedData/Sofafin-*/Build/Products/Debug-appletvsimulator/Sofafin-tvOS.app
xcrun simctl install <UDID> $APP
xcrun simctl launch <UDID> com.maximesaltet.sofafin -serverAddress "<hôte>:8096"
```

Le paramètre `-serverAddress` pré-remplit le champ du serveur ; il est aussi inscrit
dans le schéma Xcode, donc actif à chaque ⌘R.

Journal de l'application :

```bash
xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "com.maximesaltet.sofafin"'
```

Icônes (catalogue tvOS complet depuis une image) :

```bash
python3 Tools/make_icons.py --source Design/icon-source.png
```

### Simulateurs

| Nom | Usage |
|---|---|
| `Apple TV 4K (3rd generation)` | Celui de travail, **session connectée** — ne pas la détruire |
| Un second simulateur | Session vierge, pour revoir l'onboarding |

Plusieurs dossiers `DerivedData/Sofafin-*` peuvent coexister après un déplacement
du projet. Récupérer le bon plutôt que de piocher au hasard :

```bash
xcodebuild ... -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2}'
```

---

## Structure

```
Packages/JellyfinKit/        cœur partagé app + extension (aucune dépendance UI)
  JellyfinClient.swift       client HTTP, en-tête d'autorisation, décodage
  Endpoints+*.swift          auth & Quick Connect, bibliothèque, images
  Playback.swift             profil d'appareil, négociation, rapports de session
  CredentialStore.swift      session persistée, groupe partagé, migration
  DeepLink.swift             sofafin://play/<id> et sofafin://item/<id>

Apps/tvOS/Sources/
  AppSession.swift           état global : phase d'auth, client, bibliothèques
  RootView.swift             TabView, piles de navigation, retour à la racine
  Design/                    jetons, surfaces de verre, vignettes, rangées
    Theme.swift              styles sémantiques, couleurs adaptatives, métriques
    Accessibility.swift      descriptions VoiceOver, animations facultatives
    FocusParallax.swift      profondeur et reflet d'une vignette au focus
    ImagePrefetcher.swift    amorce le réseau pendant le préchargement des piles
  Features/{Onboarding,Home,Detail,Library,Search,Settings,Player}/

  Features/Player/
    PlaybackEngine.swift            possède l'AVPlayer : négociation, reprise, rapports
    PlaybackEngine+Decorations.swift affordances posées sur AVPlayerViewController
    PlaybackEngine+NowPlaying.swift session audio, panneau système, commandes distantes
    PlaybackEngine+Diagnostics.swift pourquoi une lecture ne démarre pas
    NextEpisodeProposal.swift       AVContentProposalViewController de fin d'épisode
    PlayerPanels.swift              panneaux du swipe-bas et bandeau superposé

Apps/TopShelf/Sources/       extension de l'étagère du haut (processus séparé)
Tools/make_icons.py          catalogue d'icônes tvOS (piles de calques)
Design/icon-prompt.md        prompts de génération de l'icône
```

Les **Human Interface Guidelines d'Apple TV** font autorité pour toute décision
d'interface : https://developer.apple.com/design/human-interface-guidelines/tvos

---

## Décisions structurantes

**AVPlayer, pas VLCKit.** On gagne les contrôles système, Liquid Glass sur la barre
de lecture, PiP, AirPlay et Now Playing. En contrepartie AVFoundation ne lit pas le
Matroska : le profil d'appareil (`DeviceProfileFactory.appleTV`) déclare HLS + fMP4
en transcodage, ce qui pousse Jellyfin à **remuxer sans réencoder** — quelques pour
cent de CPU. Le QuickSync du serveur absorbe le reste.

**Les bibliothèques sont chargées avant d'entrer dans l'interface.** Les charger
après reconstruisait la barre d'onglets, détruisait `HomeView` et **annulait ses
requêtes en vol** — l'accueil s'affichait vide alors que le serveur répondait. Les
modèles vérifient aussi `Task.isCancelled` avant de conclure à une médiathèque vide.

**Quick Connect est la voie d'entrée principale.** Taper un mot de passe à la
télécommande est un supplice ; le code s'affiche à l'écran et se valide depuis un
autre appareil.

**Les actions qui modifient l'état côté serveur incrémentent `session.libraryRevision`.**
Les écrans s'y abonnent via `.task(id:)` : sans cela, un titre marqué comme vu
resterait affiché dans « Reprendre la lecture ». **Tout écran affichant des
vignettes doit s'y abonner** — leur menu contextuel porte « marquer comme vu » et
« ajouter aux favoris », donc n'importe lequel peut être l'origine du changement.
L'abonnement recharge ce qui porte un état modifiable, jamais la structure de
l'écran : sur une fiche de série, recharger les saisons ramènerait l'utilisateur
sur celle d'origine alors qu'il en parcourait une autre (`refreshUserState`).

**Un clic simple sur un épisode lance la lecture** ; la fiche s'obtient par appui
long (`MediaCardMenu`). Une fiche ouverte sur un épisode affiche **la série**, saison
correspondante déjà sélectionnée — un épisode seul est un cul-de-sac.

---

## Pièges tvOS déjà payés

**Liquid Glass est partiel.** `.buttonStyle(.glass)` et `.glassProminent` existent ;
`.glassEffect()` et `GlassEffectContainer` **non** (contrairement à iOS/macOS). Les
surfaces sont reconstruites dans `Design/LiquidGlass.swift` : matière + arête
spéculaire + ombre. `GlassButtonStyle` est un `PrimitiveButtonStyle`, donc impossible
à ranger derrière un type effacé — voir `SelectableChip` pour le contournement.

**Les dates .NET portent sept décimales** (`…T21:04:11.7830000Z`).
`ISO8601DateFormatter` n'en accepte que trois et rejette le reste, ce qui ferait
échouer le décodage de tout item daté. Troncature dans `JellyfinClient.parseJellyfinDate`.

**Le trousseau n'est pas persistant sur tvOS** : Apple ne le garantit pas et le
système peut le purger. La session vit dans les préférences du groupe
`group.com.maximesaltet.sofafin` (un jeton révocable, pas un mot de passe), avec
migration automatique depuis l'ancien domaine local.

**Un `TextField` tvOS exige une police système** (`.headline`, `.title2`…) : avec
`.system(size:)` le contrôle cale le texte en haut de sa pilule. Il dessine déjà son
fond — l'envelopper dans une surface décorative produit une boîte dans une boîte. Le
centrage vertical se corrige par `baselineOffset`, jamais par un décalage de la vue.

**Pas de contour blanc au focus** : une bordure suit mal les coins d'une carte et
déborde sur son titre. Le vocabulaire tvOS est l'agrandissement et l'ombre
(`FocusLift`).

**Le catalogue d'icônes tvOS** est une pile de calques dont l'ordre doit être
**déclaré** dans le `Contents.json` (sinon Xcode trie par nom et « Middle » finit au
fond), et dont le calque le plus profond doit être opaque et remplir exactement le
cadre, à chaque échelle.

**Ne jamais imposer `startTimeTicks` dans l'URL de transcodage.** En HLS, Jellyfin
publie une playlist couvrant **tout** le média et transcode à la demande le segment
réclamé : le lecteur se déplace donc librement dedans. Forcer une position produit un
flux tronqué qui refuse de démarrer. La reprise se fait **côté client**, dans tous les
modes — et jamais avant que l'élément soit `readyToPlay` : avant cela sa durée est
inconnue et `seek` est **ignoré sans erreur**, ce qui fait repartir le film du début
alors que la position demandée était juste. Corollaire : la timeline correspond
toujours au média entier, `position == temps écoulé`.

**Le lecteur s'enrichit par les points d'extension d'AVKit, jamais en réécrivant
les contrôles.** `contextualActions` porte le « Passer l'intro », `nextContentProposal`
la fin d'épisode, `customInfoViewControllers` les panneaux du swipe-bas,
`navigationMarkerGroups` les chapitres, `transportBarCustomMenuItems` et
`customOverlayViewController` le reste. Cinq pièges, tous payés :

- `AVPlayerViewControllerDelegate` **n'est pas isolé** : une classe `@MainActor` ne
  peut s'y conformer qu'en écrivant `NSObject, @MainActor AVPlayerViewControllerDelegate`.
- `customInfoViewControllers` sont dimensionnés par leur **`preferredContentSize`**.
  Sans elle, le panneau s'ouvre sur une bande grise : les onglets sont là, le
  contenu est écrasé à zéro.
- **`navigationMarkerGroups` a été retiré, ne pas le remettre.** Il semble être le
  moyen officiel de poser les chapitres sur la timeline, mais AVKit en tire un
  **second bouton** dans la barre de transport, à l'icône de liste — la même que
  celle du menu « Chapitres ». Ce bouton ouvre un panneau de vignettes qu'AVKit
  fabrique en échantillonnant le média : sur un flux HLS transcodé à la demande,
  sans piste de défilement rapide, il n'y parvient pas et n'affiche qu'une **carte
  grise vide**. Les chapitres passent donc par le menu textuel de
  `transportBarCustomMenuItems`, et les segments par « Passer l'intro »
  (`contextualActions`), qui n'en dépend pas.
- **`automaticAcceptanceInterval` ne se décompte qu'à partir de la fin du média**,
  alors que la proposition s'affiche dès le début du générique : les deux durées
  s'additionnent au lieu que la seconde borne la première, et un générique d'une
  minute et demie donnait près de deux minutes avant l'enchaînement. Le délai qui
  fait foi est celui que `NextEpisodeProposalViewController` pose lui-même à son
  apparition (`acceptanceDelay`, 15 s) — une échéance sur
  `dateOfAutomaticAcceptance` pour que le décompte affiché soit juste, doublée
  d'une minuterie qui l'honore, générique en cours ou non.
- `contextualActions` ne doit être reconstruit que sur changement réel de segment.
  Le recréer à chaque battement le fait clignoter et lui reprend le focus au moment
  où l'utilisateur le presse.
- Le **`playerLayoutGuide`** d'un `AVContentProposalViewController` n'est rattaché
  à aucune vue tant qu'AVKit n'a pas présenté le contrôleur : s'y contraindre dans
  `viewDidLoad` lève `NSGenericException` (« no common ancestor ») et **tue
  l'application à la fin du premier épisode ayant une suite**. Le crash ne se
  produit donc jamais avant d'avoir regardé un épisode jusqu'au bout, ce qui le
  rend facile à manquer. `NextEpisodeProposal` pose d'abord des ancres sur sa
  propre vue, puis bascule sur le guide depuis `viewWillLayoutSubviews` une fois
  vérifié que les deux partagent une racine.

**Les piles paresseuses ont trois règles, toutes payées par l'expérience.**
Une `LazyHStack` ou une `LazyVGrid` construit ses vues **en avance** sur le
défilement — c'est sa fenêtre de préchargement, et le seul code qui s'y exécute
est l'`init` des vues. `onAppear` et `.task` arrivent trop tard : d'où
`ImagePrefetcher`, appelé depuis l'`init` de `RemoteImage`, qui remplit
`URLCache.shared` pendant que la vignette est encore hors champ. Il est **plafonné
à trois requêtes simultanées et suspendu pendant la lecture** : les affiches et le
flux vidéo sortent du même serveur, et un préchargement sans bride affame Jellyfin
au moment où il remuxe — la lecture se fige alors sur son indicateur de chargement
avec le son qui continue, puisque lui est déjà tamponné. Au-delà du plafond une
demande est abandonnée, jamais mise en file : `AsyncImage` reste le filet. Ensuite, une
rangée horizontale prend la hauteur de sa **première** sous-vue : tout texte de
vignette porte donc `lineLimit(_:reservesSpace: true)`, faute de quoi une carte au
titre absent rognerait toutes les autres. Enfin, l'offset d'une pile paresseuse est
*estimé* et instable — se positionner passe par `ScrollPosition.scrollTo(id:)`
avec `scrollTargetLayout()`, jamais par un `ScrollViewReader` (qui exige que la
vue visée existe déjà) ni par un calcul d'offset.

**Toute fermeture confiée au système et créée dans une méthode `@MainActor` en
hérite l'isolation.** Swift 6 la marque implicitement, et le jour où le système
l'appelle depuis sa propre file — ce qu'il ne promet jamais de ne pas faire — le
processus s'arrête net : `EXC_BREAKPOINT` (`brk #0x1`) sur un fil de fond, **sans
exception, sans message, sans pile applicative**. Le numéro du fil dans le
rapport est le seul indice ; un fil autre que le premier désigne une violation
d'isolation, jamais une erreur de logique. Écrire `@Sendable` sur la fermeture, ou
la fabriquer depuis une fonction `nonisolated`. Deux cas rencontrés :
`MPMediaItemArtwork(boundsSize:requestHandler:)`, dont le système réclame l'image
quand il en a besoin, et les cibles de `MPRemoteCommandCenter`.

**`MainActor.assumeIsolated` est un piège dans tout rappel dont on ne choisit pas
la file.** Il n'endort pas le compilateur : il *affirme* être sur l'acteur
principal, et l'affirmation fausse arrête le processus **sans exception ni trace**
— le journal s'interrompt net, sans « Terminating app ». Deux sources en sont
dépourvues de garantie : les observations **KVO** (délivrées sur la file qui a
modifié la propriété, jamais promise principale par AVFoundation) et les
gestionnaires de **`MPRemoteCommandCenter`**, appelés depuis la file de MediaRemote.
Y écrire `Task { @MainActor in … }`. L'affirmation n'est légitime que là où la file
est imposée par nous — `addPeriodicTimeObserver(queue: .main)`,
`addObserver(queue: .main)` — ou par UIKit, comme les `UIAction`.

**`AVPlayerViewController` ne renseigne pas Now Playing.** Il sait décorer ses
propres contrôles depuis `externalMetadata`, mais le panneau système — télécommande,
Control Center, écran d'accueil, AirPlay — passe par MediaRemote, qui réclame trois
choses distinctes : une `AVAudioSession` **active** (sans elle l'app n'est pas le
lecteur courant), `MPNowPlayingInfoCenter.nowPlayingInfo`, et des commandes
`MPRemoteCommandCenter`. Il manquait les trois, d'où le
`MRPlaybackQueueServiceClient … "requires a client data source"` en boucle dans le
journal. La durée publiée vient de la fiche Jellyfin et non de l'`AVPlayerItem`,
indéfinie tant qu'il n'est pas prêt. La position n'est **pas** republiée à chaque
battement : le système extrapole depuis la vitesse annoncée, on ne le réaligne donc
qu'aux pauses, aux reprises et lorsqu'un écart supérieur au pas du battement trahit
un déplacement dans la timeline — AVKit ne notifie pas les repositionnements venus
de ses propres contrôles. Les gestionnaires de commande retiennent le moteur : les
retirer à l'arrêt, sinon la télécommande agit sur un lecteur déjà fermé. Enfin, ne
pas régler `playbackState` : il exige l'autorisation privée
`com.apple.mediaremote.set-playback-state`, qu'une application tierce n'obtient
pas — le système l'ignore en le consignant. La vitesse publiée suffit à lui faire
déduire l'état.

**Le tone mapping du serveur doit rester désactivé — c'est lui qui décidait de tout.**
Réglé le 2026-08-11 dans `/opt/appdata/jellyfin/encoding.xml` (sauvegarde
`.bak-20260811`) : `EnableTonemapping` **et** `EnableVppTonemapping` à `false`.

Deux conséquences distinctes, dans cet ordre :

1. **Les films HDR ne démarraient pas.** `EnableTonemapping` (variante OpenCL) fait
   passer `-init_hw_device opencl=ocl@va` à ffmpeg, or le conteneur n'embarque aucun
   runtime OpenCL. ffmpeg s'arrêtait sur `Failed to get number of OpenCL platforms:
   -1001` **avant d'écrire la moindre image**, et chaque segment répondait HTTP 500 —
   y compris `hls1/main/-1.mp4`, qui n'est pas un « segment −1 » mais le fichier
   d'**initialisation fMP4** (`-hls_fmp4_init_filename "<id>-1.mp4"`). Ne pas
   réactiver tant qu'`intel-opencl-icd` n'est pas dans l'image.
2. **Le tone mapping interdit la copie du flux.** Convertir le HDR en SDR impose un
   réencodage complet : `hevc_qsv -profile:v:0 main` sur du 4K, à peine plus rapide
   que le temps réel sur un N100. En le coupant, le même fichier passe en
   `-codec:v:0 copy -codec:a:0 copy` à **~100× le temps réel** — un simple
   changement de conteneur — et le HDR arrive intact sur l'Apple TV, qui sait
   l'afficher. Les `CodecProfiles` du profil d'appareil, eux, sont bien transmis
   (`hevc-rangetype=…`) mais **ne suffisent pas** à éviter la conversion : seul le
   réglage serveur compte.

Contrepartie assumée : un client qui ne gère pas le HDR (navigateur) recevra des
couleurs délavées sur ces fichiers, puisque plus personne ne les convertit.

**Une lecture qui ne démarre pas est muette par défaut.** La négociation avec
Jellyfin réussit presque toujours — le serveur répond, un plan est construit, une
URL est produite, et la ligne `LECTURE` s'affiche. Tout ce qui échoue ensuite se
passe dans AVFoundation, qui ne signale rien de lui-même : l'écran tourne
indéfiniment. Les traces `<<<< PlayerRemoteXPC >>>>` et `<<<< Async >>>>` du
journal système sont du bruit interne de CoreMedia — on les voit aussi sur des
lectures qui fonctionnent, elles ne prouvent rien. Ce qui parle, et que
`PlaybackEngine+Diagnostics` consigne : `AVPlayerItem.errorLog()`, qui porte le
**code HTTP et l'URI des segments refusés**, le statut `.failed` avec son erreur
sous-jacente, et une surveillance de 30 s pour le cas le plus déroutant — aucune
erreur, mais rien qui démarre. L'URL du flux est journalisée en clair : c'est elle
qu'on rejoue dans `ffplay` pour trancher entre le serveur et le lecteur. Quand le
transcodage est en cause, la raison n'est jamais côté client : elle est dans
`/config/log/ffmpeg-transcode-*.log` sur le serveur.

**Les bandes-annonces ne peuvent être que des fichiers locaux.** Jellyfin expose
aussi des `RemoteTrailers`, mais ce sont des liens YouTube : tvOS n'embarque **aucun
moteur web** (ni `WebKit`, ni `SafariServices`), et YouTube ne diffuse pas de flux
qu'un lecteur puisse pointer. Changer de lecteur n'y change rien. La fiche n'affiche
donc son bouton que si `/Items/{id}/LocalTrailers` renvoie quelque chose.

Ces fichiers se produisent côté serveur par un script planifié (`yt-dlp`). Il choisit
dans les `RemoteTrailers` que Jellyfin a déjà récupérés — VF d'abord, VOST ensuite,
jamais de VO seule — et télécharge en **H.264/MP4 obligatoirement** : l'Apple TV
décode VP9 et AV1 pour l'app YouTube, mais `AVFoundation` ne les lit pas dans un
fichier. Deux pièges déjà payés : `pct exec` et cron donnent un `PATH` sans
`/usr/local/bin`, d'où la résolution explicite du binaire `yt-dlp` ; et Python
tamponne sa sortie quand elle est redirigée, d'où le `-u` dans la ligne de cron.

Le lecteur **ne rapporte rien au serveur pour un `ItemKind.trailer`** : une
bande-annonce interrompue remonterait sinon dans « Reprendre la lecture » au milieu
des films.

**`/MediaSegments/{id}` attend `includeSegmentTypes` répété**, un paramètre par
valeur — et non joint par des virgules comme le reste de l'API Jellyfin, qui
répond alors 400. Les segments eux-mêmes ne viennent pas du serveur nu : ils
exigent un fournisseur (plugin *Intro Skipper*), rangé dans `/config/data/plugins`
et **pas** `/config/plugins`. Sa tâche « Detect and Analyze Media Segments » est
planifiée quotidiennement à minuit : ni l'installation ni un rescan ne la
déclenchent, il faut la lancer à la main la première fois. Une médiathèque sans
segments n'est jamais une erreur — l'absence est absorbée, les affordances
correspondantes ne s'affichent simplement pas.

**Le conteneur d'app group n'est inscriptible que dans `Library/Caches` sur
l'appareil.** Sa racine et `Library/Application Support` sont refusées — alors que
le simulateur accepte tout, ce qui masque complètement le problème. D'où le
sélecteur d'emplacement de `CredentialStore` : il essaie quatre candidats et retient
le premier qui accepte une écriture-test réelle. `isWritableFile` ne sert à rien ici
(faux sur un dossier absent, vrai sur un volume qui refuse ensuite la création).
Comme `Caches` peut être purgé, une copie de la session est gardée dans les
préférences locales et le fichier est réécrit au démarrage suivant.

**Ne pas activer « Runs as Current User »** (`com.apple.developer.user-management`)
pour partager des données avec l'extension : sur tvOS, cette capability rend le
conteneur d'app group carrément inaccessible (`containerURL` renvoie nil) au lieu de
le rendre inscriptible. Symptôme documenté sur les forums Apple, vérifié ici.

**L'extension Top Shelf doit être de type `app-extension`, jamais
`tv-app-extension`.** Ce dernier est hérité des extensions TVML et du
`TVTopShelfProvider` déprécié ; avec lui PlugInKit n'enregistre pas le bundle, et le
système lance le processus puis le tue en dix millisecondes — quel que soit le code
qu'il contient :

```
HeadBoard      Plugin … must have pid! Extension request will fail
HeadBoard      Unable to acquire process assertion in beginUsing:, killing plugin
runningboardd  termination reported by launchd (0, 0, 768)
```

Le bundle est parfaitement formé par ailleurs (point d'extension, classe principale,
signature), ce qui rend le diagnostic trompeur. La bissection tranche vite : réduire
l'extension à un contenu figé sans dépendances ; si elle échoue encore, la cause est
dans la cible, pas dans le code.

---

## Conformité aux directives Apple TV

Audit complet mené contre les Human Interface Guidelines d'Apple TV. Les règles qui
ont façonné le code, et qu'il ne faut pas défaire par inadvertance :

**La typographie ne porte aucune taille absolue.** `Theme.Font` s'appuie sur les
styles sémantiques de tvOS (`.body`, `.headline`, `.caption`…), qui partent déjà
des minima du salon — corps à 29 pt, libellé secondaire à 25 pt — et suivent seuls
« Texte plus grand » et « Texte en gras ». Une `.system(size:)` réintroduite dans
une vue casse les trois d'un coup. Les seules tailles fixes restantes sont des
glyphes décoratifs et le logo d'accueil, tous au-delà de 56 pt.

**Les couleurs sont des `UIColor` dynamiques**, pas des `Color` figées : c'est ce
qui les fait répondre à « Augmenter le contraste » sans que la moindre vue lise
l'environnement.

**Un rechargement de bibliothèque ne démonte jamais l'écran.** `load(silently:)`
dans `HomeModel` et `LibraryView` distingue l'ouverture d'un écran — qui mérite son
indicateur — du rafraîchissement déclenché par un « vu », un favori, un retour de
lecture ou un retour au premier plan. Vider les rangées le temps d'un aller-retour
au serveur détruit la position du focus, ce que les directives interdisent
explicitement. Même raison pour `hasClaimedInitialFocus` : le focus par défaut ne
se réclame qu'une fois.

**Une distinction visuelle au focus n'est pas décorative.** `focusable()` seul
déplace le focus sans rien changer à l'écran : toujours l'accompagner de
`focusLift`. « Réduire les animations » calme le ressort mais ne supprime ni
l'agrandissement ni l'ombre — voir `FocusLift`, à l'inverse de
`decorativeAnimation` qui, lui, s'efface complètement.

**Les vignettes parlent d'une seule voix** : `accessibilityElement(children: .ignore)`
plus `MediaItem.accessibilityDescription`. Énumérer titre, barre de progression et
coin de couleur n'apprendrait rien à qui ne voit pas la carte.

**Les résolutions d'images visent l'échelle 2 d'une Apple TV 4K**, focus compris —
une affiche de 280 points en réclame 610 en pixels. Voir les valeurs par défaut de
`Endpoints+Images.swift` : les baisser fait étirer l'image par le lecteur.

### Écarts assumés

- **Navigation par barre latérale** (`.sidebarAdaptable`) là où les directives prescrivent
  une barre d'onglets en haut. Conservée sciemment : c'est le pattern de l'app TV
  d'Apple depuis tvOS 18, et il sert le parti pris plein cadre. Les directives décrivent
  l'état antérieur de la plateforme sur ce seul point.
- **Parallaxe partielle** (`FocusParallax`) : profondeur et reflet spéculaire au
  focus, mais pas de suivi du doigt sur la surface tactile. Celui-ci n'est pilotable
  que depuis le moteur de focus d'UIKit, inaccessible à une carte qui est un
  `Button` SwiftUI. Y accéder demanderait de réécrire les vignettes en UIKit, donc
  de faire cohabiter deux systèmes de focus dans la même hiérarchie.
- **`onExitCommand` sur le lecteur** est un filet, pas une certitude : reste à
  confirmer sur l'appareil si AVKit consomme déjà le bouton Menu quand son
  contrôleur est embarqué dans un `fullScreenCover`.

## Reste à faire

- Port macOS (les vues seulement, `JellyfinKit` est déjà multiplateforme)
- Sous-titres externes en lecture directe (AVPlayer ne les charge pas sur un MP4 ;
  ils passent aujourd'hui par le remux HLS)
- Vérifier le Top Shelf sur l'appareil : l'icône doit être dans la rangée du haut,
  et le groupe d'applications doit être provisionné à la signature
