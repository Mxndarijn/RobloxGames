# tree_pine: stylised fir (replaces v17 tree_pine, ~7.7 x 12.8 x 8.1 studs; trunk r 0.55 at the origin).
import math, random
import bmesh
from mathutils import Vector
from lib import *

R = random.Random(5)
BARK, BARK_D = PALETTE["bark"], PALETTE["bark_dark"]
NEEDLE_D, NEEDLE, NEEDLE_L = rgb(50, 118, 80), rgb(62, 148, 88), rgb(110, 190, 104)  # r04: +20% dark value for the game sun
parts = []


def tier(name, r, h, z, tips=9, droop=0.45, twist=0.0, dark=NEEDLE_D, light=NEEDLE_L):
    """Cone skirt with `tips` branch points: the rim alternates long drooping tips and short
    notches, so the silhouette is a fir, not a party hat. Closed underside (cone inwards)."""
    bm = bmesh.new()
    n = tips * 2
    rim = []
    for k in range(n):
        a = k * math.tau / n + twist
        tip = k % 2 == 0
        rr = r * (1.0 if tip else 0.62) * R.uniform(0.93, 1.05)
        zz = z - (droop if tip else 0.0)
        rim.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, zz)))
    apex = bm.verts.new((R.uniform(-0.05, 0.05), R.uniform(-0.05, 0.05), z + h))
    under = bm.verts.new((0, 0, z + h * 0.18))  # shallow inverted cone underneath
    for k in range(n):
        a, b = rim[k], rim[(k + 1) % n]
        bm.faces.new((a, b, apex))
        bm.faces.new((b, a, under))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # paint per face corner: tips light, notches/core dark, underside darkest (fake AO)
    layer = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        below = f.normal.z < 0
        for lp in f.loops:
            v = lp.vert
            d = math.hypot(v.co.x, v.co.y) / r
            if below:
                c = shade(dark, 0.8)
            elif v is apex:
                c = mix(dark, light, 0.75)
            else:
                c = mix(dark, light, max(0.0, min(1.0, (d - 0.55) / 0.45)))
            lp[layer] = c
    return obj_from_bm(name, bm, smooth=False)


H = 12.8
parts.append(tube("Trunk", [(0, 0, -0.1), (0, 0, 0.6), (0, 0, 3.5), (0, 0, 7.0)], [0.85, 0.6, 0.5, 0.35], BARK, segs=7, seed=R))
gradient(parts[-1], BARK_D, shade(BARK, 1.1), z0=0, z1=4)
for k in range(4):  # root flare
    a = k * math.tau / 4 + 0.4
    c, s = math.cos(a), math.sin(a)
    parts.append(tube(f"Root{k}", [(c * 0.3, s * 0.3, 0.6), (c * 0.9, s * 0.9, 0.2), (c * 1.4, s * 1.4, -0.05)], [0.3, 0.2, 0.08], BARK_D, segs=5, seed=R))
# tiers: bottom wide, each smaller, overlapping; alternating twist so tips interleave
TIERS = [(4.05, 3.3, 3.3), (3.35, 3.1, 5.1), (2.65, 2.9, 6.85), (1.95, 2.7, 8.55), (1.25, 2.55, 10.25)]
for i, (r, h, z) in enumerate(TIERS):
    t = i / (len(TIERS) - 1)
    parts.append(tier(f"Tier{i}", r, h, z, tips=8 - i // 2, droop=0.55 - 0.08 * i, twist=i * 0.33,
                      dark=mix(NEEDLE_D, NEEDLE, t * 0.5), light=mix(NEEDLE, NEEDLE_L, 0.4 + 0.6 * t)))
print("tree_pine: lowest needles at", round(min(v.co.z for v in parts[-5].data.vertices), 2))
finish("tree_pine", parts)
