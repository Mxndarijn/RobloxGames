# ranch_barn_loft: elevated hay-loft barn blockout (Slime Ranch), ~12 x 8 x 11 studs.
# Open lower bay (posts + beams) with ranch_plaza floor pad; loft deck at z~5.0 in ranch_plaza
# (cream banned on big surfaces); wood plank loft walls on 3 sides; open front (-Y) with hay
# spilling and a cream loft-door frame; barn-red gabled roof (shed recipe). Ladder on +X.
# Reads with ranch_shed / plot_building: same gable+slab roof, cream only on small trim.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM = PALETTE["ranch_cream"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
PLAZA = PALETTE["ranch_plaza"]
BUTTER = PALETTE["ranch_butter"]

WOOD_LO = mix(WOOD_D, WOOD, 0.6)
WOOD_HI = mix(WOOD, CREAM, 0.2)
CREAM_LO = mix(CREAM, WOOD, 0.25)
ROOF_LO = mix(ROOF_D, ROOF, 0.6)
ROOF_HI = mix(ROOF, CREAM, 0.15)
PLAZA_LO = mix(PLAZA, WOOD, 0.2)
HAY_LO = mix(BUTTER, WOOD, 0.1)
HAY_HI = mix(BUTTER, CREAM, 0.3)
parts = []


def pbox(name, size, pos, bot, top, bev=0.12, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


# --- footprint / loft heights ---
WX, WY = 5.6, 3.6          # half wall extents (~11.2 x 7.2)
Z_FLOOR = 0.35             # plaza pad thickness
Z_LOFT = 5.0               # loft deck top
WZ = 8.2                   # eave / wall top
RIDGE = 11.0
EAVE_X = 6.4               # roof half-width
RY = 3.75                  # roof half-depth
ANG = math.radians(36)
TH = 0.5

# plaza floor pad (big surface = ranch_plaza, not cream)
parts.append(pbox("Pad", (2 * WX + 1.2, 2 * WY + 1.0, Z_FLOOR), (0, 0, Z_FLOOR / 2),
                  PLAZA_LO, PLAZA, bev=0.15))

# four corner posts (thick, warm wood) + mid posts on long sides for the open bay
POST_W = 0.95
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(pbox(f"Post{sx}{sy}", (POST_W, POST_W, Z_LOFT - Z_FLOOR + 0.1),
                          (sx * (WX - 0.15), sy * (WY - 0.15), Z_FLOOR + (Z_LOFT - Z_FLOOR) / 2),
                          WOOD_LO, WOOD, bev=0.14))
# mid posts on +-X under the loft (bay reads as a shelter)
for sx in (-1, 1):
    parts.append(pbox(f"Mid{sx}", (POST_W * 0.85, POST_W * 0.85, Z_LOFT - Z_FLOOR),
                      (sx * (WX - 0.15), 0, Z_FLOOR + (Z_LOFT - Z_FLOOR) / 2),
                      WOOD_LO, WOOD, bev=0.12))

# cross beams under the loft deck
parts.append(pbox("BeamY", (2 * WX - 0.4, 0.7, 0.7), (0, 0, Z_LOFT - 0.45), WOOD_LO, WOOD, bev=0.1))
for sy in (-1, 1):
    parts.append(pbox(f"BeamX{sy}", (2 * WX - 0.8, 0.65, 0.65),
                      (0, sy * (WY - 0.35), Z_LOFT - 0.45), WOOD_LO, WOOD, bev=0.1))

# loft deck: ranch_plaza (big surface)
parts.append(pbox("Deck", (2 * WX + 0.3, 2 * WY + 0.3, 0.45), (0, 0, Z_LOFT + 0.1),
                  PLAZA_LO, PLAZA, bev=0.1))
# deck plank strips for read (slightly uneven values)
for k in range(5):
    y = -WY + 0.6 + k * (2 * WY - 0.4) / 4
    c = PLAZA if k % 2 else mix(PLAZA, WOOD, 0.12)
    parts.append(pbox(f"Plank{k}", (2 * WX - 0.6, 0.55, 0.12), (0, y, Z_LOFT + 0.38),
                      mix(PLAZA_LO, c, 0.5), c, bev=0))

# loft walls: back (+Y) and sides (+-X), open front (-Y)
# solid core behind planks so turntable doesn't show through
parts.append(box("Core", (2 * WX - 0.6, 2 * WY - 0.5, WZ - Z_LOFT - 0.3),
                 (0, 0.15, Z_LOFT + 0.2 + (WZ - Z_LOFT - 0.3) / 2), WOOD_LO))

# side walls: horizontal lap boards
NC = 3
ch = (WZ - Z_LOFT - 0.35) / NC
for sx in (-1, 1):
    for k in range(NC):
        z = Z_LOFT + 0.4 + ch * (k + 0.5)
        c = WOOD if k % 2 else mix(WOOD, WOOD_HI, 0.35)
        parts.append(pbox(f"Lap{sx}{k}", (0.42, 2 * WY - 1.0, ch - 0.08),
                          (sx * (WX + 0.05), 0.1, z), mix(WOOD_LO, c, 0.5), c, bev=0,
                          rot=(0, sx * -3, 0)))

# back wall: vertical boards
for k, x in enumerate([-4.0, -2.7, -1.35, 0.0, 1.35, 2.7, 4.0]):
    c = WOOD if k % 2 else mix(WOOD, WOOD_HI, 0.35)
    h = WZ - Z_LOFT - 0.4 + 0.06 * ((k * 5) % 3 - 1)
    parts.append(pbox(f"VB{k}", (1.05, 0.42, h), (x, WY + 0.05, Z_LOFT + 0.35 + h / 2),
                      mix(WOOD_LO, c, 0.4), c, bev=0))

# cream corner trim on loft (small accents only)
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(pbox(f"Trim{sx}{sy}", (0.7, 0.7, WZ - Z_LOFT - 0.15),
                          (sx * (WX + 0.08), sy * (WY + 0.05), Z_LOFT + 0.35 + (WZ - Z_LOFT - 0.15) / 2),
                          CREAM_LO, CREAM, bev=0.12))

# front loft opening: cream frame + open bay (hay behind)
fy = -WY
OW, OH = 5.2, 2.6
parts.append(pbox("LoftFrL", (0.55, 0.45, OH + 0.4), (-OW / 2 - 0.2, fy - 0.15, Z_LOFT + 0.5 + (OH + 0.4) / 2),
                  CREAM_LO, CREAM, bev=0.1))
parts.append(pbox("LoftFrR", (0.55, 0.45, OH + 0.4), (OW / 2 + 0.2, fy - 0.15, Z_LOFT + 0.5 + (OH + 0.4) / 2),
                  CREAM_LO, CREAM, bev=0.1))
parts.append(pbox("LoftHdr", (OW + 1.2, 0.45, 0.55), (0, fy - 0.15, Z_LOFT + 0.5 + OH + 0.2),
                  CREAM_LO, CREAM, bev=0.1))
parts.append(pbox("LoftSill", (OW + 0.6, 0.45, 0.35), (0, fy - 0.1, Z_LOFT + 0.42),
                  CREAM_LO, CREAM, bev=0.08))
# half-doors swung open ~22 deg (barn loft doors), kept close to the wall
for sx in (-1, 1):
    parts.append(pbox(f"Door{sx}", (OW / 2 - 0.2, 0.35, OH - 0.25),
                      (sx * (OW / 2 + 0.35), fy - 0.35, Z_LOFT + 0.7 + (OH - 0.25) / 2),
                      ROOF_LO, ROOF, bev=0.08, rot=(0, 0, sx * -22)))

# hay spilling from loft opening (blobs on sill + inside)
parts.append(blob("Hay1", 0.95, (0.3, fy - 0.15, Z_LOFT + 0.9), HAY_HI, subdiv=1, squash=(1.6, 1.0, 0.7), jitter=0.1, seed=3))
parts.append(blob("Hay2", 0.8, (-1.1, fy + 0.05, Z_LOFT + 0.8), HAY_LO, subdiv=1, squash=(1.3, 0.9, 0.6), jitter=0.12, seed=7))
parts.append(blob("Hay3", 0.95, (1.4, fy + 0.3, Z_LOFT + 0.9), HAY_HI, subdiv=1, squash=(1.2, 1.1, 0.65), jitter=0.1, seed=11))
parts.append(blob("HayIn", 1.25, (0, 0.4, Z_LOFT + 1.1), HAY_LO, subdiv=1, squash=(2.2, 1.5, 0.7), jitter=0.08, seed=5))
gradient(parts[-4], HAY_LO, HAY_HI)
gradient(parts[-3], HAY_LO, HAY_HI)
gradient(parts[-2], HAY_LO, HAY_HI)
gradient(parts[-1], HAY_LO, HAY_HI)

# gables (triangular prisms under the roof)
apex = RIDGE - TH / math.cos(ANG) - 0.05
for sy in (-1, 1):
    bm = bmesh.new()
    y0, y1 = sy * (WY - 0.15), sy * (WY + 0.12)
    vs = [bm.verts.new(v) for v in (
        (-WX, y0, WZ - 0.15), (WX, y0, WZ - 0.15), (0, y0, apex),
        (-WX, y1, WZ - 0.15), (WX, y1, WZ - 0.15), (0, y1, apex))]
    bm.faces.new((vs[0], vs[1], vs[2]))
    bm.faces.new((vs[3], vs[5], vs[4]))
    for a, b in ((0, 1), (1, 2), (2, 0)):
        bm.faces.new((vs[a], vs[b], vs[b + 3], vs[a + 3]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    g = obj_from_bm(f"Gable{sy}", bm, WOOD)
    gradient(g, WOOD, WOOD_HI)
    parts.append(g)

# roof: two thick red slabs + shingle courses + cream barges + ridge
run = EAVE_X / math.cos(ANG)
for sx in (-1, 1):
    cx = sx * EAVE_X / 2
    cz = RIDGE - EAVE_X / 2 * math.tan(ANG) - TH / 2 / math.cos(ANG)
    rot = (0, sx * math.degrees(ANG), 0)
    parts.append(pbox(f"Roof{sx}", (run + 0.2, 2 * RY, TH), (cx, 0, cz), ROOF_LO, ROOF, bev=0.12, rot=rot))
    for k in range(2):
        t = (k + 0.5) / 2
        d = run * (1 - t) - run / 2
        px = cx + sx * d * math.cos(ANG) + sx * (TH / 2 + 0.12) * math.sin(ANG)
        pz = cz - d * math.sin(ANG) + (TH / 2 + 0.12) * math.cos(ANG)
        col = mix(ROOF, ROOF_HI, 0.35 + 0.4 * k)
        parts.append(pbox(f"Course{sx}{k}", (run / 2 - 0.3, 2 * RY - 0.35, 0.4),
                          (px, 0, pz - 0.1), mix(ROOF_LO, col, 0.5), col, bev=0.08, rot=rot))
    for sy in (-1, 1):
        parts.append(pbox(f"Barge{sx}{sy}", (run + 0.25, 0.42, 0.7),
                          (cx, sy * (RY + 0.05), cz + 0.05), CREAM_LO, CREAM, bev=0.1, rot=rot))
ridge = box("Ridge", (0.85, 2 * RY + 0.7, 0.85), (0, 0, RIDGE - 0.15), CREAM, rot=(0, 45, 0))
bevel(ridge, 0.14)
gradient(ridge, CREAM_LO, CREAM)
parts.append(ridge)

# ladder on +X side (wood rails + rungs), reaches loft sill
lx = WX + 0.7
for i in range(2):
    parts.append(pbox(f"Rail{i}", (0.28, 0.28, Z_LOFT + 0.6),
                      (lx, -1.0 + i * 1.1, (Z_LOFT + 0.6) / 2), WOOD_LO, WOOD, bev=0.06))
for k in range(6):
    z = 0.55 + k * 0.85
    parts.append(pbox(f"Rung{k}", (0.22, 1.15, 0.2), (lx, -0.45, z), WOOD, WOOD_HI, bev=0))

finish("ranch_barn_loft", parts)
