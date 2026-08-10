#!/usr/bin/env python3
"""Construit le catalogue d'icônes tvOS de Jellyflix.

tvOS n'utilise pas une image plate mais une pile de calques que le système écarte
en parallaxe quand l'icône prend le focus. Deux règles se paient cher si on les
ignore :

* l'ordre des calques doit être **déclaré** dans le `Contents.json` de la pile —
  sans quoi Xcode les classe par nom de fichier et « Middle » finit derrière ;
* le calque le plus profond doit être **opaque et remplir exactement** le cadre,
  à chaque échelle demandée.

Usage :

    python3 Tools/make_icons.py                       # visuel de remplacement
    python3 Tools/make_icons.py --source icon.png     # une image, sans parallaxe
    python3 Tools/make_icons.py --back b.png --middle m.png --front f.png

Les images fournies sont recadrées au centre au format attendu. Pour `--middle`
et `--front`, la transparence est conservée : ce sont les calques qui flottent.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "Apps/tvOS/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets"

RED = (229, 19, 33)
RED_DEEP = (122, 8, 20)
INK = (11, 11, 13)

# (nom du dossier, taille de référence en points, échelles à produire)
ICON_STACKS = [
    ("App Icon.imagestack", (400, 240), [1, 2]),
    ("App Icon - App Store.imagestack", (1280, 768), [1]),
]

TOP_SHELF = [
    ("Top Shelf Image.imageset", (1920, 720), "top-shelf"),
    ("Top Shelf Image Wide.imageset", (2320, 720), "top-shelf-wide"),
]

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Futura.ttc",
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/SFNS.ttf",
]


# MARK: - Utilitaires

def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size, index=0)
            except OSError:
                continue
    return ImageFont.load_default()


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def fit_center(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Recadre au centre en remplissant le cadre, sans déformer."""
    target_ratio = size[0] / size[1]
    width, height = image.size
    ratio = width / height

    if ratio > target_ratio:
        new_width = int(height * target_ratio)
        box = ((width - new_width) // 2, 0, (width + new_width) // 2, height)
    else:
        new_height = int(width / target_ratio)
        box = (0, (height - new_height) // 2, width, (height + new_height) // 2)

    return image.crop(box).resize(size, Image.LANCZOS)


def flatten_on_black(image: Image.Image) -> Image.Image:
    """Le calque de fond doit être opaque : on aplatit sur du noir."""
    base = Image.new("RGBA", image.size, INK + (255,))
    base.alpha_composite(image)
    return base


# MARK: - Visuel de remplacement

def vertical_gradient(size: tuple[int, int], top: tuple, bottom: tuple) -> Image.Image:
    width, height = size
    image = Image.new("RGBA", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(height - 1, 1)
        draw.line(
            [(0, y), (width, y)],
            fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,),
        )
    return image


def radial_glow(size: tuple[int, int], center: tuple[float, float], radius: float, color: tuple) -> Image.Image:
    """Halo diffus, dessiné en réduction puis flouté — bien plus rapide qu'un
    calcul par pixel sur une image 4K, et plus doux."""
    width, height = size
    scale = 8
    small = Image.new("RGBA", (max(width // scale, 1), max(height // scale, 1)), (0, 0, 0, 0))
    draw = ImageDraw.Draw(small)
    cx, cy, r = center[0] / scale, center[1] / scale, radius / scale
    steps = 26
    for i in range(steps, 0, -1):
        t = i / steps
        draw.ellipse(
            [cx - r * t, cy - r * t, cx + r * t, cy + r * t],
            fill=color + (int(150 * (1 - t) ** 1.7),),
        )
    return small.filter(ImageFilter.GaussianBlur(radius=6)).resize((width, height), Image.LANCZOS)


def play_glyph(size: tuple[int, int], scale: float = 1.0, center_y: float = 0.5) -> Image.Image:
    width, height = size
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    cx, cy = width / 2, height * center_y
    disc = min(width, height) * 0.34 * scale

    draw.ellipse([cx - disc, cy - disc, cx + disc, cy + disc], fill=RED + (255,))
    ring = disc * 1.16
    draw.ellipse(
        [cx - ring, cy - ring, cx + ring, cy + ring],
        outline=(255, 255, 255, 60),
        width=max(2, int(disc * 0.05)),
    )

    side = disc * 0.82
    offset = side * 0.12
    draw.polygon(
        [
            (cx - side * 0.45 + offset, cy - side * math.sin(math.pi / 3) * 0.92),
            (cx - side * 0.45 + offset, cy + side * math.sin(math.pi / 3) * 0.92),
            (cx + side * 0.78 + offset, cy),
        ],
        fill=(255, 255, 255, 255),
    )
    return image


def wordmark(size, text="JELLYFLIX", baseline=0.74, size_ratio=0.15) -> Image.Image:
    width, height = size
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    font = load_font(max(int(height * size_ratio), 12))
    box = draw.textbbox((0, 0), text, font=font)
    draw.text(
        ((width - (box[2] - box[0])) / 2 - box[0], height * baseline),
        text,
        font=font,
        fill=(255, 255, 255, 240),
    )
    return image


def placeholder_layers(size: tuple[int, int]) -> dict[str, Image.Image]:
    width, height = size
    front = play_glyph(size, scale=0.78, center_y=0.40)
    front.alpha_composite(wordmark(size))
    return {
        "Back": vertical_gradient(size, RED_DEEP, INK),
        "Middle": radial_glow(size, (width * 0.5, height * 0.42), min(width, height) * 0.95, RED),
        "Front": front,
    }


# MARK: - Écriture du catalogue

def build_layer(stack: Path, name: str, renders: dict[int, Image.Image], opaque: bool) -> None:
    layer = stack / f"{name}.imagestacklayer"
    write_json(layer / "Contents.json", {"info": {"author": "xcode", "version": 1}})

    content = layer / "Content.imageset"
    content.mkdir(parents=True, exist_ok=True)

    images = []
    for scale, render in sorted(renders.items()):
        filename = f"{name.lower()}{'' if scale == 1 else f'@{scale}x'}.png"
        (flatten_on_black(render) if opaque else render).save(content / filename)
        images.append({"idiom": "tv", "filename": filename, "scale": f"{scale}x"})

    write_json(content / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})


def build_stack(path: Path, size: tuple[int, int], scales: list[int], sources: dict[str, Image.Image] | None) -> None:
    if path.exists():
        shutil.rmtree(path)

    # L'ordre est significatif : premier = devant, dernier = derrière.
    order = ["Front", "Middle", "Back"]
    write_json(
        path / "Contents.json",
        {
            "info": {"author": "xcode", "version": 1},
            "layers": [{"filename": f"{name}.imagestacklayer"} for name in order],
        },
    )

    for name in order:
        renders: dict[int, Image.Image] = {}
        for scale in scales:
            scaled = (size[0] * scale, size[1] * scale)
            if sources is None:
                renders[scale] = placeholder_layers(scaled)[name]
            elif name in sources:
                renders[scale] = fit_center(sources[name], scaled)
            else:
                renders[scale] = Image.new("RGBA", scaled, (0, 0, 0, 0))

        # Seul le calque du fond doit être opaque et plein cadre.
        build_layer(path, name, renders, opaque=(name == "Back"))


def build_top_shelf(path: Path, size: tuple[int, int], stem: str, source: Image.Image | None) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)

    images = []
    for scale in (1, 2):
        scaled = (size[0] * scale, size[1] * scale)
        if source is not None:
            render = flatten_on_black(fit_center(source, scaled))
        else:
            width, height = scaled
            render = vertical_gradient(scaled, RED_DEEP, INK)
            render.alpha_composite(radial_glow(scaled, (width * 0.28, height * 0.5), height * 1.5, RED))
            render.alpha_composite(play_glyph((height, height), scale=0.5), (int(width * 0.05), 0))
            render.alpha_composite(
                wordmark((int(width * 0.42), height), baseline=0.42, size_ratio=0.20),
                (int(width * 0.17), 0),
            )

        filename = f"{stem}{'' if scale == 1 else '@2x'}.png"
        render.save(path / filename)
        images.append({"idiom": "tv", "filename": filename, "scale": f"{scale}x"})

    write_json(path / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Image unique, utilisée comme fond (pas de parallaxe)")
    parser.add_argument("--back", type=Path, help="Calque de fond (opaque, plein cadre)")
    parser.add_argument("--middle", type=Path, help="Calque médian (transparence conservée)")
    parser.add_argument("--front", type=Path, help="Calque avant (transparence conservée)")
    parser.add_argument("--top-shelf", type=Path, help="Bandeau de l'étagère du haut")
    args = parser.parse_args()

    sources: dict[str, Image.Image] | None = None
    if args.source:
        sources = {"Back": Image.open(args.source).convert("RGBA")}
    elif args.back or args.middle or args.front:
        sources = {}
        for name, path in (("Back", args.back), ("Middle", args.middle), ("Front", args.front)):
            if path:
                sources[name] = Image.open(path).convert("RGBA")
        if "Back" not in sources:
            parser.error("Le calque de fond (--back) est obligatoire : tvOS le veut opaque et plein cadre.")

    top_shelf_source = None
    if args.top_shelf:
        top_shelf_source = Image.open(args.top_shelf).convert("RGBA")
    elif sources:
        top_shelf_source = sources["Back"]

    BRAND.mkdir(parents=True, exist_ok=True)
    write_json(
        BRAND / "Contents.json",
        {
            "assets": [
                {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
                {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
                {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
                {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )

    for name, size, scales in ICON_STACKS:
        build_stack(BRAND / name, size, scales, sources)

    for name, size, stem in TOP_SHELF:
        build_top_shelf(BRAND / name, size, stem, top_shelf_source)

    print(f"Catalogue écrit dans {BRAND}")
    if sources is None:
        print("Visuel de remplacement utilisé — voir Design/icon-prompt.md pour le remplacer.")


if __name__ == "__main__":
    main()
