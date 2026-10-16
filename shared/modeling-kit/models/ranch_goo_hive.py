# ranch_goo_hive: beehive-style goo hive (Slime Ranch), ~4 wide x ~6.3 tall.
# Straw skep = closed lathe of 6 stacked bulging coil rings (alternating straw values, darker
# binding seams), knob on top, on a short 4-legged wood stand. Small arched entry on -Y at the
# skep foot; glossy goo (lib/goo.py metaballs) oozes out of the entry across the deck and over its
# front edge, and drips run down the coils from a seam. cylinder() pos = base; rot= in DEGREES.
import math
import bmesh
from mathutils import Vector
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, PATH, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_path"], PALETTE["ranch_plaza"]
BUTTER, METAL = PALETTE["ranch_butter"], PALETTE["ranch_metal"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
WOOD_LO = mix(WOOD_D, WOOD, 0.45)
WOOD_HI = mix(WOOD, CREAM, 0.15)
STRAW_LO = mix(PLAZA, WOOD, 0.25)
STRAW_HI = mix(PATH, BUTTER, 0.4)
parts = []
SEGS = 18


def pbox(name, size, pos, bot, top, bev=0.08, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


# --- stand: 4 slightly splayed legs, aprons, plank deck ---
DZ = 2.0            # deck top
DW, DD = 4.0, 3.9
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(pbox(f"Leg{sx}{sy}", (0.55, 0.55, DZ - 0.1), (sx * 1.45, sy * 1.4, (DZ - 0.1) / 2),
                          WOOD_LO, WOOD, bev=0.06, rot=(sy * -4, sx * 4, 0)))
for sy in (-1, 1):
    parts.append(pbox(f"ApronX{sy}", (3.3, 0.35, 0.45), (0, sy * 1.4, DZ - 0.6), WOOD_LO, WOOD, bev=0.05))
for sx in (-1, 1):
    parts.append(pbox(f"ApronY{sx}", (0.35, 3.2, 0.45), (sx * 1.45, 0, DZ - 0.6), WOOD_LO, WOOD, bev=0.05))
for i, x in enumerate((-1.45, -0.48, 0.48, 1.45)):
    parts.append(pbox(f"Plank{i}", (0.92, DD + (0.12 if i % 2 else 0), 0.4), (x, 0.03 * i, DZ - 0.2),
                      WOOD_LO, shade(WOOD_HI, 1.0 if i % 2 else 0.95), bev=0.07))

# --- skep: stacked coil rings (closed lathe) ---
R0, HS = 1.75, 3.5
NR = 6


def env(z):
    """envelope radius of the skep at height z above the deck (flat-ish foot, round dome)."""
    t = max(0.0, min(1.0, z / HS))
    return R0 * max(0.0, 1.0 - t ** 2.4) ** 0.5


prof = []           # (r, z, ring index, is_seam)
for i in range(NR):
    z0 = HS * 0.82 * i / NR
    z1 = HS * 0.82 * (i + 1) / NR
    prof.append((env(z0) * 0.97, z0, i, True))
    prof.append((env((z0 + z1) / 2) * 1.05, (z0 + z1) / 2, i, False))
zc = HS * 0.82
prof.append((env(zc) * 0.97, zc, NR, True))
prof.append((env(zc) * 0.75, zc + 0.28, NR, False))
prof.append((0.42, zc + 0.48, NR + 1, True))     # knob neck
prof.append((0.5, zc + 0.68, NR + 1, False))
prof.append((0.0, zc + 0.82, NR + 1, False))
prof[0] = (prof[0][0] * 1.02, 0.0, 0, True)

bm = bmesh.new()
rings = []
rnd = __import__("random").Random(3)
for r, z, i, seam in prof:
    ring = []
    for k in range(SEGS):
        a = k * math.tau / SEGS
        j = 1 + (rnd.random() * 2 - 1) * 0.015
        ring.append(bm.verts.new((math.cos(a) * r * j, math.sin(a) * r * j, DZ + z)))
    rings.append(ring)
faces = []
for row, (a, b) in enumerate(zip(rings, rings[1:])):
    for k in range(SEGS):
        faces.append((bm.faces.new((a[k], a[(k + 1) % SEGS], b[(k + 1) % SEGS], b[k])), row))
faces.append((bm.faces.new(list(reversed(rings[0]))), -1))
bmesh.ops.remove_doubles(bm, verts=rings[-1], dist=1e-4)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
lay = bm.loops.layers.color.new("Col")
for f, row in faces:
    if not f.is_valid:
        continue
    c = f.calc_center_median()
    t = max(0.0, min(1.0, (c.z - DZ) / (HS + 0.8)))
    ri = prof[row][2] if row >= 0 else 0
    col = mix(STRAW_LO, STRAW_HI, 0.25 + 0.75 * t)
    if ri % 2:
        col = shade(col, 0.94)
    if row >= 0 and (prof[row][3] or prof[row + 1][3]) and ri <= NR:
        # faces touching a seam: half toward the darker binding
        col = mix(col, WOOD, 0.25)
    if ri >= NR + 1:
        col = mix(WOOD, WOOD_HI, 0.5)
    for lp in f.loops:
        lp[lay] = (*col[:3], 1.0)
skep = obj_from_bm("Skep", bm)
parts.append(skep)

# --- arched entry on -Y at the skep foot: dark wood arch + lighter frame ---
EW, EH = 1.0, 0.85
ey = -env(0.3) * 1.02
for nm, w, h, dy, col_lo, col_hi in (("EntryFrame", EW + 0.36, EH + 0.18, 0.0, WOOD, WOOD_HI),
                                     ("Entry", EW, EH, -0.12, WOOD_D, mix(WOOD_D, WOOD, 0.3))):
    bm = bmesh.new()
    pts = [(-w / 2, 0.0), (w / 2, 0.0)]
    for k in range(9):
        a = math.pi * k / 8
        pts.append((w / 2 * math.cos(a), h - w / 2 + w / 2 * math.sin(a)))
    vs = [bm.verts.new((x, ey + dy + 0.45, DZ + 0.02 + z)) for x, z in pts]
    f = bm.faces.new(vs)
    res = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, -0.6, 0), verts=[e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(nm, bm, col_lo)
    gradient(o, col_lo, col_hi)
    parts.append(o)
ENTRY_FRONT = ey - 0.27

# --- goo: ooze from the entry across the deck and over the front edge, drips down the coils ---
balls = []
# tongue out of the entry
for j in range(7):
    t = j / 6
    y = ENTRY_FRONT + 0.15 - t * (ENTRY_FRONT + DD / 2 - 0.05)
    balls.append(Ball((0.05 + 0.15 * math.sin(t * 2.5), y, DZ + 0.06), (0.5 + 0.12 * t, 0.42, 0.14)))
balls.append(Ball((0.0, ENTRY_FRONT + 0.2, DZ + 0.22), (0.42, 0.3, 0.2)))   # bulge in the doorway
# over the deck front edge and down the plank face
edge_y = -DD / 2
for x0, ln in ((0.15, 0.6), (-0.45, 0.3)):
    balls.append(Ball((x0, edge_y + 0.05, DZ - 0.02), (0.32, 0.22, 0.14)))
    steps = 3
    for j in range(steps + 1):
        t = j / steps
        balls.append(Ball((x0, edge_y - 0.02, DZ - 0.1 - ln * t), (0.2 * (1 - 0.3 * t), 0.1, 0.18)))
    balls.append(Ball((x0, edge_y - 0.08, DZ - 0.12 - ln), (0.17, 0.15, 0.17)))
# goo collar: a wavy band of flat lenses round the whole skep on a seam, drips hanging from it


def surf(ang, z, off=0.0):
    """point + outward normal on the skep envelope (ang 0 = -Y front)."""
    a = math.radians(ang - 90)
    n_h = Vector((math.cos(a), math.sin(a), 0))
    drdz = (env(z + 0.05) - env(z - 0.05)) / 0.1
    n = (n_h - Vector((0, 0, drdz))).normalized()
    return n_h * env(z) + Vector((0, 0, DZ + z)) + n * off, n, n_h


CZ = HS * 0.82 * 5 / NR
NC = 18
for k in range(NC):
    ang = k * 360 / NC
    z = CZ + 0.12 * math.sin(k * 2.3)
    p, n, n_h = surf(ang, z, -0.02)
    lat = n.cross(Vector((0, 0, 1))).normalized()
    up = lat.cross(n)
    balls.append(Ball(p, (0.45, 0.24, 0.12), rot=frame_quat(lat, up, n)))
for ang, ln in ((-30, 0.95), (35, 0.65), (110, 0.8), (200, 0.9), (265, 0.6)):
    steps = 4
    for j in range(1, steps + 1):
        z = CZ - ln * j / steps
        p, n, n_h = surf(ang, z, -0.03)
        lat = n.cross(Vector((0, 0, 1))).normalized()
        down = n.cross(lat)
        balls.append(Ball(p, (0.18, 0.22 * (1 - 0.3 * j / steps), 0.11), rot=frame_quat(down, lat, n)))
    p, n, n_h = surf(ang, CZ - ln - 0.06, 0.02)
    balls.append(Ball(p, (0.17, 0.17, 0.17)))
goo = metaball_mesh("Goo", balls, resolution=0.09, tris=520)
parts.append(paint_goo(goo, lambda co, n: mix(GOO, GOO_HI, min(0.5, 0.45 * max(0.0, n.z) ** 6))))
# goo puddle under the front edge
pud = metaball_mesh("Puddle", [Ball((0.15, -DD / 2 - 0.25, 0.0), (0.9, 0.6, 0.1))], resolution=0.12, tris=120,
                    clamp_z=0.02)
parts.append(paint_goo(pud, lambda co, n: mix(GOO, GOO_HI, 0.25 * max(0.0, n.z) ** 4)))

finish("ranch_goo_hive", parts)
