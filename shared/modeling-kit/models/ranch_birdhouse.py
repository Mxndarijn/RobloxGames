# ranch_birdhouse: chunky birdhouse on a wooden post (Slime Ranch), ~7 studs tall.
# Wood body + barn-red gable roof (ridge along Y so the gable + hole face -Y),
# round entry hole (dark-wood inset disc) + perch dowel on -Y, small cream trim on the gable edge.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL = PALETTE["ranch_cream"], PALETTE["ranch_metal"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
FIELD_L, PINK = PALETTE["ranch_field_light"], PALETTE["ranch_pink"]
WOOD_LO = mix(WOOD_D, WOOD, 0.45)
WOOD_HI = mix(WOOD, CREAM, 0.15)
RED_LO = mix(ROOF_D, ROOF, 0.5)
parts = []


def pbox(name, size, pos, bot, top, bev=0.08, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


# --- post on a cross foot ---
PH = 3.9
parts.append(pbox("Post", (0.85, 0.85, PH), (0, 0, PH / 2), WOOD_LO, WOOD, bev=0.1))
for k, (sx, sy) in enumerate(((1.9, 0.6), (0.6, 1.9))):
    parts.append(pbox(f"Foot{k}", (sx, sy, 0.4), (0, 0, 0.2), WOOD_D, WOOD_LO, bev=0.08))
for s in (-1, 1):  # little knee braces under the platform
    parts.append(pbox(f"Knee{s}", (0.3, 0.3, 1.3), (s * 0.75, 0, PH - 0.5), WOOD_LO, WOOD, bev=0.04, rot=(0, s * 40, 0)))
# platform
parts.append(pbox("Deck", (3.0, 2.9, 0.35), (0.05, -0.2, PH + 0.17), WOOD_LO, WOOD_HI, bev=0.08))

# --- house body ---
BW, BD, BH = 2.2, 2.0, 1.9
BZ = PH + 0.35
parts.append(pbox("Body", (BW, BD, BH), (0, 0, BZ + BH / 2), WOOD_LO, WOOD, bev=0.1))
# plank seams: thin darker strips on the front and sides
for i, x in enumerate((-0.55, 0.0, 0.55)):
    parts.append(box(f"Seam{i}", (0.06, 0.04, BH - 0.2), (x, -BD / 2 - 0.01, BZ + BH / 2), WOOD_LO))
# gable front + back: triangle prisms (cylinder with 3 segs, axis along Y)
PITCH = 40
GH = BW / 2 * math.tan(math.radians(PITCH))
bm = bmesh.new()
tri = [bm.verts.new((x, -BD / 2, z)) for x, z in ((-BW / 2, BZ + BH - 0.02), (BW / 2, BZ + BH - 0.02), (0, BZ + BH + GH))]
f = bm.faces.new(tri)
r = bmesh.ops.extrude_face_region(bm, geom=[f])
bmesh.ops.translate(bm, vec=(0, BD, 0), verts=[e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)])
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
gab = obj_from_bm("Gable", bm, WOOD)
gradient(gab, WOOD, WOOD_HI)
parts.append(gab)

# --- roof: two slabs, ridge along Y (gable faces -Y) ---
pitch = PITCH
half = BW / 2 + 0.55
slen = half / math.cos(math.radians(pitch))
ridge_z = BZ + BH + half * math.tan(math.radians(pitch)) - 0.05
for s in (-1, 1):
    cx = s * slen / 2 * math.cos(math.radians(pitch))
    cz = ridge_z - slen / 2 * math.sin(math.radians(pitch))
    parts.append(pbox(f"Roof{s}", (slen + 0.1, BD + 1.1, 0.5), (cx, 0, cz + 0.2), RED_LO, ROOF, bev=0.1,
                      rot=(0, s * pitch, 0)))
parts.append(pbox("Ridge", (0.5, BD + 1.2, 0.45), (0, 0, ridge_z + 0.28), ROOF_D, RED_LO, bev=0.1))

# --- front details on -Y ---
fy = -BD / 2
hz = BZ + BH * 0.62
parts.append(cylinder("HoleRim", 0.54, 0.14, (0, fy + 0.02, hz), CREAM, segs=12, rot=(90, 0, 0)))
parts.append(cylinder("Hole", 0.42, 0.16, (0, fy - 0.0, hz), WOOD_D, segs=12, rot=(90, 0, 0)))
parts.append(cylinder("Perch", 0.1, 0.65, (0, fy, hz - 0.72), WOOD_HI, segs=6, rot=(90, 0, 0)))
parts.append(blob("PerchKnob", 0.13, (0, fy - 0.65, hz - 0.72), WOOD_HI, subdiv=1, jitter=0))
# cream trim strip along the gable edges (small)
for s in (-1, 1):
    tl = BW / 2 / math.cos(math.radians(PITCH))
    parts.append(pbox(f"Trim{s}", (tl, 0.12, 0.18),
                      (s * BW / 4, fy - 0.06, BZ + BH + GH / 2 - 0.1),
                      mix(CREAM, WOOD, 0.25), CREAM, bev=0.03, rot=(0, s * PITCH, 0)))
# tiny goo dish on the deck corner (front-right): pewter bowl + goo cap
dz = BZ
parts.append(cylinder("Dish", 0.3, 0.2, (0.95, -1.05, dz), METAL, segs=8, r_top=0.42))
gradient(parts[-1], mix(METAL, WOOD_D, 0.1), mix(METAL, CREAM, 0.3))
parts.append(blob("DishGoo", 0.36, (0.95, -1.05, dz + 0.2), GOO, subdiv=2, squash=(1, 1, 0.35), jitter=0))
gradient(parts[-1], GOO, mix(GOO, GOO_HI, 0.3))
finish("ranch_birdhouse", parts)
