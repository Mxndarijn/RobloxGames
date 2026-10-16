# ranch_campfire: plaza fire pit with a goo kettle on a wood tripod (Slime Ranch plaza prop).
# Ember bed disc inside a ring of chunky rounded stones (warm sand/path tones, never grey), two
# crossed logs + two leaning logs, stylised low-poly flame tongues (closed lathes whose tips curl;
# roof red base -> butter -> cream-butter tip, NO neon), a 3-leg wood tripod (one leg at the back,
# two front so the -Y view sees the fire) lashed with twine, pewter hook + kettle (closed lathe with
# a goo-filled mouth) whose goo bulges over the lip and drips down the front (lib/goo.py).
# Medium prop, target 500-2000 tris, ~4 wide, ~4.5 tall. cylinder() pos = base; lib rot= is in DEGREES.
import math, random
import bmesh
from mathutils import Matrix, Vector
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL = PALETTE["ranch_cream"], PALETTE["ranch_metal"]
PATH, PLAZA = PALETTE["ranch_path"], PALETTE["ranch_plaza"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
BUTTER = PALETTE["ranch_butter"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
FIELD_D, FIELD_L = PALETTE["ranch_field_dark"], PALETTE["ranch_field_light"]
BARK_LO, BARK_HI = mix(WOOD_D, WOOD, 0.3), mix(WOOD_D, WOOD, 0.9)
HEART = mix(PATH, CREAM, 0.15)
METAL_LO, METAL_HI = mix(METAL, WOOD_D, 0.15), mix(METAL, CREAM, 0.3)
STONE_LO, STONE_HI = mix(PLAZA, WOOD_D, 0.2), mix(PATH, CREAM, 0.45)
R = random.Random(21)
parts = []

# --- dimensions --------------------------------------------------------------------------
RING_R, NSTONE = 1.5, 9        # stone ring centre radius, stone count
LEG_R, APEX = 2.15, 4.25       # tripod foot radius, apex height
KZ = 2.3                       # kettle base height


def lathe(name, rows, segs, color_rows, pos=(0, 0, 0)):
    """closed surface of revolution: rows of (r, z) bottom->top; r == 0 at either end makes a pole.
    color_rows: one RGBA per row (faces take the mean of their rows)."""
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    rings, vrow = [], {}
    for ri, (r, z) in enumerate(rows):
        if r <= 1e-6:
            v = bm.verts.new((0, 0, z))
            vrow[v] = ri
            rings.append([v])
            continue
        ring = []
        for i in range(segs):
            a = i * math.tau / segs
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
            vrow[ring[-1]] = ri
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[i]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    for ring in (rings[0], rings[-1]):
        if len(ring) > 1:
            bm.faces.new(ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        rs = [vrow[v] for v in f.verts]
        c = color_rows[min(rs)] if max(rs) - min(rs) <= 1 else color_rows[min(rs)]
        for lp in f.loops:
            lp[col] = c
    bmesh.ops.translate(bm, vec=Vector(pos), verts=bm.verts)
    return obj_from_bm(name, bm)


# --- ember bed -------------------------------------------------------------------------------
EMB = [mix(WOOD_D, ROOF_D, 0.4), mix(WOOD_D, ROOF_D, 0.5), mix(WOOD_D, ROOF_D, 0.8), mix(ROOF_D, ROOF, 0.5)]
parts.append(lathe("Embers", [(0, 0.0), (1.3, 0.0), (1.3, 0.1), (0.9, 0.16), (0.45, 0.2), (0, 0.22)], 12,
                   [EMB[0], EMB[0], EMB[1], EMB[2], EMB[3], EMB[3]]))

# --- stone ring ------------------------------------------------------------------------------
for k in range(NSTONE):
    a = k * math.tau / NSTONE + R.uniform(-0.08, 0.08) + 0.15
    sr = R.uniform(0.44, 0.52)
    p = (RING_R * math.cos(a), RING_R * math.sin(a), sr * 0.62)
    parts.append(blob(f"Stone{k}", sr, p, PATH, subdiv=2, squash=(1.0, 1.35, 0.68), jitter=0.07, seed=k,
                      rot=(0, 0, math.degrees(a) + 90)))
    lo = STONE_LO if k % 2 else mix(STONE_LO, PLAZA, 0.3)
    gradient(parts[-1], lo, STONE_HI if k % 3 else mix(STONE_HI, PLAZA, 0.3))

# --- logs: two crossed flat + two leaning in --------------------------------------------------


def log(name, p0, p1, r):
    o = tube(name, [p0, p0.lerp(p1, 0.5), p1], [r, r * 1.04, r * 0.95], WOOD, segs=6, seed=len(name))
    gradient(o, BARK_LO, BARK_HI)
    # paint the two end caps heartwood (faces whose normal runs along the log)
    d = (p1 - p0).normalized()
    bm = bmesh.new()
    bm.from_mesh(o.data)
    layer = bm.loops.layers.color["Col"]
    bm.normal_update()
    for f in bm.faces:
        if abs(f.normal.dot(d)) > 0.9:
            for lp in f.loops:
                lp[layer] = HEART
    bm.to_mesh(o.data)
    bm.free()
    return o


for k, a in enumerate((25, 115)):
    d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
    z = 0.42 + 0.3 * k
    parts.append(log(f"LogX{k}", -d * 1.15 + Vector((0, 0, z)), d * 1.15 + Vector((0, 0, z)), 0.26))
for k, a in enumerate((-60, 160)):
    d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
    parts.append(log(f"LogL{k}", d * 1.0 + Vector((0, 0, 0.35)), d * 0.15 + Vector((0, 0, 1.25)), 0.21))

# --- flame tongues ---------------------------------------------------------------------------


def flame(name, base, h, w, lean, yaw, inner=False):
    """closed tongue: 5-sided rings bulge then pinch to a tip offset by lean (curl), faceted."""
    segs = 5
    prof = [(0.55, 0.0), (1.0, 0.22), (0.88, 0.45), (0.55, 0.68), (0.25, 0.86), (0.0, 1.0)]
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    rings = []
    ld = Vector((math.cos(yaw), math.sin(yaw), 0))
    for ri, (rf, t) in enumerate(prof):
        c = base + Vector((0, 0, h * t)) + ld * lean * t ** 1.8
        if rf == 0:
            rings.append([bm.verts.new(c)])
            continue
        rings.append([bm.verts.new(c + Vector((math.cos(i * math.tau / segs + yaw) * rf * w,
                                                math.sin(i * math.tau / segs + yaw) * rf * w, 0)))
                      for i in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    lo, mid, hi = (BUTTER, mix(BUTTER, CREAM, 0.25), mix(BUTTER, CREAM, 0.55)) if inner else \
        (mix(ROOF_D, ROOF, 0.6), mix(ROOF, BUTTER, 0.55), BUTTER)
    for f in bm.faces:
        for lp in f.loops:
            t = (lp.vert.co.z - base.z) / h
            lp[col] = mix(lo, mid, t / 0.5) if t < 0.5 else mix(mid, hi, (t - 0.5) / 0.5)
    return obj_from_bm(name, bm)


FLAMES = [  # (x, y, height, width, lean, yaw deg, inner)
    (0.0, 0.05, 2.1, 0.5, 0.35, 200, False),
    (0.45, -0.25, 1.45, 0.38, 0.4, -40, False),
    (-0.5, -0.2, 1.55, 0.4, 0.45, 210, False),
    (0.35, 0.5, 1.3, 0.36, 0.35, 60, False),
    (-0.35, 0.45, 1.2, 0.34, 0.3, 130, False),
    (0.05, -0.2, 1.4, 0.3, 0.25, 260, True),
    (0.2, 0.2, 1.0, 0.24, 0.2, 20, True),
]
for k, (x, y, h, w, lean, yaw, inner) in enumerate(FLAMES):
    parts.append(flame(f"Flame{k}", Vector((x, y, 0.18)), h * 0.95, w * 1.3, lean, math.radians(yaw), inner))

# --- tripod ----------------------------------------------------------------------------------
apex = Vector((0, 0, APEX))
for k, a in enumerate((90, 210, 330)):
    d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
    foot = d * LEG_R
    top = apex + (apex - foot).normalized() * 0.22   # legs cross a little past the lashing
    parts.append(tube(f"Leg{k}", [foot, foot.lerp(top, 0.5), top], [0.15, 0.14, 0.12], WOOD, segs=6))
    gradient(parts[-1], mix(WOOD_D, WOOD, 0.45), mix(WOOD, CREAM, 0.15))
parts.append(cylinder("Lashing", 0.24, 0.32, (0, 0, APEX - 0.22), PATH, segs=6))
gradient(parts[-1], mix(PATH, WOOD, 0.4), mix(PATH, CREAM, 0.2))

# --- hook + kettle -----------------------------------------------------------------------------
KR = 0.85
KROWS = [(0, 0.0), (0.5, 0.0), (0.78, 0.15), (KR, 0.45), (0.8, 0.75), (0.62, 0.97), (0.68, 1.03),
         (0.68, 1.13), (0.55, 1.13), (0.53, 1.06), (0, 1.09)]
MLO, MMID, MHI = METAL, mix(METAL, CREAM, 0.25), mix(METAL, CREAM, 0.45)
kc = [MLO, MLO, MLO, MMID, MMID, MHI, MHI, MHI, GOO, GOO, mix(GOO, GOO_HI, 0.35)]
parts.append(lathe("Kettle", KROWS, 10, kc, pos=(0, 0, KZ)))
parts.append(tube("Hook", [apex - Vector((0, 0, 0.3)), Vector((0, 0, KZ + 1.72)), Vector((0.1, 0, KZ + 1.55))],
                  [0.07, 0.07, 0.07], METAL, segs=4))
gradient(parts[-1], METAL_LO, METAL_HI)
bail = [Vector((math.cos(t) * 0.72, 0, KZ + 1.03 + math.sin(t) * 0.55)) for t in (0, 0.5, 1.0, math.pi / 2, math.pi - 1.0, math.pi - 0.5, math.pi)]
parts.append(tube("Bail", bail, [0.065] * len(bail), METAL, segs=4))
gradient(parts[-1], METAL_LO, METAL_HI)
# spout pointing front-right
parts.append(tube("Spout", [Vector((0.5, -0.5, KZ + 0.5)), Vector((0.8, -0.78, KZ + 0.7)), Vector((0.98, -0.92, KZ + 0.92))],
                  [0.16, 0.12, 0.11], METAL, segs=5))
gradient(parts[-1], METAL_LO, METAL_HI)

# --- goo: domes in the mouth, rolls over the front lip, drips down the belly -------------------
top = KZ + 1.13
balls = [Ball((0, 0, top + 0.03), (0.58, 0.58, 0.16))]
for k in range(4):  # short lip roll over the front (-Y)
    a = -math.pi / 2 - 0.25 + (k - 1.5) * 0.3
    n = Vector((math.cos(a), math.sin(a), 0))
    balls.append(Ball(n * 0.68 + Vector((0, 0, top - 0.04)), (0.15, 0.12, 0.1), rot=frame_quat(Vector((-n.y, n.x, 0)), n, Vector((0, 0, 1)))))


def belly_r(z):
    """kettle radius at height z (kettle-local) from the lathe profile."""
    for (r0, z0), (r1, z1) in zip(KROWS[1:6], KROWS[2:7]):
        if z0 <= z <= z1 and z1 > z0:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return KR


for a, length in ((-math.pi / 2 - 0.25, 0.8), (-math.pi / 2 + 0.2, 0.4)):
    n = Vector((math.cos(a), math.sin(a), 0))
    x = Vector((-n.y, n.x, 0))
    steps = 5
    for s in range(1, steps + 1):
        z = 1.05 - (s / steps) * length
        r = belly_r(z) + 0.02
        w = 0.17 - 0.04 * s / steps
        balls.append(Ball(n * r + Vector((0, 0, KZ + z)), (w, 0.09, 0.15), rot=frame_quat(x, Vector((0, 0, 1)), n)))
    z = 1.05 - length - 0.12
    balls.append(Ball(n * (belly_r(z) + 0.1) + Vector((0, 0, KZ + z)), (0.16, 0.16, 0.19)))
goo = metaball_mesh("KettleGoo", balls, resolution=0.06, tris=260)
print("goo nm", goo["nm"])
paint_goo(goo, lambda co, n: (*mix(GOO, GOO_HI, 0.12 + 0.45 * max(0.0, n.z) ** 2)[:3], 1.0))
parts.append(goo)

finish("ranch_campfire", parts)
