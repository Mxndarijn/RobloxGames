#!/usr/bin/env python3
"""Compare a render with a concept image: side-by-side sheet + similarity score.

    python3 compare.py out/tree_oak_sheet.png concept.png                 # whole sheet vs concept
    python3 compare.py out/tree_oak_sheet.png concept.png --tile front    # one view of a contact sheet
    python3 compare.py after.png before.png --tile front --concept-tile front   # two contact sheets
    python3 compare.py a.png b.png --out sheets/cmp.png

Score (0..1, higher = closer), numpy + Pillow only, all on 128x128 downscales:
  ssim   - mean SSIM of greyscale (8x8 box windows): structure/shading
  hist   - colour histogram intersection (RGB 8x8x8 bins): palette match
  edges  - correlation of Sobel edge magnitudes: silhouette/outline match
  score  = 0.4*ssim + 0.3*hist + 0.3*edges  (rough guide only; LOOK at the sheet)
"""
import argparse, json, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

N = 128
TILES = ["front", "side", "back-3/4", "top-3/4"]


def crop_tile(img, name, res=None):
    """Cut one view out of an iterate.py contact sheet (2x2 under a 30 px header)."""
    head, pad = 30, 4
    res = res or (img.width - 3 * pad) // 2
    k = TILES.index(name)
    x = pad + (k % 2) * (res + pad)
    y = head + pad + (k // 2) * (res + pad)
    return img.crop((x, y, x + res, y + res))


def square(img):
    """Pad to square with the edge colour so aspect ratio is kept."""
    w, h = img.size
    s = max(w, h)
    bg = img.getpixel((0, 0))
    out = Image.new("RGB", (s, s), bg)
    out.paste(img, ((s - w) // 2, (s - h) // 2))
    return out


def box(a, k=8):
    """Mean filter (valid region) via integral image."""
    c = np.pad(a, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def ssim(x, y):
    C1, C2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    mx, my = box(x), box(y)
    vx, vy, cxy = box(x * x) - mx * mx, box(y * y) - my * my, box(x * y) - mx * my
    s = ((2 * mx * my + C1) * (2 * cxy + C2)) / ((mx * mx + my * my + C1) * (vx + vy + C2))
    return float(s.mean())


def hist(a, b):
    def h(img):
        q = (np.asarray(img) // 32).reshape(-1, 3)
        idx = q[:, 0] * 64 + q[:, 1] * 8 + q[:, 2]
        v = np.bincount(idx, minlength=512).astype(float)
        return v / v.sum()
    return float(np.minimum(h(a), h(b)).sum())


def sobel(g):
    p = np.pad(g, 1, mode="edge")
    gx = (p[:-2, 2:] + 2 * p[1:-1, 2:] + p[2:, 2:]) - (p[:-2, :-2] + 2 * p[1:-1, :-2] + p[2:, :-2])
    gy = (p[2:, :-2] + 2 * p[2:, 1:-1] + p[2:, 2:]) - (p[:-2, :-2] + 2 * p[:-2, 1:-1] + p[:-2, 2:])
    return np.hypot(gx, gy)


def edges(x, y):
    ex, ey = sobel(x).ravel(), sobel(y).ravel()
    if ex.std() < 1e-6 or ey.std() < 1e-6:
        return 0.0
    return float(max(0.0, np.corrcoef(ex, ey)[0, 1]))


def scores(a, b):
    a, b = square(a).resize((N, N), Image.LANCZOS), square(b).resize((N, N), Image.LANCZOS)
    ga, gb = (np.asarray(i.convert("L"), dtype=float) for i in (a, b))
    s = {"ssim": ssim(ga, gb), "hist": hist(a, b), "edges": edges(ga, gb)}
    s["score"] = 0.4 * max(0.0, s["ssim"]) + 0.3 * s["hist"] + 0.3 * s["edges"]
    return {k: round(v, 3) for k, v in s.items()}


def sheet(a, b, s, path, la, lb, h=384):
    a = a.resize((round(a.width * h / a.height), h))
    b = b.resize((round(b.width * h / b.height), h))
    pad, head = 6, 26
    img = Image.new("RGB", (a.width + b.width + 3 * pad, h + 2 * pad + head + 20), (34, 36, 40))
    d = ImageDraw.Draw(img)
    try:
        f = ImageFont.load_default(size=13)
    except TypeError:
        f = ImageFont.load_default()
    img.paste(a, (pad, head + pad))
    img.paste(b, (2 * pad + a.width, head + pad))
    d.text((pad, 6), la, fill=(235, 235, 235), font=f)
    d.text((2 * pad + a.width, 6), lb, fill=(235, 235, 235), font=f)
    d.text((pad, head + h + pad + 3), f"score {s['score']:.3f}   ssim {s['ssim']:.3f}   hist {s['hist']:.3f}   edges {s['edges']:.3f}",
           fill=(255, 210, 120), font=f)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    img.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("render")
    ap.add_argument("concept")
    ap.add_argument("--tile", choices=TILES, help="compare only this view of an iterate.py contact sheet")
    ap.add_argument("--concept-tile", choices=TILES, help="also crop this view from the concept (when it is a contact sheet too)")
    ap.add_argument("--out", help="side-by-side PNG (default: <render>_vs_<concept>.png next to render)")
    a = ap.parse_args()
    r = Image.open(a.render).convert("RGB")
    c = Image.open(a.concept).convert("RGB")
    if a.tile:
        r = crop_tile(r, a.tile)
    if a.concept_tile:
        c = crop_tile(c, a.concept_tile)
    s = scores(r, c)
    out = a.out or os.path.join(os.path.dirname(os.path.abspath(a.render)),
                                f"{os.path.splitext(os.path.basename(a.render))[0]}_vs_{os.path.splitext(os.path.basename(a.concept))[0]}.png")
    sheet(r, c, s, out, os.path.basename(a.render) + (f" [{a.tile}]" if a.tile else ""), os.path.basename(a.concept) + (f" [{a.concept_tile}]" if a.concept_tile else ""))
    print(json.dumps({**s, "sheet": out}))


if __name__ == "__main__":
    sys.exit(main())
