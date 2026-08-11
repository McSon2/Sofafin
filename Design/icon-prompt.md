# Prompts d'icône Sofafin (GPT Image)

## Contraintes techniques tvOS — valables pour tous les prompts

L'icône d'une app Apple TV est **paysage** (400 × 240 pt, ratio 5:3), pas carrée.
Elle est **rognée en rectangle à coins arrondis** par le système : rien d'important
dans les coins. Le fond doit être **plein et opaque** — tvOS refuse un calque de
fond transparent. Pas d'ombre portée ni de bordure : le système ajoute les siennes.

Générer en **1536 × 1024** (3:2, le plus proche que propose GPT Image), puis recadrer
en 5:3 en gardant le centre.

---

## Prompt principal — icône complète

> A premium Apple TV app icon, landscape 3:2 composition, for a personal home
> cinema application named Sofafin.
>
> Subject: a single elegant bioluminescent jellyfish, centered, seen from the side,
> floating in deep darkness. Its translucent bell glows from within with warm
> crimson and ember-orange light. Its long trailing tentacles gradually transform,
> as they descend, into strips of 35 mm motion picture film — visible sprocket
> holes along the edges, individual frames catching faint light, the transition
> from organic tentacle to film strip smooth and deliberate, never abrupt.
>
> Lighting: dramatic single-source glow emanating from inside the bell, falling off
> quickly into near-black. Deep charcoal background with a subtle warm vignette,
> like a darkened cinema before the film starts. Rich blacks, no muddy grey.
>
> Style: refined editorial illustration with painterly depth and physical
> materiality — think a hand-crafted film festival poster, not a vector logo and
> not a 3D render. Fine detail in the bell's translucency and the film perforations.
> Restrained, sophisticated, cinematic.
>
> Composition: the jellyfish occupies the central 60% of the frame with generous
> negative space around it; nothing meaningful in the corners. Balanced, calm,
> immediately readable as a silhouette when scaled down to thumbnail size.
>
> Palette: crimson red, ember orange, warm amber highlights, deep charcoal and near
> black. No blue, no purple, no teal.
>
> Absolutely no text, no lettering, no watermark, no UI elements, no play button
> triangle, no rounded corners, no drop shadow, no border, no frame. Do not imitate
> the Netflix logo. Avoid generic glossy tech-startup gradients, lens flares,
> sparkle particles, chrome bevels and plastic 3D shading.

---

## Prompt logotype — celui qui correspond à l'icône en place

C'est cette famille-là qu'utilise l'icône actuelle : le nom composé en grand, rouge
sur noir. Le prompt ci-dessous reprend exactement cette intention pour **SOFAFIN**.

> A premium Apple TV app icon, landscape 3:2 composition. The entire subject is a
> single word rendered as a wordmark: **SOFAFIN**, all capitals, spelled exactly
> S-O-F-A-F-I-N, centered on a pure black background.
>
> Typography: a bold condensed grotesque sans-serif, geometric and confident, with
> tight but even letter spacing. The letterforms are slightly extended vertically,
> flat-terminated, with generous weight — the look of a title card stamped on a
> cinema screen. Crisp edges, no distortion, no italic slant, perfectly level
> baseline. Every letter fully visible and legible.
>
> Colour: the wordmark is a deep saturated crimson red, lit from within so the
> letters glow faintly at their edges against the black. Nothing else is coloured.
>
> Lighting: a soft warm red bloom radiates a short distance from the letters into
> the darkness, then falls off to true black. Very subtle film grain across the
> frame.
>
> Composition: the wordmark occupies the central 70% of the width, horizontally and
> vertically centred, with generous empty margins. Nothing whatsoever in the
> corners. It must stay readable when scaled down to a small thumbnail.
>
> Palette: crimson red, faint ember highlights, deep near-black. No blue, no purple,
> no white.
>
> Do not imitate the Netflix wordmark, its exact typeface, or its arched
> perspective — keep the letters flat and level, and the type geometric rather than
> humanist. No tagline, no second line of text, no play button, no jellyfish, no
> icon, no UI, no rounded corners, no drop shadow, no border, no frame, no
> watermark. Avoid glossy 3D bevels, chrome, lens flares and sparkle particles.

**Vérifier avant d'intégrer** : les modèles d'images se trompent régulièrement sur
l'orthographe. Relire lettre à lettre — S, O, F, A, F, I, N — et régénérer plutôt
que retoucher si une lettre manque ou se dédouble.

---

## Variante — si la méduse ne convient pas

> A premium Apple TV app icon, landscape 3:2 composition, for a personal home
> cinema application.
>
> Subject: heavy crimson velvet theatre curtains parting at the exact center to
> reveal a narrow vertical shaft of warm projector light spilling forward, dust
> motes drifting through the beam. The curtains are photographed close, their
> folds deep and tactile, the fabric weave visible.
>
> Lighting: the light source is behind the curtains — everything else falls into
> deep shadow. Strong contrast, warm light against cold darkness.
>
> Style: cinematic still photography, shallow depth of field, rich film grain,
> physical texture. Not illustration, not 3D render.
>
> Composition: perfectly symmetrical, the light shaft on the central vertical axis,
> nothing meaningful in the corners.
>
> Palette: deep crimson, warm amber light, near-black shadows.
>
> No text, no lettering, no logo, no play button, no rounded corners, no drop
> shadow, no border. Avoid glossy vector styling and generic gradients.

---

## Option parallaxe — trois calques

tvOS écarte les calques d'une icône quand elle prend le focus. Pour en profiter,
générer **trois images au même cadrage**, puis les passer à
`Tools/make_icons.py --back … --middle … --front …`.

**Calque arrière** (opaque, plein cadre) :

> Deep charcoal cinematic background with a soft warm crimson glow rising from the
> lower center, subtle vignette, fine film grain. Completely empty — no subject, no
> text, no objects. Landscape 3:2. Rich blacks, no banding.

**Calque médian** (fond noir uni, à détourer) :

> Long trailing jellyfish tentacles transforming into 35 mm film strips with visible
> sprocket holes, drifting downward, faintly backlit in warm amber. Isolated on a
> pure black background, nothing else in frame. Landscape 3:2. Painterly, detailed,
> physical.

**Calque avant** (fond noir uni, à détourer) :

> A single translucent jellyfish bell glowing from within with warm crimson and
> ember light, seen from the side, isolated on a pure black background, nothing else
> in frame. Sharp, detailed, luminous, painterly. Landscape 3:2.

Détourer ensuite le noir des deux derniers calques (Aperçu, Photoshop, ou
`rembg i in.png out.png`).
