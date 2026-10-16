# ranch_horseshoe_pit: low horseshoe-pit set (Slime Ranch), ~9.6 long (X) x ~3.8 deep x ~1.5 tall.
# Bevelled wood board frame with chunky corner blocks around a closed sand heightfield (ranch_path,
# dug ranch_plaza pits round the stakes), a pewter stake at each end, a ringer lying round the -X
# stake and three chunky horseshoes near the +X stake (two flat, one leaning). cylinder() pos = base.
import math
import random
import bmesh
from mathutils import Matrix, Vector
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, PATH, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_path"], PALETTE["ranch_plaza"]
METAL, ROOF, ROOF_D = PALETTE["ranch_metal"], PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
WOOD_LO = mix(WOOD_D, WOOD, 0.45)
WOOD_HI = mix(WOOD, CREAM, 0.15)
METAL_LO = mix(METAL, CREAM, 0.25)
METAL_HI = mix(METAL, CREAM, 0.6)
parts = []


def pbox(name, size, pos, bot, top, bev=0.08, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


L, D = 8.2, 3.4          # inner box
BT, BH = 0.5, 0.6        # board thickness / height
STAKE_X = 3.0
SAND_Z = 0.42

# --- frame: long boards, end boards, corner blocks ---
for s in (-1, 1):
    parts.append(pbox(f"Long{s}", (L + 2 * BT, BT, BH), (0.04 * s, s * (D / 2 + BT / 2), BH / 2),
                      WOOD_LO, WOOD_HI if s < 0 else WOOD, bev=0.1))
    parts.append(pbox(f"End{s}", (BT, D, BH - 0.05), (s * (L / 2 + BT / 2), 0, (BH - 0.05) / 2),
                      WOOD_LO, WOOD, bev=0.1))
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(pbox(f"Corner{sx}{sy}", (0.8, 0.8, BH + 0.2), (sx * (L / 2 + BT / 2), sy * (D / 2 + BT / 2),
                          (BH + 0.2) / 2), WOOD_D, mix(WOOD, WOOD_HI, 0.5), bev=0.12))
# red painted backstop boards behind each stake (raised end caps)
for s in (-1, 1):
    parts.append(pbox(f"Backstop{s}", (0.45, D + 0.3, 0.55), (s * (L / 2 + BT / 2), 0, BH + 0.1),
                      mix(ROOF_D, ROOF, 0.55), ROOF, bev=0.1))

# --- sand: closed heightfield (grid + extrude down) with dug pits round the stakes ---
NX, NY = 16, 6
rnd = random.Random(4)
bm = bmesh.new()
bmesh.ops.create_grid(bm, x_segments=NX, y_segments=NY, size=0.5)
bmesh.ops.scale(bm, vec=(L + 0.1, D + 0.1, 1), verts=bm.verts)


def pit(x, y):
    return min(1.0, min(math.hypot(x - sx * STAKE_X, y * 1.2) for sx in (-1, 1)) / 1.7)


for v in bm.verts:
    edge = abs(v.co.x) > L / 2 - 1e-3 or abs(v.co.y) > D / 2 - 1e-3
    k = pit(v.co.x, v.co.y)
    v.co.z = SAND_Z + (0 if edge else 0.04 * (rnd.random() - 0.5) - 0.12 * (1 - k * k) + 0.03 * k)
res = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
bmesh.ops.translate(bm, vec=(0, 0, -0.32), verts=[e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)])
for v in bm.verts:
    if v.co.z < SAND_Z - 0.2:
        v.co.z = 0.05
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
lay = bm.loops.layers.color.new("Col")
for f in bm.faces:
    c = f.calc_center_median()
    k = pit(c.x, c.y)
    col = mix(mix(PLAZA, WOOD, 0.4), PATH, min(1.0, k * 1.15))
    for lp in f.loops:
        lp[lay] = (*col[:3], 1.0)
parts.append(obj_from_bm("Sand", bm))

# --- stakes ---
for s in (-1, 1):
    x = s * STAKE_X
    parts.append(cylinder(f"Stake{s}", 0.17, 1.45, (x, 0, 0.2), METAL, segs=8, r_top=0.14))
    gradient(parts[-1], METAL_LO, METAL_HI)
    parts.append(blob(f"StakeCap{s}", 0.2, (x, 0, 1.66), METAL_HI, subdiv=1, squash=(1, 1, 0.7), jitter=0))


# --- horseshoes: U tube (flattened) placed with a matrix ---
def horseshoe(name, M, r=0.72, tr=0.22):
    pts = []
    for k in range(9):              # arc over the top (toe), open toward -y
        a = math.radians(-20 + 220 * k / 8)
        pts.append((r * math.cos(a), r * math.sin(a), 0))
    pts = [(pts[0][0] + 0.02, pts[0][1] - 0.35, 0)] + pts + [(pts[-1][0] - 0.02, pts[-1][1] - 0.35, 0)]
    rads = [tr * 1.15] + [tr] * 9 + [tr * 1.15]   # fat heel calks
    o = tube(name, pts, rads, METAL, segs=6)
    o.data.transform(M @ Matrix.Diagonal((1, 1, 0.6, 1)))
    gradient(o, METAL_LO, METAL_HI)
    return o


def M_at(pos, rz=0.0, rx=0.0, ry=0.0):
    return (Matrix.Translation(pos) @ Matrix.Rotation(math.radians(rz), 4, "Z")
            @ Matrix.Rotation(math.radians(ry), 4, "Y") @ Matrix.Rotation(math.radians(rx), 4, "X"))


# ringer round the -X stake (centre of the arc on the stake), lying on the sand
parts.append(horseshoe("Ringer", M_at((-STAKE_X + 0.05, -0.1, SAND_Z - 0.04), rz=200, rx=4)))
# near the +X stake: two flat, one leaning on the backstop side
parts.append(horseshoe("Shoe1", M_at((STAKE_X - 1.3, -0.7, SAND_Z - 0.02), rz=35, rx=3)))
parts.append(horseshoe("Shoe2", M_at((STAKE_X - 0.9, 0.95, SAND_Z - 0.02), rz=-120, ry=-4)))
parts.append(horseshoe("Shoe3", M_at((STAKE_X + 0.5, -0.9, SAND_Z + 0.35), rz=95, rx=-28)))

# a small goo splat in the +X pit: ranch tie-in
pud = metaball_mesh("GooSplat", [Ball((STAKE_X - 0.6, 0.1, SAND_Z - 0.1), (0.6, 0.45, 0.1)),
                                 Ball((STAKE_X - 0.15, 0.35, SAND_Z - 0.1), (0.24, 0.2, 0.08))],
                    resolution=0.08, tris=120)
parts.append(paint_goo(pud, lambda co, n: mix(GOO, GOO_HI, 0.3 * max(0.0, n.z) ** 4)))

finish("ranch_horseshoe_pit", parts)
