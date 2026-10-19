# Mystery Egg nest: chunky straw bowl on the plot pad that holds a mystery egg.
# ~3.4 wide, ~0.9 tall, hollow dip whose lowest point is at EGG_Z (0.3) so the shared egg
# (models/_mystery_egg.py: 2.2 x 1.7) sits with its bottom 0.3 above z=0.
# Bowl = closed lathe (straw-striped columns), two twisted straw coils round the rim,
# a few dark twigs poking out for silhouette.
# Preview with the egg in it: MYSTERY_NEST_PREVIEW=1 python iterate.py models/mystery_egg_nest.py --no-export
import math, os
import bmesh
from mathutils import Vector
from lib import *
from lib.shapes import obj_from_bm
from models import _mystery_egg as egg

EGG_Z = 0.3
BUTTER = PALETTE["ranch_butter"]
PATH = PALETTE["ranch_path"]
WOOD = PALETTE["ranch_wood"]
WOOD_D = PALETTE["ranch_wood_dark"]
STRAW = mix(BUTTER, WOOD, 0.15)
STRAW_D = mix(BUTTER, WOOD, 0.55)
STRAW_HI = mix(BUTTER, PALETTE["ranch_cream"], 0.35)
TWIG_LO = WOOD_D
TWIG_HI = mix(WOOD_D, WOOD, 0.6)

# (r, z) profile, bottom axis -> outer wall -> rim -> inner dip -> dip centre (EGG_Z)
OUTER = [(0.0, 0.0), (1.2, 0.0), (1.5, 0.12), (1.64, 0.34), (1.62, 0.56), (1.46, 0.74)]
INNER = [(1.2, 0.78), (1.0, 0.68), (0.78, 0.53), (0.5, 0.39), (0.0, EGG_Z)]
PROFILE = OUTER + INNER
N_OUT = len(OUTER)


def lathe(name, profile, segs, color_fn, seed=1, jit=0.04):
    r = rng(seed)
    bm = bmesh.new()
    rings = []
    for i, (rad, z) in enumerate(profile):
        if rad <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        ring = []
        for k in range(segs):
            a = k * math.tau / segs
            rr = rad * (1 + (r.random() * 2 - 1) * jit) if 0 < i < len(profile) - 1 else rad
            zz = z + ((r.random() * 2 - 1) * 0.03 if 1 < i < len(profile) - 2 else 0)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), zz)))
        rings.append(ring)
    info = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segs):
            k1 = (k + 1) % segs
            if len(a) == 1:
                vs = (a[0], b[k1], b[k])
            elif len(b) == 1:
                vs = (a[k], a[k1], b[0])
            else:
                vs = (a[k], a[k1], b[k1], b[k])
            bm.faces.new(vs)
            info.append((i, k))
    bm.faces.index_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    col = bm.loops.layers.color.new("Col")
    for fi, (i, k) in enumerate(info):
        f = bm.faces[fi]
        c = color_fn(i, k, f.calc_center_median())
        for lp in f.loops:
            lp[col] = c
    return obj_from_bm(name, bm)


def bowl_col(i, k, c):
    stripe = [STRAW, STRAW_HI, mix(STRAW, STRAW_D, 0.5)][k % 3]  # vertical straw stripes only
    if i >= N_OUT:  # inside the dip: plain, darker toward the bottom (reads as hollow, not a pie)
        t = min(1.0, max(0.0, (c.z - EGG_Z) / 0.5))
        return mix(mix(WOOD, STRAW_D, 0.4), STRAW, 0.25 + 0.6 * t)
    t = min(1.0, c.z / 0.8)
    return mix(mix(STRAW_D, WOOD, 0.35), stripe, 0.45 + 0.55 * t)


def coil(name, pts_fn, n, tube_r, segs=6, twist=2):
    """Closed straw rope along a loop: diagonal colour stripes give the twisted look."""
    bm = bmesh.new()
    pts = [Vector(pts_fn(j / n)) for j in range(n)]
    rings = []
    for j, p in enumerate(pts):
        d = (pts[(j + 1) % n] - pts[j - 1]).normalized()
        side = d.cross(Vector((0, 0, 1))).normalized()
        up = side.cross(d).normalized()
        rings.append([bm.verts.new(p + (side * math.cos(k * math.tau / segs) + up * math.sin(k * math.tau / segs)) * tube_r)
                      for k in range(segs)])
    info = []
    for j in range(n):
        a, b = rings[j], rings[(j + 1) % n]
        for k in range(segs):
            k1 = (k + 1) % segs
            bm.faces.new((a[k], a[k1], b[k1], b[k]))
            info.append((j, k))
    bm.faces.index_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    bm.normal_update()
    col = bm.loops.layers.color.new("Col")
    for fi, (j, k) in enumerate(info):
        f = bm.faces[fi]
        band = (j * twist + k) % 4
        base = [STRAW_HI, STRAW, STRAW_D, STRAW][band]
        lit = max(0.0, f.normal.z) * 0.5 + 0.5  # undersides a touch darker
        c = mix(mix(base, WOOD, 0.3), base, lit)
        for lp in f.loops:
            lp[col] = c
    return obj_from_bm(name, bm)


parts = [lathe("Bowl", PROFILE, 20, bowl_col)]
parts.append(coil("CoilTop", lambda u: ((1.36 + 0.06 * math.sin(5 * u * math.tau + 0.7 * math.sin(2 * u * math.tau))) * math.cos(u * math.tau),
                                        (1.36 + 0.06 * math.sin(5 * u * math.tau + 0.7 * math.sin(2 * u * math.tau))) * math.sin(u * math.tau),
                                        0.68 + 0.06 * math.sin(3 * u * math.tau)), 28, 0.16))
parts.append(coil("CoilMid", lambda u: ((1.58 + 0.03 * math.sin(4 * u * math.tau + 1)) * math.cos(u * math.tau + 0.4),
                                        (1.58 + 0.03 * math.sin(4 * u * math.tau + 1)) * math.sin(u * math.tau + 0.4),
                                        0.38 + 0.04 * math.sin(2 * u * math.tau + 2)), 28, 0.15, twist=3))

# Twigs: laid round the rim on the coils, ends crossing outward and up (messy nest silhouette).
r = rng(5)
for i in range(7):
    a = i * math.tau / 7 + r.uniform(-0.2, 0.2)
    d = 1 if i % 2 else -1          # which way it runs along the rim
    span = 0.75 + r.uniform(0, 0.2)  # angle covered
    z0 = 0.62 + r.uniform(-0.06, 0.06)
    pts, rads = [], []
    for j, u in enumerate((0.0, 0.5, 1.0)):
        rr = 1.3 + 0.38 * u ** 1.6     # starts on the rim, ends poking out
        zz = z0 + 0.15 * u ** 2        # tip lifts
        aa = a + d * span * u
        pts.append((rr * math.cos(aa), rr * math.sin(aa), zz))
        rads.append(0.11 - 0.025 * u)
    t = tube("Twig%d" % i, pts, rads, segs=5)
    parts.append(gradient(t, TWIG_LO, TWIG_HI))

# Clearance check: inner dip vs the egg sitting at EGG_Z (shared egg profile).
worst = 9.0
for rad, z in INNER:
    h = z - EGG_Z
    if 0 < h < egg.H:
        er = egg.radius_at_z(h)
        worst = min(worst, rad - er)
print("NEST egg_z=%.2f min dip clearance (dip r - egg r at same z) = %.3f" % (EGG_Z, worst))

if os.environ.get("MYSTERY_NEST_PREVIEW"):
    e = egg.shell("PreviewEgg", lambda s, th, t: mix(rgb(226, 196, 148), rgb(250, 234, 200), s))
    e.location.z = EGG_Z
    parts.append(e)

o = finish("mystery_egg_nest", parts)
