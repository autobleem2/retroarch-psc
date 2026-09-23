#!/usr/bin/env python3
"""Autobleem2.png - the XMB wallpaper, from the ab2 theme's launcher background.

    make_wallpaper.py <AutoBleem2 checkout>/payload/themes/ab2/images/AB-EvoBack.jpg [Autobleem2.png]

XMB puts its icon row along the top and the item list down the left, so the wallpaper keeps the
circuit-board texture there and moves the AutoBleem 2 logo to the bottom right, where only a game's
thumbnail ever sits (RetroBoot's wallpaper made the same choice). AB-EvoBack.jpg has the logo bottom left
and the launcher's footer bar bottom right: the whole bottom band is replaced by a vertical reflection of
the rows above it (continuous at the seam - it reads as a lens shape), the two reflected labels that came
out upside down are softened into a glow, and the logo block is pasted back at the right with feathered
edges. RetroArch dims it with menu_wallpaper_opacity 0.6.
"""
import sys
from PIL import Image, ImageOps, ImageDraw, ImageFilter

LOGO = (18, 455, 462, 708)   # the logo block in AB-EvoBack.jpg (x0, y0, x1, y1)
SEAM = 448                   # the row the bottom band is reflected about
LABELS = ((120, 452, 350, 520), (220, 505, 600, 560))   # reflected text, softened


def feather(size, margin):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rectangle((margin, margin, size[0] - margin, size[1] - margin), fill=255)
    return m.filter(ImageFilter.GaussianBlur(margin * 0.7))


def main():
    src = Image.open(sys.argv[1]).convert("RGB")
    out = sys.argv[2] if len(sys.argv) > 2 else "Autobleem2.png"
    w, h = src.size
    logo = src.crop(LOGO)
    bg = src.copy()
    band = h - SEAM
    bg.paste(ImageOps.flip(bg.crop((0, SEAM - band, w, SEAM))), (0, SEAM))
    for box in LABELS:
        reg = bg.crop(box).filter(ImageFilter.GaussianBlur(9))
        bg.paste(reg, box[:2], feather(reg.size, 10))
    bg.paste(logo, (w - LOGO[2] + 2, LOGO[1]), feather(logo.size, 26))
    bg.save(out)
    print("wrote %s (%dx%d)" % (out, w, h))


if __name__ == "__main__":
    main()
