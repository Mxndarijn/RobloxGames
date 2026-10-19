#!/usr/bin/env python3
"""Colour map PNG per pet mount: the vertex colours of out/pet_mount_<name>.obj drawn flat (no light, no shadow) from
a 3/4 view and from the top, plus the palette that dominates the mesh. The mounts have no UV texture: Roblox shows
the "Col" vertex colours, so this is the 'texture' to review.

    python3 tools/pet_mounts_colormap.py --out renders/pet_mounts [--copy sheets] [--suffix _v2]
"""
import argparse, math, os, shutil
import numpy as np
from PIL import Image, ImageDraw

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = ["storm_cloud", "rainbow_cloud", "sunset_cloud", "ice_cloud", "flame_cloud", "leaf", "bubble", "magic_carpet", "ufo", "lily_pad",
         "star_cushion", "crescent_moon", "mushroom", "pancakes", "jelly", "hoverboard", "clam_shell", "royal_cushion"]


def load_obj(path):
    v, c, f = [], [], []
    for line in open(path):
        t = line.split()
        if not t:
            continue
        if t[0] == "v":
            v.append([float(x) for x in t[1:4]])
            c.append([float(x) for x in t[4:7]] if len(t) >= 7 else [0.5] * 3)
        elif t[0] == "f":
            f.append([int(x.split("/")[0]) - 1 for x in t[1:]])
    tri = [(p[0], p[i], p[i + 1]) for p in f for i in range(1, len(p) - 1)]
    return np.array(v), np.array(c), np.array(tri)


def raster(v, c, tri, yaw, pitch, size, bg):
    """flat-colour z-buffered orthographic render (obj axes: Y up, front = +Z)."""
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    x = v[:, 0] * cy + v[:, 2] * sy
    z = -v[:, 0] * sy + v[:, 2] * cy
    y = v[:, 1] * cp - z * sp
    d = v[:, 1] * sp + z * cp  # depth towards the camera: bigger = nearer
    lo, hi = np.array([x.min(), y.min()]), np.array([x.max(), y.max()])
    k = (size * 0.9) / max(hi - lo)
    px = (x - lo[0]) * k + size * 0.05 + (size * 0.9 - (hi[0] - lo[0]) * k) / 2
    py = size - ((y - lo[1]) * k + size * 0.05 + (size * 0.9 - (hi[1] - lo[1]) * k) / 2)
    img = np.zeros((size, size, 3)) + np.array(bg) / 255.0
    zb = np.full((size, size), -1e9)
    for a, b, cc in tri:
        xs, ys, ds = px[[a, b, cc]], py[[a, b, cc]], d[[a, b, cc]]
        x0, x1 = int(max(xs.min(), 0)), int(min(xs.max() + 1, size - 1))
        y0, y1 = int(max(ys.min(), 0)), int(min(ys.max() + 1, size - 1))
        if x1 <= x0 or y1 <= y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(den) < 1e-9:
            continue
        w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
        w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den
        w2 = 1 - w0 - w1
        m = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not m.any():
            continue
        dd = w0 * ds[0] + w1 * ds[1] + w2 * ds[2]
        col = w0[..., None] * c[a] + w1[..., None] * c[b] + w2[..., None] * c[cc]
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        upd = m & (dd > sub)
        sub[upd] = dd[upd]
        img[y0:y1 + 1, x0:x1 + 1][upd] = col[upd]
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))


def palette(v, c, tri, n=8):
    a = v[tri]
    area = np.linalg.norm(np.cross(a[:, 1] - a[:, 0], a[:, 2] - a[:, 0]), axis=1) / 2
    col = c[tri].mean(axis=1)
    q = np.round(col * 7).astype(int)  # coarse buckets so gradients collapse into a few swatches
    acc = {}
    for qi, ar, co in zip(map(tuple, q), area, col):
        s = acc.setdefault(qi, [0.0, np.zeros(3)])
        s[0] += ar
        s[1] += co * ar
    top = sorted(acc.values(), key=lambda s: -s[0])[:n]
    tot = sum(s[0] for s in acc.values())
    return [(tuple(int(round(x * 255)) for x in s[1] / s[0]), s[0] / tot) for s in top]


def make(name, out, suffix="", size=520):
    v, c, tri = load_obj(os.path.join(KIT, "out", f"pet_mount_{name}.obj"))
    bg = (236, 238, 244)
    a = raster(v, c, tri, math.radians(35), math.radians(32), size, bg)
    b = raster(v, c, tri, 0.0, math.radians(90), size, bg)
    im = Image.new("RGB", (size * 2, size + 110), bg)
    im.paste(a, (0, 0))
    im.paste(b, (size, 0))
    d = ImageDraw.Draw(im)
    d.text((8, 6), f"pet_mount_{name}: vertex colours, unlit (3/4, top)", fill=(40, 40, 50))
    pal = palette(v, c, tri)
    w = (size * 2 - 20) // len(pal)
    for i, (rgb, share) in enumerate(pal):
        x = 10 + i * w
        d.rectangle([x, size + 12, x + w - 8, size + 70], fill=rgb, outline=(60, 60, 70))
        d.text((x + 2, size + 76), "#%02x%02x%02x  %d%%" % (*rgb, round(share * 100)), fill=(40, 40, 50))
    path = os.path.join(out, f"{name}_colormap{suffix}.png")
    im.save(path)
    return path


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--only", default="")
    p.add_argument("--suffix", default="", help="appended to the PNG names, e.g. _v2")
    p.add_argument("--copy", default="", help="also copy the PNGs here (relative to the kit)")
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for n in a.only.split(",") if a.only else NAMES:
        if os.path.exists(os.path.join(KIT, "out", f"pet_mount_{n}.obj")):
            path = make(n, a.out, a.suffix)
            print("wrote", path)
            if a.copy:
                os.makedirs(os.path.join(KIT, a.copy), exist_ok=True)
                shutil.copy(path, os.path.join(KIT, a.copy, f"pet_mount_{n}_colormap.png"))


if __name__ == "__main__":
    main()
