# exclusive_jar_boutique (concept): the Exclusive Shop as the game's own signature goo jar, made premium. A big glass
# jar with gold bands stands on a wooden plinth ringed with goo; three goo pedestals inside lift the exclusive pet
# clouds into view (the game seats the real seat meshes on DISPLAYS); a wooden shop front with a lilac / butter
# awning and the sign is built into the jar's front; the lid is a gold cork with the trophy slime on top.
# Two meshes: the solid shop and the jar glass (Transparency in game). Counter top z 4.1 like the other shops.
import math
import os
import bpy
from lib import *
from models._phoenix_ranch import *
from models._shop_parts import counter, prism, gcyl
from models._shop_kit import *

parts, glassy = [], []
DISPLAYS = []
JR = 6.4            # jar radius
PZ = 1.0            # plinth top
WZ = 11.6           # straight glass top

# ---- plinth: wood planks + goo poured over its rim --------------------------------------------------------
pl = lathe("Plinth", [(JR + 1.6, 0), (JR + 1.6, PZ), (0, PZ)], (0, 0, 0), segs=32, col=WOOD)
paint(pl, lambda c, n: (PLANK if int((math.atan2(c.y, c.x) + math.pi) / math.tau * 32) % 2 else WOOD) if n.z < 0.5 else mix(PLAZA, WOOD, 0.3))
parts.append(pl)
parts.append(goo_ring("PlinthGoo", 0, 0, PZ - 0.45, JR + 1.45, n=44, seed=3, drip=(0.25, 0.6), thick=0.6))
# goo pool inside the jar floor
pool = lathe("Pool", [(JR - 0.2, PZ), (JR - 0.2, PZ + 0.35), (0, PZ + 0.45)], (0, 0, 0), segs=28, col=GOO)
paint(pool, lambda c, n: mix(GOO, GOO_HI, 0.5) if n.z > 0.9 else GOO_LO)
parts.append(pool)

# ---- the jar: glass wall + shoulder + neck (its own see-through mesh), gold bands ----------------------------
jar_prof = [(JR, PZ + 0.2), (JR, WZ + 0.1)]
outer = lathe("JarGlass", jar_prof + [(r - 0.25, z) for r, z in reversed(jar_prof)], (0, 0, 0), segs=32, col=GLASS)
# the shoulder is goo spilling over the jar top: solid, glossy, dripping down the glass
sh = lathe("Shoulder", [(JR + 0.25, WZ - 0.1), (JR + 0.3, WZ + 0.5), (JR * 0.9, WZ + 1.5), (JR * 0.66, WZ + 2.3), (JR * 0.45, WZ + 2.7), (0, WZ + 2.75)], (0, 0, 0), segs=32, col=GOO)
paint(sh, lambda c, n: mix(GOO, GOO_HI, 0.55) if n.z > 0.85 else GOO)
parts.append(sh)
parts.append(goo_ring("TopGoo", 0, 0, WZ - 0.2, JR + 0.05, n=56, seed=5, drip=(0.6, 1.8), thick=0.5))
glassy.append(glass(outer, 0.8))
for k, z in enumerate((PZ + 0.35, 7.0)):
    parts.append(ring(f"Band{k}", JR + 0.08, z, thick=0.34, segs=24))
parts.append(ring("NeckBand", JR * 0.46, WZ + 2.7, thick=0.34, segs=16))

# ---- gold cork lid + trophy slime --------------------------------------------------------------------------
LZ = WZ + 2.75
lid = lathe("Lid", [(JR * 0.45, LZ - 0.2), (JR * 0.52, LZ + 0.5), (JR * 0.5, LZ + 1.3), (JR * 0.34, LZ + 1.55), (0, LZ + 1.6)], (0, 0, 0), segs=20, col=GOLD)
paint(lid, lambda c, n: GOLD_HI if n.z > 0.8 else (mix(GOLD_LO, GOLD, 0.5) if n.z > -0.2 else GOLD_LO))
parts.append(lid)
parts.append(goo_ring("LidGoo", 0, 0, LZ + 1.25, JR * 0.5, n=22, seed=8, drip=(0.2, 0.55), thick=1.0))
parts += trophy_slime(0, 0, LZ + 1.45, size=4.2, decim=0.45)

# ---- three goo pedestals inside: the clouds float above them (DISPLAYS) ----------------------------------------
for k, (x, y, h) in enumerate(((-3.3, 1.4, 6.0), (0.0, 2.6, 8.2), (3.3, 1.4, 6.0))):
    col = lathe(f"Ped{k}", [(1.05, PZ), (0.75, PZ + 0.6), (0.6, PZ + h - 0.5), (0.95, PZ + h - 0.1), (0.95, PZ + h), (0, PZ + h + 0.05)], (x, y, 0), segs=12, col=GOO)
    paint(col, lambda c, n: mix(GOO, GOO_HI, 0.55) if n.z > 0.8 else (GOO if c.z > PZ + 1.5 else GOO_LO))
    parts.append(col)
    parts.append(ring(f"PedRing{k}", 0.97, PZ + h - 0.05, thick=0.16, pos=(x, y), segs=10, sides=4))
    DISPLAYS.append((x, y, PZ + h + 0.35))
# goo bubbles rising in the jar
for k, (x, y, z, r) in enumerate(((-1.6, 3.4, 3.0, 0.32), (1.8, 3.0, 5.6, 0.25), (-0.4, 3.8, 8.0, 0.36), (2.6, 2.4, 9.3, 0.22), (-2.8, 2.6, 7.0, 0.27))):
    parts.append(blob(f"Bubble{k}", r, (x, y, z), mix(GOO_HI, CREAM, 0.3), subdiv=1, jitter=0))

# ---- shop front built into the jar: wood frame, counter, striped awning, sign ---------------------------------
FY = -JR + 0.6       # the front sits into the glass
W = 9.6
parts += counter("C", W, FY - 1.4, 2.6, 3.6, WOOD, LILAC_LO, LILAC, shade(mix(WOOD, PLAZA, 0.35), 0.85), mix(WOOD, PLAZA, 0.35), np_=8)
for sx in (-1, 1):
    parts.append(bbox(f"FramePost{sx}", (0.9, 1.2, 7.0), (sx * (W / 2 + 0.1), FY - 1.2, 3.5), WOOD_LO, WOOD, bev=0.15))
    parts.append(blob(f"PostKnob{sx}", 0.5, (sx * (W / 2 + 0.1), FY - 1.2, 7.35), GOLD, subdiv=2, jitter=0))
parts.append(bbox("FrameBeam", (W + 1.4, 1.2, 0.9), (0, FY - 1.2, 6.6), WOOD_LO, WOOD, bev=0.15))
# awning: 7 stripes sloping out, scalloped edge
NS = 7
for k in range(NS):
    x = -W / 2 - 0.4 + (W + 0.8) * (k + 0.5) / NS
    hi, lo = (LILAC, LILAC_LO) if k % 2 == 0 else (BUTTER, BUTTER_LO)
    parts.append(bbox(f"Awn{k}", ((W + 0.8) / NS + 0.01, 3.0, 0.3), (x, FY - 2.7, 6.1), lo, hi, bev=0, rot=(-22, 0, 0)))
    sc = cylinder(f"AwnScal{k}", (W + 0.8) / NS / 2 - 0.03, 0.24, (x, FY - 4.1, 5.25), hi, segs=10, rot=(90, 0, 0))
    gradient(sc, mix(lo, hi, 0.5), hi)
    parts.append(sc)
# sign above the beam, arched, bulbs round it (SurfaceGui "EXCLUSIVE" on the face)
SZ = 7.9
arch = [(-3.6, SZ - 0.9), (3.6, SZ - 0.9), (3.6, SZ + 0.4)] + [(math.cos(math.radians(a)) * 3.6, SZ + 0.4 + math.sin(math.radians(a)) * 0.9) for a in range(15, 166, 15)] + [(-3.6, SZ + 0.4)]
parts.append(prism("SignBoard", arch, FY - 1.6, FY - 0.9, GOLD_LO, GOLD))
parts.append(prism("SignFace", [(x * 0.9, SZ + (z - SZ) * 0.78) for x, z in arch], FY - 1.8, FY - 1.55, LILAC_LO, LILAC))
for k in range(11):
    a = math.radians(10 + k * 16)
    parts.append(bulb(f"SignBulb{k}", (math.cos(a) * 3.8, FY - 1.85, SZ + 0.4 + math.sin(a) * 1.05), 0.19))
# gold star on the counter front
st = [(math.cos(math.radians(90 + i * 36)) * (0.7 if i % 2 == 0 else 0.3), 2.25 + math.sin(math.radians(90 + i * 36)) * (0.7 if i % 2 == 0 else 0.3)) for i in range(10)]
parts.append(gcyl("Medal", 0.9, 0.25, (0, FY - 2.95, 2.25), GOLD_LO, GOLD, segs=12, rot=(90, 0, 0)))
parts.append(prism("MedalStar", st, FY - 3.22, FY - 3.02, LILAC_LO, LILAC_HI))

# ---- two gold lanterns on the plinth front -----------------------------------------------------------------
for sx in (-1, 1):
    x, y = sx * 7.0, -3.8
    parts.append(gcyl(f"LampPost{sx}", 0.22, 4.6, (x, y, PZ), WOOD_LO, WOOD, segs=6))
    parts.append(gcyl(f"LampCage{sx}", 0.6, 1.1, (x, y, PZ + 4.6), GOLD_LO, GOLD, segs=6))
    parts.append(blob(f"LampGoo{sx}", 0.42, (x, y, PZ + 5.15), mix(GOO_HI, BUTTER, 0.3), subdiv=1, jitter=0))
    parts.append(cone(f"LampHat{sx}", 0.75, 0.6, (x, y, PZ + 5.7), GOLD, segs=6))

# ---- layout for the game (shop mesh frame), then the meshes ------------------------------------------------
import json


def bc(objs):
    vs = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return ((min(v.x for v in vs) + max(v.x for v in vs)) / 2, (min(v.y for v in vs) + max(v.y for v in vs)) / 2, min(v.z for v in vs))


OFF = bc(parts)          # the shop mesh's own origin: finish() puts it at the bbox bottom-centre
rel = lambda p: [round(p[0] - OFF[0], 3), round(p[1] - OFF[1], 3), round(p[2] - OFF[2], 3)]
DISPLAYS = [tuple(rel(d)) for d in DISPLAYS]
layout = {
    "note": "Blender frame, studs: x right, y back (front faces -y), z up; origin = the shop mesh bbox bottom-centre. Roblox: X = x, Y = z, Z = -y.",
    "ground_z": round(-OFF[2], 3),            # where the plinth bottom (the grass) is in the shop frame
    "glass_origin": rel(bc(glassy)),          # the glass mesh's bbox bottom-centre in the shop frame
    "glass_transparency": 0.8,
    "displays": DISPLAYS,                     # seat bottoms of the three floating pet clouds
    "counter_top": rel((0, FY - 1.4, 4.1)),
    "counter_size": [9.6, 2.6],
    "sign_face_centre": rel((0, FY - 1.81, SZ + 0.05)),
    "sign_face_size": [6.4, 1.4],
    "footprint_radius": round(JR + 1.6 + 1.6, 2),
}
with open(os.path.join(OUT, "exclusive_jar_boutique_layout.json"), "w", newline="") as f:
    json.dump(layout, f, indent=1)

PART = os.environ.get("JAR_PART", "")   # shop | glass | "" (both, for previews)
if PART == "glass":
    for o in parts:
        bpy.data.objects.remove(o)
    finish("exclusive_jar_boutique_glass", glassy)
elif PART == "shop":
    for o in glassy:
        bpy.data.objects.remove(o)
    finish("exclusive_jar_boutique", parts)
else:
    finish("exclusive_jar_boutique", parts)
    g = finish("exclusive_jar_boutique_glass", glassy)
    g["rbx_transparency"] = 0.8
