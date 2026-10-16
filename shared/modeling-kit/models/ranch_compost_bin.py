# ranch_compost_bin: slatted wood compost bin (Slime Ranch), ~5 wide x ~3.4 tall.
# Four corner posts, horizontal slats with gaps on 3 sides, a lower front (two boards) so the heap
# shows from the front, a lid board leaning on the back. Inside: a heightfield heap of compost
# (dark mixed soil + peel/leaf bits) with a goo patch oozing over the front board into a puddle.
# A small pitchfork leans on the right side. cylinder() pos = base; rot= in DEGREES.
import math
import bmesh
from mathutils import Matrix
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_metal"], PALETTE["ranch_plaza"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
FIELD_L, FIELD_D = PALETTE["ranch_field_light"], PALETTE["ranch_field_dark"]
BUTTER, PINK, PATH = PALETTE["ranch_butter"], PALETTE["ranch_pink"], PALETTE["ranch_path"]

WOOD_LO = mix(WOOD_D, WOOD, 0.55)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO = mix(METAL, CREAM, 0.2)
METAL_HI = mix(METAL, CREAM, 0.55)
SOIL = mix(WOOD_D, PLAZA, 0.25)
SOIL_HI = mix(WOOD, PLAZA, 0.5)
parts = []

W, D, H = 4.6, 4.0, 3.0      # outer footprint, height of the back/side walls
FRONT_H = 1.6                 # front boards stop low so the heap shows
P = 0.55                      # post size


def pbox(name, size, pos, bot, top, bev=0.08, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


# --- posts ---
for sx in (-1, 1):
    for sy in (-1, 1):
        ph = H + 0.3
        parts.append(pbox(f"Post{sx}{sy}", (P, P, ph), (sx * (W - P) / 2, sy * (D - P) / 2, ph / 2),
                          WOOD_D, WOOD_LO, bev=0.1))

# --- slats: back + sides full height, front low ---
SL_H, GAP = 0.5, 0.12
SL_T = 0.22
rnd = rng(3)
n = int(H / (SL_H + GAP))
for i in range(n):
    z = 0.15 + i * (SL_H + GAP) + SL_H / 2
    t = z / H
    lo, hi = mix(WOOD_LO, WOOD, t), mix(WOOD, WOOD_HI, t)
    tilt = (rnd.random() - 0.5) * 3
    parts.append(pbox(f"Back{i}", (W - P - 0.05, SL_T, SL_H), (0, (D - P) / 2 + 0.05, z), lo, hi, bev=0.06, rot=(0, tilt, 0)))
    for sx in (-1, 1):
        parts.append(pbox(f"Side{sx}_{i}", (SL_T, D - P - 0.05, SL_H), (sx * ((W - P) / 2 + 0.05), 0, z), lo, hi,
                          bev=0.06, rot=(tilt, 0, 0)))
    if z + SL_H / 2 <= FRONT_H + 0.2:
        parts.append(pbox(f"Front{i}", (W - P - 0.05, SL_T, SL_H), (0, -(D - P) / 2 - 0.05, z), lo, hi, bev=0.06, rot=(0, -tilt, 0)))
# floor board so the inside isn't open to the ground
parts.append(pbox("Floor", (W - P, D - P, 0.15), (0, 0, 0.08), WOOD_D, WOOD_LO, bev=0))

# --- compost heap: grid heightfield, extruded down to a flat bottom (closed) ---
IX, IY = (W - P) / 2 - 0.2, (D - P) / 2 - 0.2
HB, HT = 0.3, 2.25    # heap bottom / peak height
N = 10
HEDGE, HPEAK = 1.35, 3.1   # heap height at the walls / at the peak


def heap_h(x, y):
    u, v = x / IX, y / IY
    r = min(1.0, math.hypot(u * 0.95, (v - 0.25) * 1.05))
    h = HEDGE + (HPEAK - HEDGE) * (1 - r * r) ** 0.7
    # lumpy, forked-over look: two noise octaves, strongest away from the walls
    h += (0.16 * math.sin(4.3 * u + 1.3) * math.cos(3.7 * v + 0.4) + 0.09 * math.sin(9.1 * u - 2.0 * v)) * (1 - r * 0.6)
    return h + 0.12 * goo_w(x, y)


def goo_w(x, y):
    """goo patch weight (0..1): a tongue running from the heap toward the front lip at x=GX."""
    dx = (x - GX) / (0.5 + 0.2 * max(0.0, -(y / IY)))
    dy = (y - (-IY + 0.35)) / 0.95
    return max(0.0, 1 - dx * dx - dy * dy)


GX = 0.6
bm = bmesh.new()
grid = []
for j in range(N + 1):
    row = []
    for i in range(N + 1):
        u, v = i / N * 2 - 1, j / N * 2 - 1
        x, y = u * IX, v * IY
        # peak a bit back of centre so the front slope faces the camera
        row.append(bm.verts.new((x, y, heap_h(x, y))))
    grid.append(row)
for j in range(N):
    for i in range(N):
        bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
top_faces = list(bm.faces)
r = bmesh.ops.extrude_face_region(bm, geom=top_faces)
for e in r["geom"]:
    if isinstance(e, bmesh.types.BMVert):
        e.co.z = HB
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
layer = bm.loops.layers.color.new("Col")
for f in bm.faces:
    c = f.calc_center_median()
    t = max(0.0, min(1.0, (c.z - HEDGE) / (HPEAK - HEDGE)))
    col = mix(SOIL, SOIL_HI, t * 0.8)
    k = (int((c.x + 5) * 2.3) * 7 + int((c.y + 5) * 2.1) * 3) % 11
    gw = goo_w(c.x, c.y)
    if gw > 0.08 and f.normal.z > 0.2:
        col = mix(GOO, GOO_HI, 0.1 + 0.3 * gw)
    elif f.normal.z > 0.3:
        if k == 0:
            col = mix(col, FIELD_D, 0.55)         # leaf bits, kept soft so they don't patchwork
    for lp in f.loops:
        lp[layer] = (*col[:3], 1.0)
heap = obj_from_bm("Heap", bm)
parts.append(heap)

# a few chunky veg scraps on top (leaf blobs + a pink peel)
for k, (x, y, c) in enumerate(((-0.9, 0.2, FIELD_L), (1.3, 0.3, FIELD_D), (0.2, 0.9, PINK), (-0.3, -0.9, BUTTER))):
    z = heap_h(x, y) - 0.05
    parts.append(blob(f"Scrap{k}", 0.32, (x, y, z), c, seed=k, subdiv=1, squash=(1.2, 0.9, 0.45), jitter=0.1))

# --- goo oozing over the front board into a puddle ---
FY = -(D - P) / 2 - 0.05 - SL_T / 2      # outer face of the front boards
FT = 0.15 + 2 * (SL_H + GAP)             # top of the front boards
balls = []
balls.append(Ball((GX, FY + 0.08, FT + 0.04), (0.62, 0.22, 0.15)))   # roll over the lip
for k, z in enumerate((FT - 0.28, FT - 0.55)):   # one short run down the board face
    balls.append(Ball((GX + 0.04 * k, FY - 0.02, z), (0.3 - 0.06 * k, 0.1, 0.2)))
balls.append(Ball((GX + 0.08, FY - 0.06, FT - 0.85), (0.22, 0.19, 0.21)))
goo = metaball_mesh("Ooze", balls, resolution=0.08, tris=320)
parts.append(paint_goo(goo, lambda co, n: mix(GOO, GOO_HI, 0.12 + 0.35 * max(0.0, n.z) ** 3)))
pud = metaball_mesh("Puddle", [Ball((GX + 0.3, FY - 0.7, 0.02), (1.2, 0.7, 0.07)),
                               Ball((GX - 0.4, FY - 0.9, 0.02), (0.6, 0.5, 0.06))], resolution=0.1, tris=160, clamp_z=0.02)
parts.append(paint_goo(pud, lambda co, n: mix(GOO, GOO_HI, 0.35)))

# --- pitchfork leaning on the right side ---
FX = W / 2 + 0.25
lean = 18
fork_parts = []
L = 4.2
handle = cylinder("ForkHandle", 0.09, L, (0, 0, 0), WOOD_HI, segs=6)
gradient(handle, WOOD, WOOD_HI)
head = pbox("ForkHead", (0.8, 0.14, 0.14), (0, 0, -0.05), METAL, METAL_HI, bev=0.03)
tines = [cylinder(f"Tine{k}", 0.05, 0.75, (dx, 0, -0.05), METAL_HI, segs=5, rot=(180, 0, 0))
         for k, dx in enumerate((-0.33, -0.11, 0.11, 0.33))]
for o in [handle, head] + tines:
    gradient(o, METAL_LO, METAL_HI) if o is not handle else None
    # tines down, handle up: fork rests on the ground at the tines, top leans on the bin wall
    M = Matrix.Translation((FX + 0.35, -0.6, 0.78)) @ Matrix.Rotation(math.radians(-lean), 4, "Y") \
        @ Matrix.Rotation(math.radians(90), 4, "Z")
    o.data.transform(M)
    parts.append(o)

finish("ranch_compost_bin", parts)
