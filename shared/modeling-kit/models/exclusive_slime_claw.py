# exclusive_slime_claw (concept): the Exclusive Shop as a prize claw shop worked by the game's own slime. A wooden ranch
# shop with a glass claw box above the counter; the gold trophy slime sits on a lilac cushion on the roof, over a hole
# in the ceiling, and lowers a stretchy gold goo arm with a three-finger goo hand into the box to grab what a player
# bought. The hand drops the prize in the gold funnel (front right); it pops out of the prize chute on the counter.
# Four meshes: the shop (solid), the glass (Transparency in game), the hand and the arm (the game moves the hand and
# stretches the arm from the ceiling hole to it). The three featured pet clouds sit on DISPLAYS on the box floor.
# Counter 10.4 wide, top z 4.1, like the other shops. Front faces -Y. CLAW_POSE=grab previews the arm reaching down.
import json
import math
import os
import random
import bmesh
import bpy
from lib import *
from models._phoenix_ranch import *
from models._shop_parts import counter, prism, gcyl
from models._shop_kit import *

parts, glassy, hand, arm = [], [], [], []
DISPLAYS = []

X0 = 6.2            # half width of the shop box (post centres)
YF, YB = -3.4, 4.2  # front and back wall planes
FZ = 4.4            # claw box floor (top)
CZ = 12.4           # claw box ceiling (underside of the roof)
RZ = 14.0           # roof top
HOLE = (0.0, 0.5)   # ceiling hole / arm root (x, y)
PINE = mix(WOOD, PLAZA, 0.35)

# ---- counter in front: planks, lilac band, sanded top; gold star medal ------------------------------------
CY, CD = -5.2, 2.6
parts += counter("C", 10.4, CY, CD, 3.6, WOOD, LILAC_LO, LILAC, shade(PINE, 0.85), PINE)
st = [(math.cos(math.radians(90 + i * 36)) * (0.7 if i % 2 == 0 else 0.3), 2.25 + math.sin(math.radians(90 + i * 36)) * (0.7 if i % 2 == 0 else 0.3)) for i in range(10)]
parts.append(gcyl("Medal", 0.9, 0.25, (0, CY - CD / 2 - 0.35, 2.25), GOLD_LO, GOLD, segs=12, rot=(90, 0, 0)))
parts.append(prism("MedalStar", st, CY - CD / 2 - 0.62, CY - CD / 2 - 0.42, LILAC_LO, LILAC_HI))
# big pink "grab" button on the left of the counter (decor; the claw runs on purchases)
parts.append(gcyl("BtnBase", 0.9, 0.35, (-3.3, CY + 0.2, 4.1), GOLD_LO, GOLD, segs=12))
btn = blob("Btn", 0.7, (-3.3, CY + 0.2, 4.55), PINK, subdiv=2, squash=(1, 1, 0.55), jitter=0)
gradient(btn, mix(PINK, ROOF, 0.3), mix(PINK, CREAM, 0.3))
parts.append(btn)
# prize chute on the right of the counter, against the shop wall: the prize pops out of its open front
PX = 3.9
parts.append(bbox("ChuteBox", (2.2, 1.8, 1.4), (PX, -4.5, 4.8), WOOD_LO, WOOD, bev=0.15))
parts.append(bbox("ChuteTrim", (2.4, 2.0, 0.3), (PX, -4.5, 5.55), GOLD_LO, GOLD, bev=0.1))
parts.append(bbox("ChuteMouth", (1.6, 0.3, 0.9), (PX, -5.35, 4.75), rgb(120, 82, 60), mix(WOOD_D, WOOD, 0.2), bev=0.08))
parts.append(bbox("ChuteFlap", (1.7, 0.18, 0.5), (PX, -5.6, 5.35), LILAC_LO, LILAC, bev=0.06, rot=(-35, 0, 0)))

# ---- shop box: posts, plank walls below the glass, back wall, box floor ---------------------------------
for sx in (-1, 1):
    for y in (YF, YB):
        parts.append(bbox(f"Post{sx}{y:.0f}", (1.1, 1.1, CZ + 0.2), (sx * X0, y, (CZ + 0.2) / 2), WOOD_LO, WOOD, bev=0.15))
        parts.append(bbox(f"Foot{sx}{y:.0f}", (1.5, 1.5, 0.5), (sx * X0, y, 0.25), shade(WOOD_D, 0.92), WOOD_D, bev=0.12))


def planks(prefix, axis, a0, a1, fixed, z0, z1, n, seed):
    """Vertical plank wall between a0..a1 along `axis` ('x' or 'y') at the fixed other coordinate."""
    R = random.Random(seed)
    out = [bbox(prefix + "Core", ((a1 - a0), 0.4, z1 - z0) if axis == "x" else (0.4, (a1 - a0), z1 - z0),
                ((a0 + a1) / 2, fixed, (z0 + z1) / 2) if axis == "x" else (fixed, (a0 + a1) / 2, (z0 + z1) / 2), WOOD_LO, WOOD_LO, bev=0)]
    w = (a1 - a0) / n
    for k in range(n):
        c = WOOD if k % 2 else mix(WOOD, CREAM, 0.12)
        h = z1 - z0 - 0.1 + R.uniform(-0.12, 0.05)
        m = a0 + w * (k + 0.5)
        off = -0.25 if fixed < 0 or (axis == "y" and fixed < 0) else 0.25
        if axis == "x":
            out.append(bbox(f"{prefix}{k}", (w - 0.1, 0.35, h), (m, fixed + off, z0 + h / 2), shade(c, 0.82), c, bev=0))
        else:
            out.append(bbox(f"{prefix}{k}", (0.35, w - 0.1, h), (fixed + off, m, z0 + h / 2), shade(c, 0.82), c, bev=0))
    return out


parts += planks("FrontPl", "x", -X0 + 0.5, X0 - 0.5, YF, 0.0, FZ, 9, 1)
for sx in (-1, 1):
    parts += planks(f"SidePl{sx}", "y", YF + 0.5, YB - 0.5, sx * X0, 0.0, FZ, 6, 2 + sx)
parts += planks("BackPl", "x", -X0 + 0.5, X0 - 0.5, YB, 0.0, CZ, 9, 5)
# back wall: lilac band and a big gold star medallion, so the back isn't plain boards
parts.append(bbox("BackBand", (2 * X0 - 0.6, 0.4, 1.2), (0, YB + 0.55, 8.6), LILAC_LO, LILAC, bev=0.1))
parts.append(gcyl("BackMedal", 1.7, 0.35, (0, YB + 0.6, 6.0), GOLD_LO, GOLD, segs=16, rot=(-90, 0, 0)))
bst = [(math.cos(math.radians(90 - i * 36)) * (1.25 if i % 2 == 0 else 0.55), 6.0 + math.sin(math.radians(90 - i * 36)) * (1.25 if i % 2 == 0 else 0.55)) for i in range(10)]
parts.append(prism("BackStar", list(reversed(bst)), YB + 0.9, YB + 1.1, LILAC_LO, LILAC_HI))
# inside the box: light lilac striped wallpaper on the back wall, so the clouds stand out against it
for k in range(10):
    x = -X0 + 0.6 + (2 * X0 - 1.2) * (k + 0.5) / 10
    c = mix(LILAC, CREAM, 0.5) if k % 2 else mix(LILAC, CREAM, 0.3)
    parts.append(bbox(f"Paper{k}", ((2 * X0 - 1.2) / 10 + 0.01, 0.12, CZ - FZ), (x, YB - 0.3, (FZ + CZ) / 2), c, c, bev=0))
# gold rail along the bottom of the glass, all round
parts.append(bbox("RailF", (2 * X0, 0.7, 0.45), (0, YF - 0.05, FZ + 0.1), GOLD_LO, GOLD, bev=0.1))
for sx in (-1, 1):
    parts.append(bbox(f"RailS{sx}", (0.7, YB - YF, 0.45), (sx * (X0 + 0.05), (YF + YB) / 2, FZ + 0.1), GOLD_LO, GOLD, bev=0.1))
# box floor: sanded boards with a goo pool in the middle
parts.append(bbox("Floor", (2 * X0 - 0.6, YB - YF - 0.6, 0.5), (0, (YF + YB) / 2, FZ - 0.25), shade(PLAZA, 0.9), PLAZA, bev=0.05))
pool = lathe("Pool", [(2.6, FZ - 0.1), (2.6, FZ + 0.12), (0, FZ + 0.2)], (-0.6, 1.2, 0), segs=20, col=GOO)
pool.data.transform(__import__("mathutils").Matrix.Diagonal((1.5, 0.8, 1, 1)) @ __import__("mathutils").Matrix.Translation((0.2, 0.4, 0)))
paint(pool, lambda c, n: mix(GOO, GOO_HI, 0.45) if n.z > 0.9 else GOO_LO)
parts.append(pool)

# three goo cushions for the featured pet clouds (DISPLAYS = the seat bottoms)
for k, (x, y) in enumerate(((-3.4, 0.6), (-0.3, 2.1), (2.7, 1.5))):
    PH = 1.6                                   # goo pedestal: lifts the cloud over the capsules and the counter line
    ped = lathe(f"Ped{k}", [(1.0, FZ), (0.7, FZ + 0.4), (0.55, FZ + PH - 0.5), (1.2, FZ + PH - 0.15), (1.2, FZ + PH), (0, FZ + PH + 0.05)], (x, y, 0), segs=12, col=GOO)
    paint(ped, lambda c, n: mix(GOO, GOO_HI, 0.5) if n.z > 0.8 else (GOO if c.z > FZ + 0.8 else GOO_LO))
    parts.append(ped)
    parts.append(ring(f"PedRing{k}", 1.22, FZ + PH - 0.08, thick=0.16, pos=(x, y), segs=12, sides=4))
    DISPLAYS.append((x, y, FZ + PH + 0.05))

# prize capsules heaped on the floor (lilac top, gold bottom)
R = random.Random(11)
caps = [(-5.0, -1.9), (-4.2, -2.4), (-2.6, -2.3), (-1.4, -2.6), (0.4, -2.5), (1.6, -2.0), (-5.1, 2.6), (-1.9, 3.3),
        (1.4, 3.3), (4.6, 2.9), (-2.0, -1.2)]
for k, (x, y) in enumerate(caps):
    r = R.uniform(0.5, 0.68)
    top = (LILAC, PINK, GOO_HI)[k % 3]
    ca = blob(f"Cap{k}", r, (x, y, FZ + r * 0.8), GOLD, subdiv=2, jitter=0, rot=(R.uniform(-30, 30), R.uniform(-30, 30), 0))
    cz = FZ + r * 0.8
    paint(ca, lambda c, n, cz=cz, top=top: mix(top, CREAM, 0.25) if c.z > cz + 0.05 else (GOLD if c.z > cz - r * 0.5 else GOLD_LO))
    parts.append(ca)

# gold prize funnel at the front right: the hand drops the prize here
FX, FYc = 4.1, -1.6
fun = lathe("Funnel", [(1.45, FZ - 0.1), (1.45, FZ + 1.1), (1.6, FZ + 1.35), (1.25, FZ + 1.35), (0.55, FZ + 0.25), (0, FZ + 0.2)], (FX, FYc, 0), segs=16, col=GOLD)
paint(fun, lambda c, n: rgb(120, 82, 60) if (n.z > 0.2 and math.hypot(c.x - FX, c.y - FYc) < 1.2) else (GOLD_HI if n.z > 0.6 else mix(GOLD_LO, GOLD, 0.6)))
parts.append(fun)

# ---- glass: front and both sides (its own mesh) ------------------------------------------------------------
GH = CZ - FZ - 0.35
GT = 0.88          # glass transparency: clearer than the jar (0.8) so the clouds read through two panes
glassy.append(glass(box("GlassF", (2 * X0 - 1.1, 0.2, GH), (0, YF, FZ + 0.3 + GH / 2), GLASS), GT))
for sx in (-1, 1):
    glassy.append(glass(box(f"GlassS{sx}", (0.2, YB - YF - 1.1, GH), (sx * X0, (YF + YB) / 2, FZ + 0.3 + GH / 2), GLASS), GT))
# thin gold mullions on the front glass
for x in (-X0 / 3, X0 / 3):
    parts.append(bbox(f"Mull{x:.0f}", (0.3, 0.35, GH), (x * 1.9, YF - 0.05, FZ + 0.3 + GH / 2), GOLD_LO, GOLD, bev=0.06))

# ---- ceiling + roof: wood slab, lilac fascia (the sign: SurfaceGui), bulbs, striped scalloped valance ---------------
parts.append(bbox("Ceiling", (2 * X0 + 0.4, YB - YF + 0.4, 0.4), (0, (YF + YB) / 2, CZ + 0.2), WOOD_LO, WOOD_LO, bev=0.05))
hole = lathe("HoleRing", [(1.35, CZ - 0.15), (1.35, CZ + 0.05), (0.95, CZ + 0.05), (0.95, CZ - 0.15)], (HOLE[0], HOLE[1], 0), segs=16, col=GOLD)
parts.append(hole)
parts.append(cylinder("HoleDark", 0.96, 0.05, (HOLE[0], HOLE[1], CZ - 0.06), rgb(96, 66, 50), segs=16))
RW, RD = 2 * X0 + 2.0, YB - YF + 2.2
parts.append(bbox("Roof", (RW, RD, RZ - CZ - 0.4), (0, (YF + YB) / 2, (CZ + 0.4 + RZ) / 2), shade(PINE, 0.85), PINE, bev=0.15))
FYF = YF - 1.1 - 0.25                       # fascia front plane
parts.append(bbox("Fascia", (RW + 0.2, 0.6, 2.1), (0, FYF + 0.1, CZ + 1.1), LILAC_LO, LILAC, bev=0.15))
parts.append(bbox("FasciaFace", (RW - 2.6, 0.2, 1.4), (0, FYF - 0.25, CZ + 1.1), shade(BUTTER, 0.92), mix(BUTTER, CREAM, 0.2), bev=0.05))
for k in range(13):
    x = -RW / 2 + 0.6 + (RW - 1.2) * k / 12
    if abs(x) > (RW - 2.6) / 2 + 0.2 or k in (0, 12):
        parts.append(bulb(f"FBulb{k}", (x, FYF - 0.3, CZ + 1.1), 0.24))
for k in range(11):
    x = -RW / 2 + 0.6 + (RW - 1.2) * k / 10
    parts.append(bulb(f"TBulb{k}", (x, FYF - 0.1, RZ + 0.2), 0.22))
# valance under the fascia: lilac / butter stripes with a scalloped edge
NS = 9
for k in range(NS):
    x = -RW / 2 + RW * (k + 0.5) / NS
    hi, lo = (LILAC, LILAC_LO) if k % 2 == 0 else (BUTTER, BUTTER_LO)
    parts.append(bbox(f"Val{k}", (RW / NS + 0.01, 0.25, 0.5), (x, FYF + 0.15, CZ - 0.15), lo, hi, bev=0))
    sc = cylinder(f"ValScal{k}", RW / NS / 2 - 0.03, 0.25, (x, FYF + 0.28, CZ - 0.4), hi, segs=10, rot=(90, 0, 0))
    gradient(sc, mix(lo, hi, 0.5), hi)
    parts.append(sc)

# ---- the slime's seat on the roof: lilac cushion with gold piping, goo poured over it ------------------------
SX, SY = HOLE[0], HOLE[1] + 0.3
cush = lathe("Seat", [(2.9, RZ), (3.2, RZ + 0.6), (3.0, RZ + 1.3), (2.3, RZ + 1.6), (0, RZ + 1.65)], (SX, SY, 0), segs=24, col=LILAC)
paint(cush, lambda c, n: mix(LILAC, PINK, 0.15) if n.z > 0.7 else (LILAC if c.z > RZ + 0.5 else LILAC_LO))
parts.append(cush)
parts.append(ring("SeatPipe", 3.18, RZ + 0.6, thick=0.26, pos=(SX, SY), segs=24))
for k in range(4):
    a = math.radians(45 + 90 * k)
    parts.append(blob(f"Tassel{k}", 0.35, (SX + math.cos(a) * 3.0, SY + math.sin(a) * 3.0, RZ + 0.25), GOLD, subdiv=1, jitter=0, squash=(1, 1, 1.4)))
SLIME_Z = RZ + 1.4
parts += trophy_slime(SX, SY, SLIME_Z, size=6.2, decim=0.6)

# ---- the claw: a gold goo arm from the ceiling hole and a three-finger goo hand ---------------------------------
POSE = os.environ.get("CLAW_POSE", "idle")
HAND_TOP = {"idle": (HOLE[0], HOLE[1], CZ - 1.5), "grab": (-0.3, 2.1, FZ + 5.4)}[POSE]


def goo_hand(cx, cy, cz):
    """Palm blob + three fingers curling down and in, fat round tips. (cx, cy, cz) = top of the palm (arm end)."""
    out = []
    pz = cz - 0.55
    palm = blob("Palm", 0.85, (cx, cy, pz), SG, subdiv=2, jitter=0, squash=(1, 1, 0.75))
    gradient(palm, SG_LO, SG_HI)
    out.append(palm)
    for k in range(3):
        a = math.radians(-90 + 120 * k)          # one prong to the back, two to the front corners
        dx, dy = math.cos(a), math.sin(a)
        prof = [(0.5, 0.0), (1.05, -0.35), (1.45, -0.95), (1.5, -1.6), (1.25, -2.15), (0.85, -2.4)]
        pts = [(cx + dx * r, cy + dy * r, pz + z) for r, z in prof]
        rad = [0.34, 0.32, 0.3, 0.28, 0.27, 0.26]
        f = tube(f"Finger{k}", pts, rad, SG, segs=8, twist_free=True)
        gradient(f, SG_LO, SG)
        out.append(f)
        out.append(blob(f"Knuckle{k}", 0.36, pts[1], SG, subdiv=1, jitter=0))
        tip = blob(f"Tip{k}", 0.34, pts[-1], SG_HI, subdiv=2, jitter=0)
        gradient(tip, SG, SG_HI)
        out.append(tip)
    return out


hand += goo_hand(*HAND_TOP)
# the arm: a gooey tube with a few bulges, root in the ceiling hole, end in the palm
a0, a1 = (HOLE[0], HOLE[1], CZ + 0.2), HAND_TOP
n = 9
apts = [tuple(a0[i] + (a1[i] - a0[i]) * t for i in range(3)) for t in (k / (n - 1) for k in range(n))]
arad = [0.5 + 0.08 * math.sin(k * 2.1) for k in range(n)]
arm_o = tube("Arm", apts, arad, SG, segs=10, twist_free=True)
gradient(arm_o, SG_LO, SG_HI)
arm.append(arm_o)

# ---- layout for the game (shop mesh frame), then the meshes ------------------------------------------------


def bc(objs):
    vs = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return ((min(v.x for v in vs) + max(v.x for v in vs)) / 2, (min(v.y for v in vs) + max(v.y for v in vs)) / 2, min(v.z for v in vs))


OFF = bc(parts)
rel = lambda p: [round(p[0] - OFF[0], 3), round(p[1] - OFF[1], 3), round(p[2] - OFF[2], 3)]
layout = {
    "note": "Blender frame, studs: x right, y back (front faces -y), z up; origin = the shop mesh bbox bottom-centre. Roblox: X = x, Y = z, Z = -y.",
    "ground_z": round(-OFF[2], 3),
    "glass_origin": rel(bc(glassy)),
    "glass_transparency": GT,
    "displays": [rel(d) for d in DISPLAYS],
    "arm_root": rel((HOLE[0], HOLE[1], CZ + 0.2)),
    "hand_idle_top": rel((HOLE[0], HOLE[1], CZ - 1.5)),
    "box_floor_z": rel((0, 0, FZ))[2],
    "box_inner": {"x": [-X0 + 0.9, X0 - 0.9], "y": [YF + 0.9, YB - 0.9]},
    "funnel_top": rel((FX, FYc, FZ + 1.35)),
    "chute_mouth": rel((PX, -5.5, 4.75)),
    "counter_top": rel((0, CY, 4.1)),
    "counter_size": [10.4, CD],
    "sign_face_centre": rel((0, FYF - 0.36, CZ + 1.1)),
    "sign_face_size": [RW - 2.6, 1.4],
}
with open(os.path.join(OUT, "exclusive_slime_claw_layout.json"), "w", newline="") as f:
    json.dump(layout, f, indent=1)

PART = os.environ.get("CLAW_PART", "")   # shop | glass | hand | arm | "" (all, for previews)
keep = {"shop": parts, "glass": glassy, "hand": hand, "arm": arm}
if PART:
    for k, objs in keep.items():
        if k != PART:
            for o in objs:
                bpy.data.objects.remove(o)
    finish("exclusive_slime_claw" + ("" if PART == "shop" else "_" + PART), keep[PART])
else:
    finish("exclusive_slime_claw", parts + hand + arm)
    g = finish("exclusive_slime_claw_glass", glassy)
    g["rbx_transparency"] = GT
    g.location = layout["glass_origin"]      # finish() re-centres each mesh on its own bbox; put the glass back
