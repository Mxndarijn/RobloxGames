#!/usr/bin/env python3
"""Outline post pass (system python + PIL): raw transparent renders -> out/icons/<id>.png.
A thin soft dark rim around the alpha silhouette, a slight saturation lift, 512x512 RGBA."""
import os, sys
from PIL import Image, ImageEnhance, ImageFilter

RIM = (38, 26, 52)
WIDTH = 6  # px at 512


def process(src, dst):
    im = Image.open(src).convert("RGBA")
    r, g, b, a = im.split()
    rgb = Image.merge("RGB", (r, g, b))
    rgb = ImageEnhance.Color(rgb).enhance(1.12)
    a_hard = a.point(lambda v: 255 if v > 24 else 0)
    k = WIDTH * 2 + 1
    dil = a_hard.filter(ImageFilter.MaxFilter(3))
    for _ in range(WIDTH // 1 - 1):
        dil = dil.filter(ImageFilter.MaxFilter(3))
    dil = dil.filter(ImageFilter.GaussianBlur(1.1))
    rim_a = dil.point(lambda v: int(v * 0.92))
    rim = Image.new("RGBA", im.size, RIM + (0,))
    rim.putalpha(rim_a)
    subject = Image.merge("RGBA", (*rgb.split(), a))
    out = Image.alpha_composite(rim, subject)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out.save(dst)


if __name__ == "__main__":
    raw, out, ids = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
    for i in ids:
        process(os.path.join(raw, i + ".png"), os.path.join(out, i + ".png"))
    print(f"outlined {len(ids)} -> {out}")
