#!/usr/bin/env python3
"""Curate reviewed empty-state Android screenshots for the GitHub landing page.

Usage: python scripts/render_readme_media.py <audited-screens> [docs/media]
Inputs must be independently checked for zero personal data and OS overlays.
The published first gallery uses the authorized QA staging phone, not unreviewed
emulator output. Pillow required. Screens are never invented or modified.
"""
from __future__ import annotations
from pathlib import Path
import argparse
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageStat

NAMES = ("today-dark", "trends-dark", "settings-dark")
SIZE = (1680, 770)
DARK = (17, 22, 36)
LAVENDER = (201, 183, 242)
WHITE = (250, 249, 252)


def source_image(path: Path) -> Image.Image:
    if not path.is_file():
        raise RuntimeError(f"Missing verified screenshot: {path}")
    src = Image.open(path).convert("RGB")
    w, h = src.size
    if not 700 <= w <= 1500 or not 1400 <= h <= 3300:
        raise RuntimeError(f"Unexpected screenshot dimensions: {path.name} {src.size}")
    # Reject black/single-color/screensaver frames, not actual UI.
    if max(ImageStat.Stat(src.resize((60, 90))).stddev) < 14:
        raise RuntimeError(f"Blank or near-monochrome screenshot: {path.name}")
    # Do not publish emulator/device status bar or gesture bar.
    return src.crop((0, 110, w, h - 65))


def text(draw, xy, value, font, fill, spacing=14):
    draw.multiline_text(xy, value, font=font, fill=fill, spacing=spacing)


def phone(image: Image.Image, width: int, border=(76, 76, 104)) -> Image.Image:
    h = int(image.height * width / image.width)
    shot = image.resize((width, h), Image.Resampling.LANCZOS)
    gap = 9
    result = Image.new("RGBA", (width + gap * 2, h + gap * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(result)
    draw.rounded_rectangle((0, 0, result.width - 1, result.height - 1),
                           radius=38, fill=border)
    mask = Image.new("L", (width, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width, h), radius=29, fill=255)
    result.paste(shot.convert("RGBA"), (gap, gap), mask)
    return result


def compose(screens: dict[str, Image.Image], font_path: Path) -> Image.Image:
    w, h = SIZE
    hero = Image.new("RGB", SIZE)
    pix = hero.load()
    for y in range(h):
        for x in range(w):
            k = x / w * .12 + y / h * .06
            pix[x, y] = (int(17 + 27 * k), int(22 + 28 * k), int(36 + 46 * k))
    blur = Image.new("RGBA", SIZE)
    rings = ImageDraw.Draw(blur)
    rings.ellipse((860, -380, 1780, 580), fill=(147, 127, 215, 43))
    rings.ellipse((1180, 260, 1790, 1080), fill=(155, 188, 176, 28))
    hero = Image.alpha_composite(hero.convert("RGBA"), blur.filter(ImageFilter.GaussianBlur(88)))

    draw = ImageDraw.Draw(hero)
    regular = ImageFont.truetype(str(font_path), 30)
    meta = ImageFont.truetype(str(font_path), 23)
    header = ImageFont.truetype(str(font_path), 94)
    claim = ImageFont.truetype(str(font_path), 41)
    # simple, reproducible moon mark (not an illustrative screenshot)
    draw.rounded_rectangle((80, 81, 154, 155), radius=25, fill=(57, 62, 91, 255))
    draw.ellipse((101, 96, 133, 136), fill=(217, 208, 250, 255))
    draw.ellipse((116, 89, 142, 126), fill=(57, 62, 91, 255))
    text(draw, (175, 92), "LITTLE REST  /  EARLY ACCESS", meta, LAVENDER)
    text(draw, (78, 240), "One quiet tap.", header, WHITE)
    text(draw, (78, 358), "A clearer night.", claim, (211, 199, 242))
    text(draw, (80, 444), "Sleep tracking, stripped back to what matters.\n"
                        "A gentle timeline. Private by default.\n"
                        "Built to feel calm at 3 a.m.", regular, (203, 211, 225), spacing=18)
    draw.rounded_rectangle((79, 655, 648, 708), radius=25, fill=(51, 61, 83), outline=(86, 91, 115), width=2)
    text(draw, (106, 664), "FLUTTER    •    ANDROID QA    •    iOS SOURCE", meta, WHITE)
    # Screenshots are genuine app pixels, only resized/cropped and framed.
    layer = Image.new("RGBA", SIZE)
    for name, x, y, width in (("trends-dark", 1320, 80, 306), ("today-dark", 945, 20, 331)):
        ph = phone(screens[name], width)
        shadow = Image.new("RGBA", SIZE)
        mask = Image.new("L", ph.size)
        ImageDraw.Draw(mask).rounded_rectangle((4, 4, ph.width - 4, ph.height - 4),
                                               radius=40, fill=180)
        shadow.paste((0, 0, 0, 155), (x + 19, y + 22, x + 19 + ph.width, y + 22 + ph.height), mask)
        layer = Image.alpha_composite(layer, shadow.filter(ImageFilter.GaussianBlur(25)))
        layer.alpha_composite(ph, (x, y))
    return Image.alpha_composite(hero, layer).convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", nargs="?", type=Path, default=Path("docs/media"))
    args = parser.parse_args()
    font = Path(__file__).resolve().parents[1] / "assets/fonts/Inter-Variable.ttf"
    if not font.is_file():
        raise RuntimeError("Bundled font unavailable; cannot produce consistent hero artwork.")
    screens = {name: source_image(args.source / (name + ".png")) for name in NAMES}
    args.output.mkdir(parents=True, exist_ok=True)
    for name, img in screens.items():
        img.thumbnail((630, 1550), Image.Resampling.LANCZOS)
        img.save(args.output / (name + ".png"), optimize=True)
    hero = compose(screens, font)
    hero.save(args.output / "little-rest-hero.png", optimize=True)
    print("Rendered genuine Android screenshots and designed hero:", args.output)
    for file in sorted(args.output.glob("*.png")):
        print(file.name, file.stat().st_size)


if __name__ == "__main__":
    main()
