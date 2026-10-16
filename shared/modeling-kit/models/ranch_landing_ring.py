# ranch_landing_ring: one curb segment for the wild-slime landing ring around the fountain plaza
# (Slime Ranch). A curved, soft ranch_plaza curb on the INNER edge of the wild landing band
# (r34-62): curb r34-35.7, ~12 studs of arc, a wood stake post + butter cap at the -X end, and a goo splat
# puddle beyond r36 on the landing side where wilds plop down off the slide.
# Local frame: arc centre (fountain/plaza centre) is at y = +R, so +Y faces the fountain and the
# landing side is -Y (outward). Tile it by rotating copies about the plaza centre.
import math
import bmesh
from lib import *

PLAZA, PATH = PALETTE["ranch_plaza"], PALETTE["ranch_path"]
WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
BUTTER, ROOF = PALETTE["ranch_butter"], PALETTE["ranch_roof"]
WOOD_LO = mix(WOOD_D, WOOD, 0.4)
PLAZA_LO = mix(PLAZA, WOOD, 0.35)
R = 34.0          # ring inner radius from FOUNTAIN_SIZES (drop ring 34..62)
SPAN = 20.0       # degrees of arc -> ~12 studs
parts = []


def arc_block(name, r0, r1, a0, a1, z0, z1, segs, lo, hi, bev=0.12):
    """Closed annular sector, centre at (0, R)."""
    bm = bmesh.new()
    ring = []
    for i in range(segs + 1):
        a = math.radians(a0 + (a1 - a0) * i / segs)
        ring.append((math.sin(a), -math.cos(a)))
    pts = [(s * r1, R + c * r1) for s, c in ring] + [(s * r0, R + c * r0) for s, c in reversed(ring)]
    vb = [bm.verts.new((x, y, z0)) for x, y in pts]
    bm.faces.new(vb)
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.z = z1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    o = obj_from_bm(name, bm)
    bevel(o, bev)
    gradient(o, lo, hi)
    return o


# curb: three chunky stones per segment with small gaps (reads as laid blocks, tiles cleanly)
n = 3
step = SPAN / n
for k in range(n):
    a0 = -SPAN / 2 + k * step + 0.25
    a1 = a0 + step - 0.5
    h = 1.25 + 0.08 * ((k * 7) % 3 - 1)
    parts.append(arc_block(f"Curb{k}", R, R + 1.7, a0, a1, 0, h, 4, PLAZA_LO, PLAZA, bev=0.22))
# low path apron under the curb, landing side
parts.append(arc_block("Apron", R + 1.7, R + 3.9, -SPAN / 2, SPAN / 2, 0, 0.18, 6, PATH, PATH, bev=0.05))


def on_ring(r, deg):
    a = math.radians(deg)
    return math.sin(a) * r, R - math.cos(a) * r, -deg  # x, y, yaw


# one wood stake per segment, at its -X end, with a butter cap: tiled, the next segment's stake
# closes this one's +X end, so each seam shows ONE stake (r01 had both ends: doubled at every seam)
for deg in (-SPAN / 2 + 0.6,):
    x, y, yaw = on_ring(R + 0.85, deg)
    s = box("Stake", (0.8, 0.8, 2.6), (x, y, 1.3), rot=(0, 0, yaw))
    bevel(s, 0.12)
    gradient(s, WOOD_LO, WOOD)
    parts.append(s)
    c = cylinder("Cap", 0.55, 0.45, (x, y, 2.6), segs=8, r_top=0.3)
    gradient(c, mix(BUTTER, WOOD, 0.3), BUTTER)
    parts.append(c)
# red marker band on the middle stone (readable target from the ring path)
x, y, yaw = on_ring(R + 0.85, 0)
b = box("Band", (2.4, 1.85, 0.25), (x, y, 1.28), rot=(0, 0, yaw))
bevel(b, 0.08)
gradient(b, mix(PALETTE["ranch_roof_dark"], ROOF, 0.5), ROOF)
parts.append(b)


# goo splat puddle on the landing side: closed slab, star-ish outline, raised rim lighter
def splat(name, cx, cy, rad, seg=20, seed=1):
    rr = rng(seed)
    bm = bmesh.new()
    prof = [rad * (1 + 0.28 * math.sin(i * 5 * math.tau / seg + seed) + 0.1 * (rr.random() - 0.5)) for i in range(seg)]
    centre = bm.verts.new((cx, cy, 0.32))
    outer = [bm.verts.new((cx + math.cos(i * math.tau / seg) * p, cy + math.sin(i * math.tau / seg) * p, 0.05)) for i, p in enumerate(prof)]
    mid = [bm.verts.new((cx + math.cos(i * math.tau / seg) * p * 0.7, cy + math.sin(i * math.tau / seg) * p * 0.7, 0.38)) for i, p in enumerate(prof)]
    bot = bm.verts.new((cx, cy, 0.02))
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((centre, mid[i], mid[j]))
        bm.faces.new((mid[i], outer[i], outer[j], mid[j]))
        bm.faces.new((bot, outer[j], outer[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            v = lp.vert
            lp[layer] = GOO_HI if v in mid else (shade(GOO, 0.85) if v in outer or v is bot else GOO)
    return obj_from_bm(name, bm)


parts.append(splat("Splat", 0.6, -6.6, 2.6, seed=2))
parts.append(splat("Splat2", -3.6, -4.2, 1.0, seg=12, seed=5))
for k, (x, y, r) in enumerate(((3.6, -4.6, 0.45), (-2.0, -8.8, 0.35), (3.0, -9.2, 0.3))):
    d = blob(f"Drop{k}", r, (x, y, r * 0.35), GOO, seed=k, subdiv=2, squash=(1, 1, 0.55), jitter=0.03)
    gradient(d, GOO, GOO_HI)
    parts.append(d)

finish("ranch_landing_ring", parts)
