# ranch_shed: small modular barn shed (Slime Ranch), ~10 x 8 x 9 studs. Gable end with the
# big door faces -Y (front); ridge runs along Y. Plank walls in ranch_wood with cream corner
# trim, barn-red gabled roof with cream ridge cap and barge boards, red door with cream X brace.
import math
import bmesh
from lib import *

# Slime Ranch palette (theme table, sRGB 0-255)
WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM = PALETTE["ranch_cream"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]

WOOD_LO = mix(WOOD_D, WOOD, 0.6)    # r04: lifted (was 0.4), shadow side went brown in the roblox look
WOOD_HI = mix(WOOD, CREAM, 0.2)
CREAM_LO = mix(CREAM, WOOD, 0.25)
ROOF_LO = mix(ROOF_D, ROOF, 0.6)
ROOF_HI = mix(ROOF, CREAM, 0.15)
parts = []


def pbox(name, size, pos, bot, top, bev=0.12, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


WX, WY = 4.2, 3.5          # half extents of the wall box
Z0, WZ = 0.5, 5.2          # sill top, eave (wall top)
RIDGE = 9.0                # top of the roof slabs at the ridge
EAVE_X = 5.0               # roof reaches x = +-5 (10 wide)
RY = 3.85                  # roof half depth (~8 deep with the door and step)
ANG = math.radians(38)
TH = 0.5                   # roof slab thickness

# sill / base beam and wall core
parts.append(pbox("Sill", (2 * WX + 0.5, 2 * WY + 0.5, Z0), (0, 0, Z0 / 2), mix(WOOD_D, WOOD, 0.3), WOOD_LO, bev=0.15))
parts.append(box("Core", (2 * WX, 2 * WY, WZ - Z0 + 0.1), (0, 0, (WZ + Z0) / 2), WOOD_LO))

# side walls (+-X): horizontal lap boards, slightly uneven
NC = 4
ch = (WZ - Z0) / NC
for sx in (-1, 1):
    for k in range(NC):
        z = Z0 + ch * (k + 0.5)
        c = WOOD if k % 2 else mix(WOOD, WOOD_HI, 0.4)
        parts.append(pbox(f"Lap{sx}{k}", (0.45, 2 * WY - 0.7, ch - 0.06), (sx * (WX + 0.02), 0.03 * ((k % 3) - 1), z),
                          mix(WOOD_LO, c, 0.5), c, bev=0.1, rot=(0, sx * -4, 0)))

# front/back walls: vertical boards (front ones beside the door)
for sy in (-1, 1):
    xs = [-3.25, -2.45, 2.45, 3.25] if sy < 0 else [-3.25, -2.45, -1.65, -0.85, 0.0, 0.85, 1.65, 2.45, 3.25]
    for k, x in enumerate(xs):
        c = WOOD if k % 2 else mix(WOOD, WOOD_HI, 0.4)
        h = WZ - Z0 - 0.05 + 0.08 * ((k * 7) % 3 - 1)
        parts.append(pbox(f"VB{sy}{k}", (0.78, 0.45, h), (x, sy * (WY + 0.02), Z0 + h / 2), mix(WOOD_LO, c, 0.4), c, bev=0.1 if sy < 0 and abs(x) > 3 else 0))

# cream corner posts
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(pbox(f"Corner{sx}{sy}", (0.85, 0.85, WZ - Z0 + 0.15), (sx * (WX + 0.05), sy * (WY + 0.05), (WZ + Z0 + 0.15) / 2),
                          CREAM_LO, CREAM, bev=0.15))
# cream eave rail on the side walls
for sx in (-1, 1):
    parts.append(pbox(f"Rail{sx}", (0.5, 2 * WY + 0.6, 0.5), (sx * (WX + 0.12), 0, WZ - 0.15), CREAM_LO, CREAM, bev=0))

# side windows: cream frame, darker shutter panel, cream cross
for sx in (-1, 1):
    x = sx * (WX + 0.2)
    parts.append(pbox(f"WinFr{sx}", (0.4, 2.4, 2.0), (x, 0.2, 3.0), CREAM_LO, CREAM, bev=0.12))
    parts.append(pbox(f"Win{sx}", (0.4, 1.8, 1.4), (x + sx * 0.1, 0.2, 3.0), WOOD_D, WOOD_LO, bev=0))
    parts.append(box(f"WinV{sx}", (0.4, 0.3, 1.4), (x + sx * 0.14, 0.2, 3.0), CREAM))
    parts.append(box(f"WinH{sx}", (0.4, 1.8, 0.3), (x + sx * 0.14, 0.2, 3.0), CREAM))

# gables: triangular prisms under the roof, front and back
apex = RIDGE - TH / math.cos(ANG) - 0.05
for sy in (-1, 1):
    bm = bmesh.new()
    y0, y1 = sy * (WY - 0.2), sy * (WY + 0.1)
    vs = [bm.verts.new(v) for v in ((-WX, y0, WZ - 0.2), (WX, y0, WZ - 0.2), (0, y0, apex),
                                    (-WX, y1, WZ - 0.2), (WX, y1, WZ - 0.2), (0, y1, apex))]
    bm.faces.new((vs[0], vs[1], vs[2])); bm.faces.new((vs[3], vs[5], vs[4]))
    for a, b in ((0, 1), (1, 2), (2, 0)):
        bm.faces.new((vs[a], vs[b], vs[b + 3], vs[a + 3]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    g = obj_from_bm(f"Gable{sy}", bm, WOOD)
    gradient(g, WOOD, WOOD_HI)
    parts.append(g)
    # hayloft window: cream frame, darker wood panel
    parts.append(pbox(f"LoftFr{sy}", (1.9, 0.4, 1.7), (0, sy * (WY + 0.2), 6.6), CREAM_LO, CREAM, bev=0.12))
    parts.append(pbox(f"Loft{sy}", (1.2, 0.4, 1.0), (0, sy * (WY + 0.3), 6.6), WOOD_D, WOOD_LO, bev=0))

# roof: two thick red slabs, shingle courses, cream barge boards and ridge cap
run = EAVE_X / math.cos(ANG)
for sx in (-1, 1):
    cx = sx * EAVE_X / 2
    cz = RIDGE - EAVE_X / 2 * math.tan(ANG) - TH / 2 / math.cos(ANG)
    rot = (0, sx * math.degrees(ANG), 0)
    s = pbox(f"Roof{sx}", (run + 0.2, 2 * RY, TH), (cx, 0, cz), ROOF_LO, ROOF, bev=0.12, rot=rot)
    parts.append(s)
    for k in range(3):   # shingle courses: raised strips, lighter toward the ridge
        t = (k + 0.5) / 3
        d = run * (1 - t) - run / 2               # distance along the slope from the slab centre
        px = cx + sx * d * math.cos(ANG) + sx * (TH / 2 + 0.12) * math.sin(ANG)
        pz = cz - d * math.sin(ANG) + (TH / 2 + 0.12) * math.cos(ANG)
        col = mix(ROOF, ROOF_HI, 0.3 + 0.35 * k)
        parts.append(pbox(f"Course{sx}{k}", (run / 3 - 0.25, 2 * RY - 0.3, 0.42), (px, 0, pz - 0.12), mix(ROOF_LO, col, 0.5), col, bev=0.1, rot=rot))
    for sy in (-1, 1):   # cream barge boards along the gable edges
        parts.append(pbox(f"Barge{sx}{sy}", (run + 0.3, 0.45, 0.75), (cx, sy * (RY + 0.05), cz + 0.05), CREAM_LO, CREAM, bev=0.12, rot=rot))
ridge = box("Ridge", (0.9, 2 * RY + 0.8, 0.9), (0, 0, RIDGE - 0.2), CREAM, rot=(0, 45, 0))
bevel(ridge, 0.15)
gradient(ridge, CREAM_LO, CREAM)
parts.append(ridge)

# big door: red vertical planks, cream frame and X brace
DW, DH = 3.9, 4.0
fy = -WY
for k in range(4):
    x = -DW / 2 + DW / 8 + k * DW / 4
    h = DH - 0.05 * (k % 2)
    parts.append(pbox(f"Door{k}", (DW / 4 - 0.05, 0.45, h), (x, fy - 0.12, Z0 + h / 2), ROOF_LO, ROOF, bev=0))
for sx in (-1, 1):
    parts.append(pbox(f"Jamb{sx}", (0.55, 0.45, DH + 0.3), (sx * (DW / 2 + 0.25), fy - 0.25, Z0 + (DH + 0.3) / 2), CREAM_LO, CREAM, bev=0.12))
parts.append(pbox("Header", (DW + 1.05, 0.45, 0.55), (0, fy - 0.25, Z0 + DH + 0.2), CREAM_LO, CREAM, bev=0.12))
parts.append(pbox("RailBot", (DW, 0.42, 0.5), (0, fy - 0.33, Z0 + 0.3), CREAM_LO, CREAM, bev=0))
parts.append(pbox("RailTop", (DW, 0.42, 0.5), (0, fy - 0.33, Z0 + DH - 0.3), CREAM_LO, CREAM, bev=0))
dl = math.hypot(DW, DH - 0.6) - 0.3
da = math.degrees(math.atan2(DH - 0.6, DW))
for sx in (-1, 1):
    parts.append(pbox(f"Brace{sx}", (dl, 0.42, 0.5), (0, fy - 0.36, Z0 + DH / 2), CREAM_LO, CREAM, bev=0, rot=(0, sx * da, 0)))
# ramp-ish door step
parts.append(pbox("Step", (DW + 1.2, 0.7, 0.42), (0, fy - 0.45, 0.21), WOOD_LO, WOOD, bev=0))

finish("ranch_shed", parts)
