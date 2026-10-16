# ranch_feed_sacks: pile of plump burlap feed sacks on a little wood pallet (Slime Ranch).
# Sacks = closed lathe profiles (burlap ranch_path/plaza, red printed band, twine tie + tuft),
# squashed and tilted with a matrix. Front sack (-Y, off the pallet) slumps open: its top cap is
# dipped and painted goo, with goo pellets spilling out onto the ground.
import math
import bmesh
from mathutils import Matrix, Vector
from lib import *
from lib.goo import Ball, metaball_mesh, paint_goo

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
PATH, PLAZA, CREAM = PALETTE["ranch_path"], PALETTE["ranch_plaza"], PALETTE["ranch_cream"]
ROOF, ROOF_D, BUTTER = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"], PALETTE["ranch_butter"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
WOOD_LO = mix(WOOD_D, WOOD, 0.45)
WOOD_HI = mix(WOOD, CREAM, 0.15)
SACK_LO, SACK_HI = mix(PLAZA, WOOD, 0.25), PATH
RED_LO = mix(ROOF_D, ROOF, 0.5)
parts = []
SEGS = 12


def pbox(name, size, pos, bot, top, bev=0.08, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


def lathe(name, prof, M, color_fn, seed=0):
    """closed surface of revolution from (r, z) rows (first/last rows capped), then transformed by M.
    color_fn(row_index, local_z, face) -> rgb."""
    rnd = __import__("random").Random(seed)
    bm = bmesh.new()
    rings = []
    for r, z in prof:
        ring = []
        for k in range(SEGS):
            a = k * math.tau / SEGS
            j = 1 + (rnd.random() * 2 - 1) * 0.03
            ring.append(bm.verts.new((math.cos(a) * r * j, math.sin(a) * r * j, z)))
        rings.append(ring)
    rowf = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(SEGS):
            rowf.append((bm.faces.new((a[k], a[(k + 1) % SEGS], b[(k + 1) % SEGS], b[k])), i))
    rowf.append((bm.faces.new(list(reversed(rings[0]))), -1))
    rowf.append((bm.faces.new(rings[-1]), len(prof)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    lay = bm.loops.layers.color.new("Col")
    for f, i in rowf:
        col = color_fn(i, f.calc_center_median().z, f)
        for lp in f.loops:
            lp[lay] = (*col[:3], 1.0)
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return obj_from_bm(name, bm)


H = 2.4
TIED = [(0.0, 0.0), (0.82, 0.06), (1.0, 0.45), (1.04, 0.82), (1.04, 1.06), (0.96, 1.45), (0.72, 1.85),
        (0.3, 2.08), (0.26, 2.2), (0.42, 2.38), (0.36, 2.5), (0.0, 2.52)]
BAND = (2, 3)       # rows printed red (between z 0.45 and 1.45 the middle band row)
TIE = 7             # row with the twine


def sack_col(i, z, f, band=True):
    if i == TIE:
        return BUTTER
    if i >= TIE + 1:
        return mix(PATH, CREAM, 0.2)  # tuft
    if band and i == 3:
        return mix(RED_LO, ROOF, min(1.0, z / H + 0.2))
    t = max(0.0, min(1.0, z / 1.9))
    c = mix(SACK_LO, SACK_HI, t)
    return shade(c, 0.95) if (i % 2) else c


def M_at(pos, sx=1.0, sy=1.0, sz=1.0, rx=0.0, ry=0.0, rz=0.0):
    R = (Matrix.Rotation(math.radians(rz), 4, "Z") @ Matrix.Rotation(math.radians(ry), 4, "Y")
         @ Matrix.Rotation(math.radians(rx), 4, "X"))
    S = Matrix.Diagonal((sx, sy, sz, 1.0))
    return Matrix.Translation(pos) @ R @ S


# --- pallet: 4 deck slats on 3 runners ---
PW, PD, PZ = 4.6, 3.6, 0.75
for i, x in enumerate((-1.6, 0.0, 1.6)):
    parts.append(pbox(f"Runner{i}", (0.6, PD, 0.4), (x, 0, 0.2), WOOD_D, WOOD_LO, bev=0.06))
for i, y in enumerate((-1.35, -0.45, 0.45, 1.35)):
    parts.append(pbox(f"Slat{i}", (PW + (0.1 if i % 2 else 0), 0.75, 0.35), (0.03 * i, y, 0.575),
                      WOOD_LO, shade(WOOD_HI, 1.0 if i % 2 else 0.95), bev=0.06))

# --- standing sacks on the pallet (back) ---
parts.append(lathe("SackA", TIED, M_at((-1.05, 0.55, PZ), 1.0, 0.85, 1.0, rx=4, rz=15), sack_col, seed=1))
parts.append(lathe("SackB", TIED, M_at((1.1, 0.7, PZ), 0.95, 0.8, 0.92, ry=10, rz=-20), sack_col, seed=2))
# --- lying sack across the front of the pallet ---
parts.append(lathe("SackC", TIED, M_at((-1.35, -0.95, PZ + 0.62), 0.8, 0.95, 1.0, ry=88, rz=-6),
                   lambda i, z, f: sack_col(i, z, f), seed=3))

# --- open slumped sack in front, off the pallet (-Y, right) ---
OPEN = [(0.0, 0.0), (0.9, 0.05), (1.08, 0.4), (1.1, 0.72), (1.0, 1.25), (0.88, 1.5),
        (0.95, 1.62), (0.86, 1.66), (0.55, 1.6), (0.0, 1.52)]


def open_col(i, z, f):
    if i >= 7:  # goo surface in the mouth
        return mix(GOO, GOO_HI, 0.15 if i == 7 else 0.3)
    if i in (5, 6):  # rolled-down lip
        return mix(PATH, CREAM, 0.15)
    if i == 2:  # thin printed band (rows 0.4-0.72)
        return mix(RED_LO, ROOF, 0.6)
    c = mix(SACK_LO, SACK_HI, max(0.0, min(1.0, z / 1.5)))
    return shade(c, 0.95) if (i % 2) else c


OM = M_at((1.75, -1.2, 0.5), 1.05, 0.95, 0.72, rx=55, rz=-12)
parts.append(lathe("SackOpen", OPEN, OM, open_col, seed=4))

# goo pellets spilling from the open mouth onto the ground (metaball beads that just touch)
mouth = OM @ Vector((0, 0, 1.55))
lip = OM @ Vector((0, -0.9, 1.5))   # lowest point of the rolled lip (faces -Y, down)
balls = [Ball(mouth + Vector((0, -0.1, 0.0)), (0.62, 0.55, 0.22)), Ball(lip, (0.36, 0.3, 0.2))]
for j in range(1, 6):  # goo tongue sliding from the lip down to the puddle
    t = j / 5
    p = lip.lerp(Vector((1.65, -2.75, 0.08)), t)
    balls.append(Ball(p + Vector((0, 0, 0.1 * math.sin(math.pi * t))), (0.3 + 0.08 * t, 0.3, 0.16)))
spill = [(1.5, -2.6, 0.18, 0.24), (1.95, -2.95, 0.12, 0.2), (1.2, -3.15, 0.1, 0.17),
         (2.35, -2.55, 0.12, 0.17), (1.7, -3.35, 0.08, 0.15)]
pb = [Ball((x, y, 0.0), (0.95, 0.75, 0.12)) for x, y in ((1.6, -2.9),)]
goo = metaball_mesh("GooMouth", balls, resolution=0.12, tris=320)
parts.append(paint_goo(goo, lambda co, n: mix(GOO, GOO_HI, min(0.5, 0.4 * max(0.0, n.z) ** 6))))
puddle = metaball_mesh("GooPuddle", pb, resolution=0.14, tris=160, clamp_z=0.02)
parts.append(paint_goo(puddle, lambda co, n: mix(GOO, GOO_HI, 0.15 * max(0.0, n.z) ** 4)))
for k, (x, y, z, r) in enumerate(spill):
    parts.append(blob(f"Pellet{k}", r, (x, y, z + r * 0.6), GOO if k % 2 else mix(GOO, GOO_HI, 0.35),
                      subdiv=1, squash=(1, 1, 0.8), jitter=0.05, seed=k))

finish("ranch_feed_sacks", parts)
