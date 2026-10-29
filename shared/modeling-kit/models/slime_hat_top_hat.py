# slime_hat_top_hat: paid slime hat cosmetic, a short cartoon top hat with a band.
# One closed lathe: hollow underside, a brim curled up at the sides (+-X), a crown that pinches a little at the
# waist and flares to the top, and a pink ribbon band. Indigo instead of black (THEME: no near-black).
# Origin bottom centre, Z up, front -Y, brim ~2.0 wide, ~1.4 tall. HAT_PREVIEW=1 adds a stand-in slime.
import math
import os
from models._pvp_fun import *

HAT = rgb(92, 84, 184)              # indigo felt
HAT_LO = rgb(78, 70, 156)
HAT_HI = rgb(128, 118, 214)
BAND = mix(RED, PINK, 0.45)
BAND_HI = mix(PINK, WHITE, 0.2)
SEGS = 20
CURL = 0.2                          # brim curl at the sides

# (r, z, kind, curl weight)  bottom -> top
PROF = [
    (0.45, 0.10, "under", 0.0), (0.80, 0.04, "under", 0.6), (0.97, 0.0, "brim", 1.0),
    (1.0, 0.06, "brim", 1.0), (0.94, 0.11, "brim", 1.0), (0.70, 0.10, "brim", 0.2),
    (0.63, 0.13, "brim", 0.0), (0.62, 0.30, "band", 0.0), (0.61, 0.42, "crown", 0.0),
    (0.61, 0.80, "crown", 0.0), (0.66, 1.26, "crown", 0.0), (0.68, 1.34, "crown", 0.0),
    (0.62, 1.40, "top", 0.0), (0.30, 1.42, "top", 0.0),
]
TOP = 1.43


def hat():
    rings = []
    for r, z, _, w in PROF:
        ring = []
        for k in range(SEGS):
            a = k * math.tau / SEGS
            ring.append((r * math.cos(a), r * math.sin(a), z + w * CURL * math.cos(a) ** 2))
        rings.append(ring)
    kinds = [q[2] for q in PROF]

    def col(i, k, c):
        if i == 0 or i >= len(PROF):
            return HAT_HI if i >= len(PROF) else HAT_LO
        kind = kinds[i]                      # band i lies between ring i-1 and ring i
        if kind == "under":
            return HAT_LO
        if kind == "band" or (kind == "crown" and c.z < 0.42):
            return BAND
        if kind == "brim":
            return mix(HAT_LO, HAT_HI, 0.5 if c.z > 0.08 else 0.15)
        if kind == "top":
            return HAT_HI
        return HAT if c.z < 1.25 else mix(HAT, HAT_HI, 0.5)
    return rings_shell("TopHat", rings, col, poles=((0, 0, 0.13), (0, 0, TOP)))


def buckle():
    """White buckle on the band front (-Y): a plate with a band-coloured window, proud of the band."""
    y = -0.62
    plate = box_part("Buckle", (0.30, 0.06, 0.25), mix(WHITE, LILAC, 0.1), M=place((0, y - 0.01, 0.275)), bevel_w=0.02)
    win = box_part("BuckleWin", (0.15, 0.05, 0.11), BAND, M=place((0, y - 0.025, 0.275)))
    return [plate, win]


parts = [hat()] + buckle()

if os.environ.get("HAT_PREVIEW"):
    SL = mix(GOO, P["ranch_field_dark"], 0.15)
    prof = [(0, -1.6), (0.9, -1.58), (1.15, -1.3), (1.2, -0.8), (1.05, -0.3), (0.7, -0.03), (0.0, 0.06)]
    parts.append(lathe("PreviewSlime", prof, lambda i, k, c: mix(SL, GOO, min(1, (c.z + 1.6) / 1.6)), segs=24))

o = finish("slime_hat_top_hat", parts)
a = o.data.attributes.get("keep_smooth")
if a is not None:
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
o["smooth_normals"] = 1
