# ranch_weathervane: chunky farm weathervane (Slime Ranch), ~3.5 wide x ~8 tall.
# Beveled wood pedestal with a little red gable roof cap, pewter rod, compass cross (N/E/S/W arms
# with ball tips), and on top a red arrow (along X so the front view shows its side) with a butter
# feather tail and a goo-drop "slime" rider on the shaft. cylinder() pos = base; rot= in DEGREES.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_metal"], PALETTE["ranch_plaza"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
BUTTER = PALETTE["ranch_butter"]

WOOD_LO = mix(WOOD_D, WOOD, 0.55)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO = mix(METAL, CREAM, 0.2)
METAL_HI = mix(METAL, CREAM, 0.55)
parts = []


def pbox(name, size, pos, bot, top, bev=0.08, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


def slab(name, pts2d, y0, y1, bot, top):
    """closed slab from a 2D outline in the XZ plane, extruded along Y (y0..y1)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y0, z)) for x, z in pts2d]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, y1 - y0, 0), verts=[e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, bot)
    gradient(o, bot, top)
    return o


# --- pedestal: chunky post on a foot, little gable roof cap ---
parts.append(pbox("Foot", (2.2, 2.2, 0.45), (0, 0, 0.22), WOOD_D, WOOD_LO, bev=0.12))
parts.append(pbox("Post", (1.2, 1.2, 3.2), (0, 0, 0.45 + 1.6), WOOD_LO, WOOD_HI, bev=0.14))
parts.append(pbox("Step", (1.6, 1.6, 0.35), (0, 0, 0.6), WOOD_LO, WOOD, bev=0.1))
parts.append(pbox("Band", (1.3, 1.3, 0.2), (0, 0, 3.0), mix(CREAM, WOOD, 0.3), CREAM, bev=0.05))
CAP_Z = 3.65
parts.append(pbox("CapBase", (1.6, 1.6, 0.25), (0, 0, CAP_Z + 0.12), WOOD_LO, WOOD, bev=0.06))
# gable roof (ridge on X) as a triangle prism
RW, RH = 1.05, 0.85
roof = slab("Roof", [(-1.2, CAP_Z + 0.2), (1.2, CAP_Z + 0.2), (0, CAP_Z + 0.25 + RH)], -RW, RW, ROOF_D, ROOF)
parts.append(roof)

# --- rod ---
ROD_Z0 = CAP_Z + 0.25 + RH - 0.1
parts.append(cylinder("Rod", 0.14, 3.6, (0, 0, ROD_Z0), METAL_HI, segs=8))
gradient(parts[-1], METAL_LO, METAL_HI)
parts.append(cylinder("RodCollar", 0.22, 0.22, (0, 0, ROD_Z0), METAL, segs=8))

# --- compass cross ---
CZ = ROD_Z0 + 1.1
for i, (dx, dy) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))):
    L = 1.45
    arm = cylinder(f"Arm{i}", 0.12, L, (0, 0, CZ), METAL, segs=6,
                   rot=(-90 * dy, 90 * dx, 0) if dx else (-90 * dy, 0, 0))
    gradient(arm, METAL_LO, METAL_HI)
    parts.append(arm)
    parts.append(blob(f"Tip{i}", 0.32, (dx * L, dy * L, CZ), mix(BUTTER, CREAM, 0.3), seed=i, subdiv=1, jitter=0.0))
parts.append(blob("Hub", 0.26, (0, 0, CZ), METAL_HI, subdiv=1, jitter=0.0))

# --- arrow on top (along X) ---
AZ = ROD_Z0 + 3.0
parts.append(pbox("Shaft", (3.0, 0.22, 0.3), (0.1, 0, AZ), ROOF_D, ROOF, bev=0.04))
head = slab("Head", [(1.5, AZ - 0.7), (2.6, AZ), (1.5, AZ + 0.7)], -0.15, 0.15, ROOF_D, ROOF)
parts.append(head)
tail = slab("Tail", [(-1.3, AZ - 0.12), (-1.9, AZ - 0.9), (-2.45, AZ - 0.9), (-1.95, AZ),
                     (-2.45, AZ + 0.9), (-1.9, AZ + 0.9), (-1.3, AZ + 0.12)],
            -0.13, 0.13, mix(BUTTER, WOOD, 0.25), BUTTER)
parts.append(tail)
parts.append(cylinder("ArrowPivot", 0.16, 0.35, (0, 0, AZ - 0.3), METAL, segs=8))

# goo drop rider on the shaft
# goo dipped over the shaft: a drape lens wrapping it + one short drip with a fat drop
balls = [Ball((0.55, 0, AZ + 0.06), (0.62, 0.24, 0.32)), Ball((0.5, 0, AZ + 0.26), (0.4, 0.19, 0.16))]
balls += [Ball((0.78, 0, AZ - 0.3), (0.12, 0.12, 0.16)), Ball((0.78, 0, AZ - 0.52), (0.17, 0.17, 0.17))]
goo = metaball_mesh("Rider", balls, resolution=0.07, tris=260)
parts.append(paint_goo(goo, lambda co, n: mix(GOO, GOO_HI, 0.45 * max(0.0, n.z) ** 2)))

finish("ranch_weathervane", parts)
