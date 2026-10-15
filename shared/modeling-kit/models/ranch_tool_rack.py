# ranch_tool_rack: freestanding barn tool rack (Slime Ranch), ~6.8 wide x ~7.6 tall plot/barn decor.
# Two posts on splayed feet, plank backboard, cream peg rail + small red roof cap; hung on the
# front (-Y): pitchfork (tines up), shovel (blade down, goo smear) and rake (head up).
# Tool heads are extruded XZ silhouettes in ranch_metal on wood handles.
# cylinder() pos = base; rot=(90,0,0) grows toward -Y.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_plaza"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
METAL = PALETTE["ranch_metal"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]

WOOD_LO = mix(WOOD_D, WOOD, 0.45)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO, METAL_HI = mix(METAL, WOOD_D, 0.1), mix(METAL, CREAM, 0.45)
RED_LO = mix(ROOF_D, ROOF, 0.5)
HANDLE, HANDLE_LO = mix(PLAZA, CREAM, 0.2), mix(WOOD, PLAZA, 0.5)
BOARD, BOARD_LO = mix(ROOF, WOOD, 0.3), mix(ROOF_D, ROOF, 0.4)  # barn-red painted backboard
parts = []


def pbox(name, size, pos, bot, top, bev=0.1, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


def slab(name, pts, y0, t, bot, top):
    """Closed slab from a 2D (x, z) outline, thickness t along Y centred on y0."""
    bm = bmesh.new()
    f = bm.faces.new([bm.verts.new((x, y0 + t / 2, z)) for x, z in pts])
    bmesh.ops.recalc_face_normals(bm, faces=[f])
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    vs = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, -t, 0), verts=vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])  # concave outlines
    o = obj_from_bm(name, bm, top)
    gradient(o, bot, top)
    return o


def rod(name, x, y, z0, z1, r, col_lo, col_hi, segs=6):
    o = cylinder(name, r, z1 - z0, (x, y, z0), col_hi, segs=segs)
    gradient(o, col_lo, col_hi)
    return o


# --- frame: two posts on splayed feet, plank backboard, rails, roof cap ---
PX, PH = 3.0, 7.0
BY = 0.25  # backboard centre y
for sx in (-1, 1):
    parts.append(pbox(f"Post{sx}", (0.85, 0.85, PH), (sx * PX, BY, PH / 2), WOOD_LO, WOOD, bev=0.12))
    parts.append(pbox(f"Foot{sx}", (0.95, 3.0, 0.55), (sx * PX, BY, 0.275), WOOD_LO, mix(WOOD_LO, WOOD, 0.6), bev=0.14))
    parts.append(pbox(f"Brace{sx}", (0.4, 0.4, 1.7), (sx * PX, BY - 0.85, 0.95), WOOD_LO, WOOD, bev=0.08,
                      rot=(-40, 0, 0)))
    parts.append(pbox(f"BraceB{sx}", (0.4, 0.4, 1.7), (sx * PX, BY + 0.85, 0.95), WOOD_LO, WOOD, bev=0.08,
                      rot=(40, 0, 0)))
n = 5
z0, z1 = 1.3, 6.3
ph = (z1 - z0) / n
for k in range(n):
    z = z0 + ph * (k + 0.5)
    c = BOARD if k % 2 == 0 else shade(BOARD, 0.93)
    parts.append(pbox(f"Plank{k}", (2 * PX - 0.3, 0.4, ph - 0.08), (0.03 * (k % 2), BY + 0.05, z),
                      mix(BOARD_LO, c, 0.6), c, bev=0.06))
# solid core behind the planks so the seams don't show the field through
parts.append(box("BoardCore", (2 * PX - 0.5, 0.2, z1 - z0 - 0.1), (0, BY + 0.1, (z0 + z1) / 2), BOARD_LO))
# wood peg rail across the top third (cream here hid the pewter tool heads)
RAIL_Z = 5.35
parts.append(pbox("PegRail", (2 * PX + 0.4, 0.35, 0.55), (0, BY - 0.3, RAIL_Z), WOOD_LO, WOOD, bev=0.08))
# low rail that keeps the handle feet in
parts.append(pbox("FootRail", (2 * PX + 0.4, 0.4, 0.5), (0, BY - 1.25, 0.95), WOOD_LO, WOOD_HI, bev=0.08))
for sx in (-1, 1):
    parts.append(pbox(f"RailArm{sx}", (0.4, 1.3, 0.4), (sx * PX, BY - 0.75, 0.95), WOOD_LO, WOOD, bev=0.06))
# roof cap: top board + two red slopes
parts.append(pbox("Cap", (2 * PX + 1.2, 1.3, 0.35), (0, BY, PH + 0.17), mix(CREAM, WOOD, 0.3), CREAM, bev=0.08))
for sy in (-1, 1):
    parts.append(pbox(f"Roof{sy}", (2 * PX + 1.6, 1.15, 0.28), (0, BY + sy * 0.48, PH + 0.6),
                      RED_LO, ROOF, bev=0.08, rot=(-sy * 28, 0, 0)))
parts.append(pbox("Ridge", (2 * PX + 1.7, 0.4, 0.3), (0, BY, PH + 0.92), RED_LO, ROOF, bev=0.08))

# pegs (pewter knobs) the tools hang from
for k, x in enumerate((-1.9, 0.0, 1.9)):
    parts.append(cylinder(f"Peg{k}", 0.15, 0.6, (x, BY - 0.4, RAIL_Z), METAL, segs=6, rot=(90, 0, 0)))
    gradient(parts[-1], METAL_LO, METAL_HI)

TY = BY - 0.85  # tool plane

# --- pitchfork (x=-1.9): handle down into the foot rail, 4 tines up ---
FX = -1.9
parts.append(rod("ForkHandle", FX, TY, 0.75, 5.0, 0.2, HANDLE_LO, HANDLE))
fork = [(-0.85, 4.85), (0.85, 4.85), (0.85, 6.55), (0.62, 6.55), (0.62, 5.25),
        (0.31, 5.25), (0.31, 6.75), (0.09, 6.75), (0.09, 5.25), (-0.09, 5.25), (-0.09, 6.75),
        (-0.31, 6.75), (-0.31, 5.25), (-0.62, 5.25), (-0.62, 6.55), (-0.85, 6.55)]
fork = [(FX + x, z) for x, z in fork]
parts.append(slab("ForkHead", fork, TY, 0.2, METAL_LO, METAL_HI))
parts.append(rod("ForkCollar", FX, TY, 4.55, 5.0, 0.27, METAL_LO, METAL_HI, segs=8))

# --- shovel (x=0): D grip up top, blade down with a goo smear ---
SX = 0.0
parts.append(rod("ShovelHandle", SX, TY, 2.6, 6.0, 0.2, HANDLE_LO, HANDLE))
parts.append(pbox("GripBar", (0.95, 0.32, 0.3), (SX, TY, 6.7), HANDLE_LO, HANDLE, bev=0.06))
for sx in (-1, 1):
    parts.append(pbox(f"GripSide{sx}", (0.22, 0.28, 0.85), (SX + sx * 0.36, TY, 6.25), HANDLE_LO, HANDLE, bev=0.04,
                      rot=(0, sx * 18, 0)))
parts.append(rod("ShovelCollar", SX, TY, 2.35, 2.9, 0.26, METAL_LO, METAL_HI, segs=8))
blade = [(-0.75, 2.5), (0.75, 2.5), (0.8, 1.25), (0.35, 0.75), (0.0, 0.6), (-0.35, 0.75), (-0.8, 1.25)]
parts.append(slab("Blade", [(SX + x, z) for x, z in blade], TY, 0.18, METAL_LO, METAL_HI))
goo = [(-0.62, 1.2), (-0.35, 1.55), (-0.1, 1.38), (0.2, 1.62), (0.5, 1.45), (0.68, 1.22),
       (0.32, 0.86), (0.0, 0.72), (-0.32, 0.86)]
g = slab("BladeGoo", [(SX + x, z) for x, z in goo], TY - 0.1, 0.06, GOO, mix(GOO, GOO_HI, 0.45))
parts.append(g)
parts.append(blob("GooDrop", 0.13, (SX + 0.02, TY - 0.12, 0.55), GOO, subdiv=1, squash=(0.8, 0.6, 1.2), jitter=0))

# --- rake (x=1.9): head up, 7 teeth pointing up ---
RX = 1.9
parts.append(rod("RakeHandle", RX, TY, 0.75, 5.6, 0.2, HANDLE_LO, HANDLE))
rake = [(-0.95, 5.55), (0.95, 5.55)]
TW = 0.15
for i in range(7):
    xr = 0.95 - i * (1.9 - TW) / 6
    rake += [(xr, 5.85), (xr, 6.4), (xr - TW, 6.4), (xr - TW, 5.85)]
clean = []
for p in rake:
    if not clean or (abs(clean[-1][0] - p[0]) > 1e-4 or abs(clean[-1][1] - p[1]) > 1e-4):
        clean.append(p)
parts.append(slab("RakeHead", [(RX + x, z) for x, z in clean], TY, 0.2, METAL_LO, METAL_HI))
parts.append(rod("RakeCollar", RX, TY, 5.15, 5.6, 0.26, METAL_LO, METAL_HI, segs=8))

finish("ranch_tool_rack", parts)
