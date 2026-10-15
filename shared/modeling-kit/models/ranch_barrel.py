# ranch_barrel: chunky wood barrel prop (Slime Ranch), ~2.4 diam x 2.6 tall.
# Bulged stave body, warm pewter hoops outside the bulge, cream bung on -Y.
# Soft farm prop for plaza/plot next to the barn loft. cylinder() pos = base.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM = PALETTE["ranch_cream"]
METAL = PALETTE["ranch_metal"]
PLAZA = PALETTE["ranch_plaza"]

WOOD_LO = mix(WOOD_D, WOOD, 0.55)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO = mix(METAL, WOOD_D, 0.2)
CREAM_LO = mix(CREAM, WOOD, 0.2)
parts = []

R, H = 1.05, 2.55
SEGS = 12
BULGE = 0.16

def radius_at(t):
    return R * (1.0 + BULGE * math.sin(math.pi * max(0.0, min(1.0, t))))

# body: pos is the BASE (cylinder stands on pos.z)
body = cylinder("Body", R, H, (0, 0, 0), WOOD, segs=SEGS)
bm = bmesh.new()
bm.from_mesh(body.data)
for v in bm.verts:
    t = max(0.0, min(1.0, v.co.z / H))
    b = 1.0 + BULGE * math.sin(math.pi * t)
    v.co.x *= b
    v.co.y *= b
layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
for f in bm.faces:
    c = f.calc_center_median()
    ang = math.atan2(c.y, c.x)
    stave = int(((ang + math.pi) / (2 * math.pi)) * SEGS) % 2
    t = max(0.0, min(1.0, c.z / H))
    col = mix(WOOD_LO, WOOD_HI, t)
    if stave:
        col = shade(col, 0.93)
    if abs(f.normal.z) > 0.85:
        col = mix(PLAZA, WOOD, 0.2) if f.normal.z > 0 else WOOD_LO
    for lp in f.loops:
        lp[layer] = (*col[:3], 1.0)
bm.to_mesh(body.data)
bm.free()
parts.append(body)

# lids: top lid proud of the rim; bottom lid sits just above z=0
parts.append(cylinder("Lid", R * 0.9, 0.14, (0, 0, H - 0.06), PLAZA, segs=SEGS))
gradient(parts[-1], mix(PLAZA, WOOD, 0.15), PLAZA)
parts.append(cylinder("Bot", R * 0.9, 0.12, (0, 0, 0.02), WOOD_LO, segs=SEGS))
gradient(parts[-1], WOOD_D, WOOD_LO)

# three metal hoops — radius tracks the bulge so they sit ON the surface
for i, t in enumerate((0.18, 0.5, 0.82)):
    z = t * H - 0.1
    rh = radius_at(t) + 0.05
    hoop = cylinder(f"Hoop{i}", rh, 0.18, (0, 0, z), METAL, segs=SEGS)
    gradient(hoop, METAL_LO, METAL)
    parts.append(hoop)

# bung on the front face (-Y), outside the mid bulge
bung_y = -(radius_at(0.55) + 0.06)
bung = cylinder("Bung", 0.18, 0.2, (0, bung_y, H * 0.55 - 0.1), CREAM, segs=8, rot=(90, 0, 0))
gradient(bung, CREAM_LO, CREAM)
parts.append(bung)

finish("ranch_barrel", parts)
