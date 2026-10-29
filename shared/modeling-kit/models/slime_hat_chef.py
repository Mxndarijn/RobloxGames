# slime_hat_chef: paid slime hat cosmetic, a white puffy chef toque.
# One closed lathe: hollow dome underside, a straight band with a red stripe, then a puffy pleated crown
# (radius modulated by angle, so the pleats are real geometry) with a domed, lumpy top.
# Origin bottom centre, Z up, front -Y, band ~1.8 wide, crown ~2.2. HAT_PREVIEW=1 adds a stand-in slime.
import math
import os
from models._pvp_fun import *

W_HI = WHITE
W_LO = mix(WHITE, LILAC, 0.38)      # cool shadow for the white (no grey/cream)
STRIPE = mix(RED, PINK, 0.25)
SEGS, PLEATS = 24, 6

# (r, z, pleat amount, band?)  bottom -> top
PROF = [
    (0.50, 0.10, 0.0, "under"), (0.82, 0.02, 0.0, "under"), (0.88, 0.0, 0.0, "band"),
    (0.90, 0.08, 0.0, "band"), (0.91, 0.24, 0.0, "stripe"), (0.91, 0.36, 0.0, "band"),
    (0.92, 0.54, 0.0, "band"), (0.86, 0.60, 0.0, "crease"),
    (0.98, 0.72, 0.07, "crown"), (1.05, 0.95, 0.10, "crown"), (1.07, 1.22, 0.10, "crown"),
    (1.01, 1.48, 0.10, "crown"), (0.82, 1.68, 0.08, "crown"), (0.46, 1.80, 0.05, "crown"),
]
TOP = 1.84


def toque():
    rings = []
    for r, z, p, _ in PROF:
        ring = []
        for k in range(SEGS):
            a = k * math.tau / SEGS
            rr = r * (1 + p * math.cos(PLEATS * a))
            zz = z + (0.05 * math.cos(PLEATS * a) if z > 1.6 else 0.0)   # lumpy puffs on the top
            ring.append((rr * math.cos(a), rr * math.sin(a), zz))
        rings.append(ring)
    kinds = [None] + [q[3] for q in PROF]   # band i lies between ring i-1 and ring i

    def col(i, k, c):
        kind = kinds[min(i, len(PROF) - 1)] if i > 0 else "under"
        if i <= 2:
            return W_LO
        if kind == "stripe":
            return STRIPE
        if kind in ("band", "crease"):
            return mix(W_LO, W_HI, 0.55)
        # crown: dark in the pleat valleys and underneath, light on top
        a = math.atan2(c.y, c.x)
        valley = 0.5 - 0.5 * math.cos(PLEATS * a)
        t = min(1, max(0, (c.z - 0.6) / 0.8))
        return mix(W_LO, W_HI, max(0, min(1, 0.35 + 0.65 * t - 0.3 * valley)))
    return rings_shell("Toque", rings, col, poles=((0, 0, 0.14), (0, 0, TOP)))


parts = [toque()]

if os.environ.get("HAT_PREVIEW"):
    SL = mix(GOO, P["ranch_field_dark"], 0.15)
    prof = [(0, -1.6), (0.9, -1.58), (1.15, -1.3), (1.2, -0.8), (1.05, -0.3), (0.7, -0.03), (0.0, 0.06)]
    parts.append(lathe("PreviewSlime", prof, lambda i, k, c: mix(SL, GOO, min(1, (c.z + 1.6) / 1.6)), segs=24))

o = finish("slime_hat_chef", parts)
a = o.data.attributes.get("keep_smooth")
if a is not None:
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
o["smooth_normals"] = 1
