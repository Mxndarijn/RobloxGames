# ranch_border_hill: soft grassy mound for the world border (Slime Ranch), ~29 x 8 x 17.
# Elliptical closed heightfield (two humps, lower one on +X) painted per vertex (smooth light-top
# gradient, no face checker), a goo puddle at its foot on the map side (-Y), two mossy stones,
# tufts and blooms. Placed at the edge, often half behind the front row.
import math, random
import bmesh
from mathutils import Vector
from lib import *
from models._border import *
from models._rocks import stone

R = random.Random(31)
SX, SY, H = 29.0, 17.0, 7.8


def bump(u, v, cu, cv, su, sv):
    d = ((u - cu) / su) ** 2 + ((v - cv) / sv) ** 2
    return math.exp(-d * 1.4)


def height(u, v):
    rr = u * u + v * v
    edge = max(0.0, 1 - rr) ** 0.7  # 0 on the ellipse rim
    h = H * bump(u, v, -0.22, 0.1, 0.7, 0.75) + H * 0.6 * bump(u, v, 0.5, -0.02, 0.45, 0.62)
    h += 0.3 * math.sin(u * 6.1 + 1.3) * math.cos(v * 4.7)  # gentle lumps
    return max(0.0, h * edge)


def colour(z):
    t = min(1.0, z / (H * 0.8))
    return mix(FIELD_D, FIELD_L, t ** 0.85)


# polar grid (r02: a square grid cut to the ellipse left a stepped rim)
NS, NR = 30, 10
bm = bmesh.new()
centre = bm.verts.new((0, 0, height(0, 0)))
rings = []
for i in range(1, NR + 1):
    rho = (i / NR) ** 0.85
    ring = []
    for k in range(NS):
        a = k * math.tau / NS + (0.5 * math.tau / NS if i % 2 else 0)
        u, w = math.cos(a) * rho, math.sin(a) * rho
        ring.append(bm.verts.new((u * SX / 2, w * SY / 2, height(u, w) if i < NR else 0.0)))
    rings.append(ring)
for k in range(NS):
    bm.faces.new((centre, rings[0][k], rings[0][(k + 1) % NS]))
for a, b in zip(rings, rings[1:]):
    for k in range(NS):
        bm.faces.new((a[k], b[k], b[(k + 1) % NS], a[(k + 1) % NS]))
bmesh.ops.triangulate(bm, faces=bm.faces)
top = list(bm.faces)
res = bmesh.ops.extrude_face_region(bm, geom=top)
for e in res["geom"]:
    if isinstance(e, bmesh.types.BMVert):
        e.co.z = -0.12
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
layer = bm.loops.layers.color.new("Col")
top_set = set(top)
for f in bm.faces:
    for lp in f.loops:
        lp[layer] = colour(lp.vert.co.z) if f in top_set else FIELD_D
parts = [obj_from_bm("Mound", bm)]


def hz(x, y):
    return height(x / (SX / 2), y / (SY / 2))  # finish() lifts the -0.12 skirt to z=0


parts.append(stone("StoneA", (3.0, 2.6, 2.2), (6.8, -4.0, hz(6.8, -4.0) - 0.5), seed=5,
                   base=rgb(200, 180, 150), moss=FIELD, moss_from=0.6, cuts=2))
parts.append(stone("StoneB", (1.9, 1.7, 1.4), (-9.0, -4.6, hz(-9.0, -4.6) - 0.3), seed=9,
                   base=rgb(190, 172, 146), cuts=1))
# goo puddle on the flat foot at the map side + highlight bubbles
gx, gy = -3.0, -7.4
g = blob("Goo", 1.7, (gx, gy, 0.1), GOO, subdiv=2, squash=(1.6, 0.85, 0.12), jitter=0.03)
gradient(g, GOO, mix(GOO, GOO_HI, 0.4))
parts.append(g)
for k, (dx, dy) in enumerate([(-0.7, 0.2), (0.9, -0.15)]):
    parts.append(blob(f"Bubble{k}", 0.34, (gx + dx, gy + dy, 0.28), GOO_HI, subdiv=1, squash=(1, 1, 0.45), jitter=0.0))
# tufts and blooms scattered on the map-facing slope
for k in range(12):
    x, y = R.uniform(-12, 12), R.uniform(-7.0, 1.5)
    if (x / (SX / 2)) ** 2 + (y / (SY / 2)) ** 2 > 0.8 or (abs(x - gx) < 3 and abs(y - gy) < 2):
        continue
    if k % 3 == 0:
        parts += flower(f"Bloom{k}", (x, y, hz(x, y) + 0.15), R, (PINK, BUTTER, LILAC)[(k // 3) % 3])
    else:
        parts += tuft(f"Tuft{k}", (x, y, hz(x, y)), R, h=1.0)
finish("ranch_border_hill", parts)
