#!/usr/bin/env python3
"""Soft ground ColorMaps for the Slime Ranch terrain (bugs #13-15): out/ground/{Grass,Ground,Sand}.png, 512x512, seamless.

    python3 tools/ground/ground_textures.py            # generate
    python3 tools/ground/ground_textures.py --upload   # dry-run upload (add --go to really send; reuses tools/icons/upload_icons.py)

Terrain multiplies a material's ColorMap with its Terrain material colour. The tint is the LIGHT colour of
each palette (GroundTerrain.COLORS), the map goes from DARK/LIGHT up to white, so tint x map spans the
concept's A..B colours (concept/render_concept.py). Grass: low-contrast pastel blotches + faint tufts speckle.
Dirt: warm blotches + small pebbles. Sand: very soft ripples. Records out/ground/ground_uploaded.json
({name: {assetId (Decal), imageId}}), then paste imageId into default.project.json MaterialService.
"""
import argparse, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(KIT, "out", "ground")
N = 512
LIGHT = {"Grass": (146, 206, 84), "Ground": (204, 152, 100), "Sand": (246, 220, 170)}
DARK = {"Grass": (92, 182, 70), "Ground": (178, 124, 80), "Sand": (236, 204, 146)}
STRENGTH = {"Grass": 0.65, "Ground": 1.0, "Sand": 1.0}  # how much of the dark colour the map may reach (snow keeps its tint)


def fnoise(rng, cells):
    """Seamless value noise: smooth-interpolated random lattice of `cells` cells wrapping at the edge."""
    g = rng.random((cells, cells)).astype(np.float32)
    big = np.tile(g, (3, 3))
    im = Image.fromarray(big).resize((cells * 3 * (N // cells), cells * 3 * (N // cells)), Image.BICUBIC)
    a = np.asarray(im, dtype=np.float32)
    s = N
    return np.clip(a[s:2 * s, s:2 * s], 0, 1)


def pebbles(rng, count, rmin, rmax):
    """Seamless soft round dots in [-1, 1] (dark -, light +)."""
    img = np.zeros((N, N), np.float32)
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    for _ in range(count):
        cx, cy = rng.random() * N, rng.random() * N
        r = rmin + rng.random() * (rmax - rmin)
        sign = -1 if rng.random() < 0.6 else 1
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                d = np.hypot(xx - cx - ox, yy - cy - oy)
                if d.min() > r + 2:
                    continue
                img += sign * np.clip(1 - d / r, 0, 1) * (0.5 + 0.5 * rng.random())
    return np.clip(img, -1, 1)


def field(name):
    rng = np.random.default_rng({"Grass": 11, "Ground": 22, "Sand": 33}[name])
    n = 0.5 * fnoise(rng, 4) + 0.3 * fnoise(rng, 12) + 0.2 * fnoise(rng, 32)  # 0..1 blotches
    n = np.clip((n - 0.5) * 1.8 + 0.5, 0, 1)
    if name == "Grass":
        n = n * 0.85 + 0.15 * fnoise(rng, 96)
    if name == "Ground":
        n = np.clip(n * 0.8 + 0.7 * pebbles(rng, 220, 3.0, 8.0) + 0.1, 0, 1)
    if name == "Sand":
        n = 0.35 + 0.3 * n + 0.1 * fnoise(rng, 128)
    return np.clip(n, 0, 1)


def build(name):
    t = field(name)  # 0 = dark end, 1 = light end
    lo = np.array([d / l for d, l in zip(DARK[name], LIGHT[name])], np.float32)
    lo = 1 - (1 - lo) * STRENGTH[name]
    rgb = lo[None, None, :] + (1 - lo)[None, None, :] * t[:, :, None]
    return Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload", action="store_true")
    ap.add_argument("--go", action="store_true")
    a, rest = ap.parse_known_args()
    os.makedirs(OUT, exist_ok=True)
    for name in LIGHT:
        build(name).save(os.path.join(OUT, name + ".png"))
        print("wrote", name + ".png")
    if a.upload:
        sys.path.insert(0, os.path.join(KIT, "tools", "icons"))
        import upload_icons as UI
        UI.ICONS = OUT
        UI.RECORD = os.path.join(OUT, "ground_uploaded.json")
        UI.request_for = lambda i, u: {"assetType": "Decal", "displayName": f"Slime ground {i}",
                                       "description": f"{i}: soft terrain ColorMap (own work, tools/ground)",
                                       "creationContext": {"creator": {"userId": u}}}
        sys.argv = [sys.argv[0]] + (["--go"] if a.go else []) + rest
        UI.main()


if __name__ == "__main__":
    main()
