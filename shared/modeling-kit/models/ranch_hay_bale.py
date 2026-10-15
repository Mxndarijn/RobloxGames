# ranch_hay_bale: rounded rectangular hay bale (Slime Ranch), ~4 x 2.5 x 2.5 studs, long axis X.
# Soft 3-segment bevels; the bale is cut into pillowy "flakes" along X (bisect + push the
# flake seams in), two twine bands sit in seams, a few loose straw clumps. Front faces -Y.
import math
import bmesh
from lib import *

# Slime Ranch palette (theme table, sRGB 0-255)
BUTTER = PALETTE["ranch_butter"]
CREAM = PALETTE["ranch_cream"]
WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]

HAY_LO = mix(BUTTER, WOOD, 0.1)    # was 0.25: the shadow side went olive-brown in the roblox look
HAY_HI = mix(BUTTER, CREAM, 0.3)
LX, LY, LZ = 4.0, 2.5, 2.5
NF = 8                    # flakes along X
SEAM = 0.09               # how far the flake seams are pushed in
parts = []

bale = box("Bale", (LX, LY, LZ), (0, 0, LZ / 2), BUTTER)
bevel(bale, 0.5, segments=3)
bm = bmesh.new()
bm.from_mesh(bale.data)
fw = (LX - 0.2) / NF
seams = [-LX / 2 + 0.1 + fw * i for i in range(1, NF)]
for x in seams + [s + fw / 2 for s in [seams[0] - fw] + seams]:
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(x, 0, 0), plane_no=(1, 0, 0), dist=1e-4)
for v in bm.verts:   # push seam rings toward the bale's long axis (not the flat bottom)
    if any(abs(v.co.x - s) < 1e-3 for s in seams):
        d = mathutils_vec = (v.co.y, v.co.z - LZ / 2)
        ln = math.hypot(*d) or 1
        v.co.y -= SEAM * d[0] / ln
        if v.co.z > 0.01:
            v.co.z -= SEAM * d[1] / ln
layer = bm.loops.layers.color.get("Col")
for f in bm.faces:   # dark-below/light-above + alternating flake value
    c = f.calc_center_median()
    k = int((c.x + LX / 2 - 0.1) // fw)
    t = max(0.0, min(1.0, c.z / LZ))
    col = shade(mix(HAY_LO, HAY_HI, t), 1.0 if k % 2 else 0.95)
    if abs(f.normal.x) > 0.9:   # cut ends: a touch lighter, so the end view isn't a flat block
        col = mix(col, CREAM, 0.18)
    for lp in f.loops:
        lp[layer] = col
bm.to_mesh(bale.data)
bm.free()
parts.append(bale)

# twine bands in the 2nd and 6th seam: rounded straps hugging the bale
for k, x in enumerate((seams[1], seams[5])):
    b = box(f"Twine{k}", (0.3, LY + 0.06, LZ + 0.06), (x, 0, (LZ + 0.06) / 2), WOOD_D)
    bevel(b, 0.53, segments=3)
    gradient(b, mix(WOOD_D, WOOD, 0.3), WOOD)
    parts.append(b)

# loose straw clumps lying on the top and poking from the seams (no spikes)
CLUMPS = [((-0.9, -0.35, LZ - 0.02), (0, 0, 30), 0),
          ((0.6, 0.45, LZ - 0.02), (0, 10, -20), 1),
          ((1.35, -0.75, LZ - 0.06), (0, -8, 60), 2),
          ]
for p, r, s in CLUMPS:
    c = blob(f"Straw{s}", 0.42, p, HAY_HI, seed=s + 11, subdiv=1, squash=(1.0, 0.45, 0.32), jitter=0.12, rot=r)
    gradient(c, BUTTER, mix(BUTTER, CREAM, 0.5))
    parts.append(c)

finish("ranch_hay_bale", parts)
