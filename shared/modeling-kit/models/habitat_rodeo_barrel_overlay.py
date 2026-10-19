# habitat_rodeo_barrel_overlay: rodeo-arena dressing for the crate pad: a dusty arena-dirt frame round the mat,
# four hooped rodeo barrels (green band) on the corners with a sagging rope ring between them, a green sign with
# a lucky horseshoe at the back middle, a green pennant on the back-left barrel, a lasso coil and hay at the front.
import math
import random
import bmesh
from lib import *
from lib.shapes import obj_from_bm
from models._habitat import lathe
from models._habitat_overlay import *
from models._phoenix_ranch import BUTTER, CREAM, WOOD, WOOD_D, P, bbox

DIRT = rgb(200, 146, 94)
GREEN = rgb(60, 184, 88)
METAL = mix(P["ranch_metal"], CREAM, 0.35)
SILVER = rgb(222, 224, 230)
ROPE = rgb(232, 196, 128)
R = random.Random(7)

parts = [frame("Dirt", DIRT, shade(DIRT, 0.82), seed=7, wobble=0.06, segs=4)]

# corner barrels: wood staves, light metal hoops, green painted band, cream lid
BR, BH, BC = 0.6, 1.25, 3.1


def barrel_col(i, k, z):
    if 0.12 < z < 0.24 or 1.0 < z < 1.12:
        return METAL
    if 0.42 < z < 0.83:
        return GREEN if k % 2 else shade(GREEN, 0.92)
    if z > BH - 0.01:
        return mix(WOOD, CREAM, 0.45)
    return shade(mix(WOOD, CREAM, 0.15), 0.92 + 0.12 * (k % 2) + 0.1 * z / BH)


PROF = [(0, 0), (BR, 0), (BR + 0.03, 0.12), (BR + 0.05, 0.24), (BR + 0.07, 0.42), (BR + 0.07, 0.83),
        (BR + 0.05, 1.0), (BR + 0.03, 1.12), (BR, BH), (0, BH)]
BARRELS = [(sx * BC, sy * BC) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
for i, (x, y) in enumerate(BARRELS):
    parts.append(lathe(f"Barrel{i}", PROF, segs=8, color_fn=barrel_col, pos=(x, y, 0), phase=math.pi / 8))


def sag(name, a, b, dip, r=0.13, n=6):
    """Rope from a to b hanging dip studs at the middle (parabola)."""
    pts = []
    for k in range(n + 1):
        t = k / n
        p = [a[j] + (b[j] - a[j]) * t for j in range(3)]
        p[2] -= dip * 4 * t * (1 - t)
        pts.append(tuple(p))
    return tube(name, pts, [r] * len(pts), ROPE, segs=5)


RZ, RE = 1.05, 3.15  # rope height at the barrels, rope line on the band
parts.append(sag("RopeL", (-RE, -BC + 0.4, RZ), (-RE, BC - 0.4, RZ), 0.35))
parts.append(sag("RopeR", (RE, -BC + 0.4, RZ), (RE, BC - 0.4, RZ), 0.35))
parts.append(sag("RopeF", (-BC + 0.4, -RE, 0.9), (BC - 0.4, -RE, 0.9), 0.45))  # front rope hangs lowest
parts.append(sag("RopeBL", (-BC + 0.4, RE, RZ), (-0.8, RE, 1.2), 0.25, n=4))
parts.append(sag("RopeBR", (0.8, RE, 1.2), (BC - 0.4, RE, RZ), 0.25, n=4))

# back sign: green board on two posts with a lucky horseshoe (opening up) on both faces
SY, SW, SH, SZ = 3.2, 1.7, 1.2, 0.55
for s in (-1, 1):
    parts.append(bbox(f"SignLeg{s}", (0.2, 0.2, SZ + 0.2), (s * 0.55, SY, (SZ + 0.2) / 2), shade(WOOD_D, 0.85), WOOD_D, bev=0))
parts.append(bbox("Sign", (SW, 0.22, SH), (0, SY, SZ + SH / 2), shade(GREEN, 0.78), GREEN, bev=0.05))
parts.append(bbox("SignTrim", (SW + 0.12, 0.28, 0.14), (0, SY, SZ + SH + 0.04), shade(CREAM, 0.9), CREAM, bev=0))
HU, HT = 0.36, 0.11  # horseshoe U radius, tube radius
cz = SZ + SH / 2 - 0.05
for f, fy in (("F", SY - 0.11 - HT * 0.6), ("B", SY + 0.11 + HT * 0.6)):
    pts = [(0 - HU, fy, cz + 0.32)]  # left leg top
    for k in range(9):
        a = math.pi + math.pi * k / 8  # bottom half circle, left to right
        pts.append((HU * math.cos(a), fy, cz + HU * math.sin(a)))
    pts.append((HU, fy, cz + 0.32))
    parts.append(tube(f"Shoe{f}", pts, [HT] * len(pts), SILVER, segs=4))
    for s in (-1, 1):  # flared heel tips
        parts.append(box(f"Heel{f}{s}", (0.3, 0.12, 0.12), (s * (HU + 0.03), fy, cz + 0.36), SILVER))

# green pennant on the back-left barrel
px, py = BARRELS[3]
parts.append(cylinder("Pole", 0.07, 1.15, (px, py, BH), CREAM, segs=5))
bm = bmesh.new()
col = bm.loops.layers.color.new("Col")
tri = [(0, 0), (1.15, -0.28), (0, -0.56)]  # (along +x, down from the pole top)
top = BH + 1.1
vs = [bm.verts.new((px + 0.05 + u, py + dy, top + v)) for dy in (-0.04, 0.04) for u, v in tri]
for f in ((vs[0], vs[1], vs[2]), (vs[3], vs[5], vs[4]), (vs[0], vs[3], vs[4], vs[1]), (vs[1], vs[4], vs[5], vs[2]),
          (vs[2], vs[5], vs[3], vs[0])):
    face = bm.faces.new(f)
    for lp in face.loops:
        lp[col] = GREEN if lp.vert.co.x - px < 0.6 else shade(GREEN, 1.12)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
parts.append(obj_from_bm("Pennant", bm))
parts.append(blob("PoleKnob", 0.11, (px, py, BH + 1.2), BUTTER, subdiv=1, jitter=0))

# lasso coil lying on the front band, hay tufts on the right side
coil = [(-1.25 + 0.45 * math.cos(math.tau * k / 10), -3.15 + 0.42 * math.sin(math.tau * k / 10), 0.26) for k in range(11)]
parts.append(tube("Lasso", coil, [0.12] * 11, ROPE, segs=4))
parts.append(tube("LassoEnd", [(-0.8, -3.15, 0.26), (-0.2, -3.25, 0.22)], [0.12, 0.1], ROPE, segs=5))
for i, (x, y) in enumerate(((3.15, -0.9), (3.2, -0.3), (-3.15, 0.6))):
    parts.append(blob(f"Hay{i}", 0.4, (x, y, 0.37), shade(BUTTER, R.uniform(0.95, 1.06)), subdiv=1,
                      squash=(1.0, 1.3, 0.8), jitter=0.08, seed=i, rot=(0, 0, R.uniform(-30, 30))))
overlay_finish("habitat_rodeo_barrel_overlay", parts)
