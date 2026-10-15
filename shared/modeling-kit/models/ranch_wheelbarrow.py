# ranch_wheelbarrow: one-wheel farm barrow (Slime Ranch), ~6.4 long plot/path decor.
# Flared plank bed with cream rim on two wood handles; pewter wheel/axle at +X, grips + legs at -X.
# The bed holds a goo mound: a closed displaced heightfield slab (grid + extrude), not stuck-on blobs.
# Long axis X; front (-Y) shows the side of the bed. cylinder() pos = base; rot=(90,0,0) grows -Y.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_plaza"]
METAL = PALETTE["ranch_metal"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]

WOOD_LO = mix(WOOD_D, WOOD, 0.45)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO, METAL_HI = mix(METAL, WOOD_D, 0.1), mix(METAL, CREAM, 0.4)
RED_LO = mix(ROOF_D, ROOF, 0.5)
parts = []


def pbox(name, size, pos, bot, top, bev=0.1, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


def disc_y(name, r, thick, centre, color, segs=12):
    """Disc in the XZ plane centred on centre (axis along Y)."""
    return cylinder(name, r, thick, (centre[0], centre[1] + thick / 2, centre[2]), color, segs=segs, rot=(90, 0, 0))


# --- bed: floor + four flared walls ---
BL, BW = 3.0, 2.4        # floor footprint
BX = 0.2                 # bed centre x
FZ = 1.55                # floor top
WH = 1.35                # wall height
parts.append(pbox("Floor", (BL, BW, 0.35), (BX, 0, FZ - 0.175), WOOD_LO, WOOD, bev=0.08))
for sy in (-1, 1):
    # side walls lean out 18 deg
    a = 18
    off = math.sin(math.radians(a)) * WH / 2
    parts.append(pbox(f"Side{sy}", (BL + 0.9, 0.4, WH), (BX, sy * (BW / 2 + off), FZ + WH / 2 - 0.05),
                      WOOD_LO, WOOD, bev=0.1, rot=(-sy * a, 0, 0)))
    parts.append(pbox(f"SideRim{sy}", (BL + 1.2, 0.5, 0.28),
                      (BX, sy * (BW / 2 + 2 * off + 0.02), FZ + WH * math.cos(math.radians(a)) - 0.02),
                      mix(CREAM, WOOD, 0.3), CREAM, bev=0.06, rot=(-sy * a, 0, 0)))
for sx, a in ((1, 35), (-1, 15)):
    off = math.sin(math.radians(a)) * WH / 2
    parts.append(pbox(f"End{sx}", (0.4, BW + 0.5, WH), (BX + sx * (BL / 2 + off), 0, FZ + WH / 2 - 0.05),
                      WOOD_LO, WOOD_HI, bev=0.1, rot=(0, sx * a, 0)))
# red painted band on the side walls (one per side, kept inside the rim line)
for sy in (-1, 1):
    a = 18
    off = math.sin(math.radians(a)) * WH * 0.45
    parts.append(pbox(f"Band{sy}", (BL + 0.3, 0.12, 0.42),
                      (BX, sy * (BW / 2 + off + 0.22), FZ + WH * 0.45),
                      RED_LO, ROOF, bev=0.04, rot=(-sy * a, 0, 0)))

# --- goo mound filling the bed: grid heightfield, extruded down into a closed slab ---
GX, GY = 9, 7
gl, gw = BL + 0.7, BW + 0.55
GZ = FZ + WH - 0.45      # rim level of the goo
bm = bmesh.new()
bmesh.ops.create_grid(bm, x_segments=GX, y_segments=GY, size=0.5)
for v in bm.verts:
    v.co.x *= gl
    v.co.y *= gw
f_top = list(bm.faces)
r = bmesh.ops.extrude_face_region(bm, geom=f_top)
down = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
bmesh.ops.translate(bm, vec=(0, 0, -0.9), verts=down)
down_set = set(down)
for v in bm.verts:
    if v in down_set:
        continue
    u, w = v.co.x / (gl / 2), v.co.y / (gw / 2)
    d = max(0.0, 1 - (u * u + w * w)) ** 0.55  # round dome, not a cone
    # lumpy mound, highest a bit toward the handles
    h = 0.9 * d + 0.14 * math.sin(3.1 * u + 1.0) * math.cos(2.3 * w) * d - 0.12 * (1 - d)
    v.co.z = h + 0.08 * (-u) * d
for v in down:
    v.co.x *= 0.82
    v.co.y *= 0.8
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bmesh.ops.translate(bm, vec=(BX, 0, GZ), verts=bm.verts)
layer = bm.loops.layers.color.new("Col")
for f in bm.faces:
    c = f.calc_center_median()
    t = max(0.0, min(1.0, (c.z - GZ - 0.1) / 0.6))
    col = mix(mix(GOO, GOO_HI, 0.12), mix(GOO, GOO_HI, 0.55), t)
    for lp in f.loops:
        lp[layer] = (*col[:3], 1.0)
parts.append(obj_from_bm("GooMound", bm))
for k, (x, y, rr) in enumerate(((0.0, -0.35, 0.22), (0.75, 0.4, 0.16), (-0.6, 0.3, 0.13))):
    parts.append(blob(f"Bub{k}", rr, (BX + x, y, GZ + 0.62 - 0.25 * abs(x)), GOO_HI, subdiv=1,
                      squash=(1, 1, 0.55), jitter=0))
# --- handles: wood tubes from the axle to the grips ---
WX, WZ, WR = 2.6, 1.0, 1.0
GRIP_X, GRIP_Z = -2.75, 2.3
for sy in (-1, 1):
    pts = [(WX - 0.1, sy * 0.62, WZ), (BX + BL / 2, sy * 0.85, FZ - 0.4), (BX - BL / 2, sy * 1.0, FZ - 0.4),
           (GRIP_X + 0.7, sy * 1.15, GRIP_Z - 0.15)]
    parts.append(tube(f"Handle{sy}", pts, [0.22, 0.24, 0.24, 0.22], WOOD, segs=6))
    gradient(parts[-1], WOOD_LO, WOOD)
    parts.append(cylinder(f"Grip{sy}", 0.24, 1.0, (GRIP_X + 0.75, sy * 1.15, GRIP_Z - 0.1), PLAZA, segs=8,
                          rot=(0, -96, 0)))
    gradient(parts[-1], mix(PLAZA, WOOD, 0.3), mix(PLAZA, CREAM, 0.3))
    # leg + foot under the back of the bed
    parts.append(pbox(f"Leg{sy}", (0.42, 0.42, FZ - 0.25), (BX - BL / 2 + 0.2, sy * 1.0, (FZ - 0.25) / 2 + 0.05),
                      WOOD_LO, WOOD, bev=0.08, rot=(0, -8, 0)))
    parts.append(pbox(f"Foot{sy}", (0.7, 0.55, 0.22), (BX - BL / 2 + 0.3, sy * 1.0, 0.11), WOOD_LO, WOOD_LO, bev=0.06))
# cross brace between the legs
parts.append(pbox("LegBrace", (0.32, 2.0, 0.32), (BX - BL / 2 + 0.22, 0, 0.75), WOOD_LO, WOOD, bev=0.06))

# --- wheel: wood disc, pewter tyre band + hub, chunky spokes; axle along Y ---
C = (WX, 0.0, WZ)
axle = 1.75
parts.append(cylinder("Axle", 0.13, axle, (WX, axle / 2, WZ), METAL, segs=8, rot=(90, 0, 0)))
gradient(parts[-1], METAL_LO, METAL_HI)
wheel = disc_y("Wheel", WR - 0.12, 0.38, C, WOOD, segs=14)
bm = bmesh.new()
bm.from_mesh(wheel.data)
lay = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
for f in bm.faces:
    if abs(f.normal.y) > 0.7:
        col = mix(WOOD, PLAZA, 0.4)
    else:
        t = max(0.0, min(1.0, f.calc_center_median().z / (2 * WR)))
        col = mix(WOOD_LO, WOOD, t)
    for lp in f.loops:
        lp[lay] = (*col[:3], 1.0)
bm.to_mesh(wheel.data)
bm.free()
parts.append(wheel)
tyre = disc_y("Tyre", WR, 0.3, C, METAL, segs=14)
gradient(tyre, METAL_LO, METAL_HI)
parts.append(tyre)
parts.append(gradient(disc_y("Hub", 0.3, 0.6, C, METAL, segs=8), METAL_LO, METAL_HI))
for i in range(3):
    a = i * math.pi / 3 + 0.3
    parts.append(pbox(f"Spoke{i}", (1.55, 0.46, 0.2), (WX, 0, WZ), WOOD_LO, WOOD_HI, bev=0,
                      rot=(0, math.degrees(a), 0)))

finish("ranch_wheelbarrow", parts)
