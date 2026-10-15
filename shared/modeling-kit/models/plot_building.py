# plot_building: storybook cottage behind each plot (replaces v17 plot_building, 27 x 17.2 x 14.6 studs).
# Front (door) faces -Y (= +Z in Roblox, as Detail.luau expects). Fixed by the game's dressing:
#   wall front face at y = -5.5; sign board 7 x 1.5 centred at x 0, z 8.3 (keep that wall clear);
#   flower boxes under windows centred x = +-7.5, top at z ~3.95 -> window sills at z 4.0.
# Tinted mix(plotAccent, white, 0.3..0.45) in game: colours here are mostly about value contrast.
import math
from lib import *

PLASTER, PLASTER_D = rgb(250, 242, 224), rgb(222, 208, 186)
STONE = rgb(170, 164, 158)
TIMBER, TIMBER_D = rgb(132, 92, 64), rgb(104, 72, 52)
ROOF, ROOF_D, ROOF_L = rgb(214, 104, 90), rgb(170, 76, 70), rgb(236, 138, 116)
TRIM = rgb(252, 250, 244)
GLASS = rgb(150, 206, 236)
DOOR = rgb(150, 98, 62)
parts = []

WX, WY, WZ = 11.0, 5.5, 10.0  # half width, half depth, eave height of the walls
RIDGE, EAVE_Y, EAVE_X = 16.6, 7.0, 13.5

# foundation + walls
f = box("Found", (2 * WX + 0.8, 2 * WY + 0.8, 0.9), (0, 0, 0.45), STONE)
bevel(f, 0.12)
gradient(f, shade(STONE, 0.85), STONE)
parts.append(f)
w = box("Walls", (2 * WX, 2 * WY, WZ - 0.6), (0, 0, 0.6 + (WZ - 0.6) / 2), PLASTER)
gradient(w, PLASTER_D, PLASTER)
parts.append(w)
# gables (triangular prisms on +-X ends, under the roof)
import bmesh
for sx in (-1, 1):
    bm = bmesh.new()
    x0, x1 = sx * (WX - 0.4), sx * WX
    vs = [bm.verts.new(v) for v in ((x0, -WY, WZ), (x0, WY, WZ), (x0, 0, RIDGE - 0.4),
                                    (x1, -WY, WZ), (x1, WY, WZ), (x1, 0, RIDGE - 0.4))]
    bm.faces.new((vs[0], vs[1], vs[2])); bm.faces.new((vs[3], vs[5], vs[4]))
    for a, b in ((0, 1), (1, 2), (2, 0)):
        bm.faces.new((vs[a], vs[b], vs[b + 3], vs[a + 3]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    g = obj_from_bm(f"Gable{sx}", bm, PLASTER)
    parts.append(g)
# timber frame: corner posts, top plate, gable cross beams
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(box(f"Post{sx}{sy}", (0.8, 0.8, WZ - 0.4), (sx * (WX - 0.15), sy * (WY - 0.15), 0.6 + (WZ - 0.4) / 2), TIMBER))
    parts.append(box(f"GBeam{sx}", (0.5, 2 * WY, 0.5), (sx * (WX + 0.05), 0, WZ + 0.1), TIMBER))
    parts.append(box(f"GPost{sx}", (0.5, 0.5, RIDGE - WZ - 0.6), (sx * (WX + 0.05), 0, (WZ + RIDGE - 0.6) / 2), TIMBER))
parts.append(box("Plate", (2 * WX + 0.3, 0.5, 0.6), (0, -WY - 0.12, WZ - 0.1), TIMBER))
parts.append(box("PlateB", (2 * WX + 0.3, 0.5, 0.6), (0, WY + 0.12, WZ - 0.1), TIMBER))

# roof: two thick slabs with a lighter fascia edge, shingle courses as stepped strips
slope = math.atan2(RIDGE - (WZ - 0.4), EAVE_Y)
L = math.hypot(EAVE_Y, RIDGE - (WZ - 0.4)) + 0.3
for sy in (-1, 1):
    ang = -math.degrees(slope) * sy
    cy, cz = sy * EAVE_Y / 2, (RIDGE + WZ - 0.4) / 2
    s = box(f"Roof{sy}", (2 * EAVE_X, L, 0.55), (0, cy, cz), ROOF, rot=(ang, 0, 0))
    gradient(s, ROOF_D, ROOF)
    parts.append(s)
    for k in range(4):  # shingle courses: thin strips proud of the slab, lighter on their top
        t = (k + 0.5) / 4
        yy = sy * EAVE_Y * (1 - t) * 0.98
        zz = (WZ - 0.4) + (RIDGE - (WZ - 0.4)) * t + 0.38
        c = box(f"Course{sy}{k}", (2 * EAVE_X - 0.3, L / 4 - 0.25, 0.22), (0, yy, zz), mix(ROOF, ROOF_L, 0.5 + 0.15 * k), rot=(ang, 0, 0))
        parts.append(c)
    for sx in (-1, 1):  # white bargeboards along the gable edges: the storybook outline
        parts.append(box(f"Barge{sy}{sx}", (0.35, L + 0.2, 0.8), (sx * (EAVE_X + 0.05), cy, cz + 0.05), TRIM, rot=(ang, 0, 0)))
ridge = cylinder("Ridge", 0.42, 2 * EAVE_X + 0.2, (-EAVE_X - 0.1, 0, RIDGE + 0.05), ROOF_D, segs=6, rot=(0, 90, 0))
parts.append(ridge)
# chimney (stays under the old 17.2 height)
ch = box("Chimney", (1.6, 1.6, 5.0), (7.0, 2.6, 14.4), STONE)
gradient(ch, shade(STONE, 0.8), STONE)
parts.append(ch)
parts.append(box("ChimCap", (2.0, 2.0, 0.4), (7.0, 2.6, 17.0), shade(STONE, 0.75)))

# door: arched, framed, with a step
DW, DH = 3.4, 5.4
fy = -WY - 0.12
parts.append(box("DoorFrame", (DW + 0.7, 0.3, DH + 0.3), (0, fy, 0.9 + (DH + 0.3) / 2), TIMBER_D))
parts.append(cylinder("DoorArchF", (DW + 0.7) / 2, 0.3, (0, fy + 0.15, 0.9 + DH), TIMBER_D, segs=12, rot=(90, 0, 0)))
parts.append(box("Door", (DW, 0.32, DH), (0, fy - 0.06, 0.9 + DH / 2), DOOR))
parts.append(cylinder("DoorArch", DW / 2, 0.32, (0, fy + 0.1, 0.9 + DH), DOOR, segs=12, rot=(90, 0, 0)))
for k in (-1, 1):
    parts.append(box(f"Plank{k}", (0.12, 0.34, DH + 1.2), (k * 0.6, fy - 0.08, 0.9 + (DH + 1.0) / 2), shade(DOOR, 0.8)))
parts.append(blob("Knob", 0.18, (1.1, fy - 0.3, 3.4), rgb(240, 200, 90), subdiv=1, jitter=0))
parts.append(box("Step", (DW + 1.6, 1.2, 0.5), (0, -WY - 0.7, 0.25), STONE))

# windows at x = +-7.5 (sills at 4.0 for the flower boxes), plus one per gable end
def window(name, x, y, z0, wdt=3.0, hgt=3.0, face=-1):
    out = []
    zc = z0 + hgt / 2
    out.append(box(name + "Fr", (wdt + 0.5, 0.3, hgt + 0.5), (x, y, zc), TRIM))
    out.append(box(name + "Gl", (wdt, 0.34, hgt), (x, y + face * 0.04, zc), GLASS))
    out.append(box(name + "MV", (0.18, 0.4, hgt), (x, y + face * 0.06, zc), TRIM))
    out.append(box(name + "MH", (wdt, 0.4, 0.18), (x, y + face * 0.06, zc), TRIM))
    for k in (-1, 1):  # shutters
        out.append(box(name + f"Sh{k}", (0.9, 0.2, hgt + 0.2), (x + k * (wdt / 2 + 0.75), y, zc), TIMBER))
    return out

for x in (-7.5, 7.5):
    parts += window(f"Win{x}", x, -WY - 0.12, 4.0)
    parts += window(f"WinB{x}", x, WY + 0.12, 4.0, face=1)
for sx in (-1, 1):  # round attic window in each gable
    parts.append(cylinder(f"Attic{sx}", 1.0, 0.3, (sx * (WX + 0.25), 0, 12.6), TRIM, segs=10, rot=(0, 90, 0)))
    parts.append(cylinder(f"AtticG{sx}", 0.7, 0.34, (sx * (WX + 0.27), 0, 12.6), GLASS, segs=10, rot=(0, 90, 0)))

for o in parts:
    o.location = (0, 0, 0)
finish("plot_building", parts)
