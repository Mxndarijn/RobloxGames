#!/usr/bin/env python3
"""Contact sheet of the rendered icons: id label, the 512 icon (shown at 180 px) on a checkerboard, plus its 36 px version on a dark tile.
    python3 contact_sheet.py <icons dir> <out.png> [--cols 8]"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

CELL, SMALL = 200, 36


def checker(w, h, s=12):
    im = Image.new("RGB", (w, h), (200, 200, 205))
    d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range(0, w, s):
            if (x // s + y // s) % 2:
                d.rectangle([x, y, x + s - 1, y + s - 1], fill=(150, 152, 160))
    return im


def _font(size):
    for name in ("DejaVuSans.ttf", "arial.ttf"):  # DejaVu on Linux, Arial on Windows
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main():
    src, out = sys.argv[1], sys.argv[2]
    cols = int(sys.argv[sys.argv.index("--cols") + 1]) if "--cols" in sys.argv else 8
    files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    order = os.environ.get("ICON_ORDER")
    if order:
        files = [f"{i}.png" for i in order.split(",") if f"{i}.png" in files]
    font = _font(12)
    rows = (len(files) + cols - 1) // cols
    W, H = cols * CELL, rows * (CELL + 18)
    sheet = Image.new("RGB", (W, H), (60, 62, 70))
    d = ImageDraw.Draw(sheet)
    for n, f in enumerate(files):
        x, y = (n % cols) * CELL, (n // cols) * (CELL + 18)
        im = Image.open(os.path.join(src, f)).convert("RGBA")
        big = im.resize((CELL - 4, CELL - 4), Image.LANCZOS)
        bg = checker(CELL - 4, CELL - 4)
        bg.paste(big, (0, 0), big)
        sheet.paste(bg, (x + 2, y + 2))
        tile = Image.new("RGB", (SMALL + 8, SMALL + 8), (36, 40, 56))
        sm = im.resize((SMALL, SMALL), Image.LANCZOS)
        tile.paste(sm, (4, 4), sm)
        sheet.paste(tile, (x + CELL - SMALL - 12, y + CELL - SMALL - 12))
        d.text((x + 4, y + CELL + 2), f[:-4], fill=(235, 235, 235), font=font)
    sheet.save(out)
    print("sheet", out, sheet.size)


main()
