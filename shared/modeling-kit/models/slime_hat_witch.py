# slime_hat_witch: paid slime hat cosmetic (Halloween), a floppy witch hat.
# Wide brim with a floppy wavy edge (never below z=0), a crown swept along a bending path so the tip flops
# over to the side, a pumpkin-orange band and a goo-green buckle.
# Origin bottom centre, Z up, front -Y, ~2.1 wide, ~2.4 tall. HAT_PREVIEW=1 adds a stand-in slime.
import math
import os
from models._pvp_fun import *

HAT = rgb(132, 88, 196)            # witch purple
HAT_LO = rgb(108, 70, 166)
HAT_HI = rgb(170, 126, 228)
BAND = mix(BUTTER, RED, 0.5)       # pumpkin orange
BAND_LO = mix(BAND, RED, 0.2)
BUCKLE = GOO
SEGS = 14


def catmull(pts, n):
    P = [Vector(p) for p in pts]
    P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    out = []
    for i in range(1, len(P) - 2):
        for j in range(n):
            t = j / n
            p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return out


# crown path (bends over to +X and a little back) and radii at the control points
PATH = [(0, 0, 0.12), (0, 0, 0.75), (0.02, 0.04, 1.38), (0.14, 0.1, 1.9), (0.42, 0.16, 2.22), (0.74, 0.2, 2.12), (0.86, 0.2, 1.88)]
RADII = [0.74, 0.56, 0.38, 0.25, 0.16, 0.09, 0.03]


def crown():
    pts = catmull(PATH, 2)
    rads = []
    for i in range(len(pts)):
        u = i / (len(pts) - 1) * (len(RADII) - 1)
        a = int(min(u, len(RADII) - 2))
        f = u - a
        r = RADII[a] * (1 - f) + RADII[a + 1] * f
        if 2 <= i <= len(pts) - 3 and i % 2 == 1:
            r *= 0.94                     # soft crinkle rings: floppy fabric
        rads.append(r)
    zmax = max(p.z for p in pts)

    def col(i, k, c):
        t = min(1, max(0, (c.z - 0.3) / (zmax - 0.3)))
        return mix(HAT_LO, HAT_HI, 0.15 + 0.85 * t)
    return sweep("Crown", [tuple(p) for p in pts], rads, col, segs=SEGS)


def brim():
    prof = [(0.55, 0.09), (0.98, 0.03), (1.1, 0.03), (1.12, 0.07), (1.02, 0.11), (0.75, 0.15)]
    rings = []
    for r, z in prof:
        ring = []
        for k in range(24):
            a = k * math.tau / 24
            w = max(0, (r - 0.6) / 0.52) ** 1.5
            zz = z + 0.1 * (1 + math.sin(3 * a + 0.6)) * w        # floppy wave, only upward
            ring.append((r * math.cos(a), r * math.sin(a), zz))
        rings.append(ring)

    def col(i, k, c):
        if i <= 2:
            return HAT_LO
        return mix(HAT_LO, HAT, 0.3 + 2.5 * max(0, c.z - 0.05))
    return rings_shell("Brim", rings, col, poles=((0, 0, 0.13), (0, 0, 0.16)))


def band():
    prof = [(0.0, 0.16), (0.745, 0.16), (0.76, 0.19), (0.68, 0.44), (0.0, 0.44)]
    return lathe("Band", prof, lambda i, k, c: mix(BAND_LO, BAND, min(1, max(0, (c.z - 0.16) / 0.25))), segs=SEGS)


def buckle():
    y, z = -0.735, 0.30
    plate = box_part("Buckle", (0.30, 0.06, 0.24), BUCKLE, M=place((0, y, z), (-17, 0, 0)), bevel_w=0.02)
    win = box_part("BuckleWin", (0.15, 0.05, 0.11), BAND_LO, M=place((0, y - 0.018, z), (-17, 0, 0)))
    return [plate, win]


parts = [crown(), brim(), band()] + buckle()

if os.environ.get("HAT_PREVIEW"):
    SL = mix(GOO, P["ranch_field_dark"], 0.15)
    prof = [(0, -1.6), (0.9, -1.58), (1.15, -1.3), (1.2, -0.8), (1.05, -0.3), (0.7, -0.03), (0.0, 0.06)]
    parts.append(lathe("PreviewSlime", prof, lambda i, k, c: mix(SL, GOO, min(1, (c.z + 1.6) / 1.6)), segs=24))

o = finish("slime_hat_witch", parts)
a = o.data.attributes.get("keep_smooth")
if a is not None:
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
o["smooth_normals"] = 1
