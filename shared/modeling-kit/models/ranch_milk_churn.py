# ranch_milk_churn: classic farm butter/milk churn (Slime Ranch plaza prop), ~2.4 wide x ~5.6 tall.
# Tapered stave body (wider at the foot), 3 pewter bands tracking the taper, plaza-wood lid with a
# knob collar, dasher (plunger) stick + cross grip sticking up, two pewter side handles on +-X,
# slight lean toward -Y, a small goo spill running from under the lid down the front (-Y).
# Recipe from models/ranch_goo_bucket.py / ranch_barrel.py. cylinder() pos = base; rot= in DEGREES.
import math
import bmesh
from mathutils import Matrix, Vector
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_metal"], PALETTE["ranch_plaza"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]

WOOD_LO = mix(WOOD_D, WOOD, 0.55)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO = METAL
METAL_HI = mix(METAL, CREAM, 0.35)

R_BOT, R_TOP, H = 1.08, 0.76, 4.1   # stave body: wider foot, narrower top
SEGS = 12
LEAN = 3.0                           # whole churn leans toward -Y (deg)
parts = []


def radius_at(t):
    return R_BOT + (R_TOP - R_BOT) * max(0.0, min(1.0, t))


# body frustum with alternating stave shades, slight belly so it isn't a CAD cone
body = cylinder("Body", R_BOT, H, (0, 0, 0), WOOD, segs=SEGS, r_top=R_TOP)
bm = bmesh.new()
bm.from_mesh(body.data)
for v in bm.verts:
    t = max(0.0, min(1.0, v.co.z / H))
    b = 1.0 + 0.04 * math.sin(math.pi * t)
    v.co.x *= b
    v.co.y *= b
layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
for f in bm.faces:
    c = f.calc_center_median()
    stave = int(((math.atan2(c.y, c.x) + math.pi) / (2 * math.pi)) * SEGS) % 2
    col = mix(WOOD_LO, WOOD_HI, max(0.0, min(1.0, c.z / H)))
    if stave:
        col = shade(col, 0.93)
    if f.normal.z > 0.85:
        col = mix(PLAZA, WOOD, 0.2)
    elif f.normal.z < -0.85:
        col = WOOD_LO
    for lp in f.loops:
        lp[layer] = (*col[:3], 1.0)
bm.to_mesh(body.data)
bm.free()
parts.append(body)

# foot ring (dark wood) so it sits heavy on the ground
parts.append(cylinder("Foot", R_BOT + 0.08, 0.22, (0, 0, 0), WOOD_LO, segs=SEGS, r_top=R_BOT + 0.05))
gradient(parts[-1], WOOD_D, WOOD_LO)

# pewter bands, radius follows taper + belly
for i, t in enumerate((0.16, 0.5, 0.86)):
    rh = radius_at(t) * (1.0 + 0.04 * math.sin(math.pi * t)) + 0.05
    band = cylinder(f"Band{i}", rh, 0.2, (0, 0, t * H - 0.1), METAL, segs=SEGS)
    gradient(band, METAL_LO, METAL_HI)
    parts.append(band)

# lid: overhanging plaza-wood disc + raised collar where the dasher goes through
LID_Z = H - 0.04
parts.append(cylinder("Lid", R_TOP + 0.14, 0.24, (0, 0, LID_Z), PLAZA, segs=SEGS, r_top=R_TOP + 0.06))
gradient(parts[-1], mix(PLAZA, WOOD, 0.35), PLAZA)
parts.append(cylinder("Collar", 0.34, 0.26, (0, 0, LID_Z + 0.22), ROOF, segs=10, r_top=0.26))
gradient(parts[-1], mix(ROOF_D, ROOF, 0.5), ROOF)

# dasher: stick up through the collar + cross grip on top
STICK_TOP = H + 1.75
parts.append(cylinder("Stick", 0.13, STICK_TOP - (LID_Z + 0.3), (0, 0, LID_Z + 0.3), WOOD_HI, segs=8))
gradient(parts[-1], WOOD, WOOD_HI)
grip = cylinder("Grip", 0.13, 1.1, (-0.55, 0, STICK_TOP - 0.1), WOOD_HI, segs=8, rot=(0, 90, 0))
gradient(grip, WOOD, WOOD_HI)
parts.append(grip)
parts.append(blob("Knob", 0.2, (0, 0, STICK_TOP + 0.03), CREAM, subdiv=1, squash=(1, 1, 0.8), jitter=0.0))

# side handles on +-X: pewter loops between two ears, on the upper band
for sx in (-1, 1):
    t0, t1 = 0.62, 0.8
    pts, rads = [], []
    for i in range(7):
        a = math.pi * i / 6
        z = H * (t0 + (t1 - t0) * (1 - math.cos(a)) / 2)
        r = radius_at(z / H) + 0.05 + 0.32 * math.sin(a)
        pts.append((sx * r, 0.0, z))
        rads.append(0.11)
    h = tube(f"Handle{sx}", pts, rads, METAL, segs=5)
    gradient(h, METAL_LO, METAL_HI)
    parts.append(h)

# lean the whole churn a few degrees toward -Y (about the foot)
LEANM = Matrix.Rotation(math.radians(LEAN), 4, "X")
for o in parts:
    o.data.transform(LEANM)

# goo: a small blob of spill squeezed out under the lid on the front, running down to the top band
def surf(t, off=0.0, a=0.0):
    n = Vector((math.sin(a), -math.cos(a), 0))
    p = n * (radius_at(t) * (1.0 + 0.04 * math.sin(math.pi * t)) + off) + Vector((0, 0, t * H))
    return LEANM @ p, (LEANM.to_3x3() @ n).normalized()


balls = []
a = math.radians(-12)
lip, n = surf(1.0, 0.1, a)
balls.append(Ball(lip, (0.42, 0.3, 0.12)))
down = (LEANM.to_3x3() @ Vector((0, 0, -1))).normalized()
steps = 6
ln = 0.18
for j in range(steps + 1):
    t = 0.98 - ln * j / steps
    p, n = surf(t, -0.03, a)
    lat = n.cross(down).normalized()
    balls.append(Ball(p, (0.26, 0.25 * (1.0 - 0.35 * j / steps), 0.1), rot=frame_quat(down, lat, n)))
p, n = surf(0.98 - ln, -0.02, a)
balls.append(Ball(p, (0.2, 0.2, 0.15), rot=frame_quat(down, n.cross(down).normalized(), n)))
goo = metaball_mesh("GooSpill", balls, resolution=0.12, tris=260)
parts.append(paint_goo(goo, lambda co, n: mix(GOO, GOO_HI, min(0.5, max(0.0, n.z) ** 4 * 0.5))))

finish("ranch_milk_churn", parts)
