# exclusive_cloud_nine (concept): the Exclusive Shop on a puffy cloud island, because it sells clouds. A round
# wooden cottage with a lilac / butter onion roof and a front counter window sits on a low cloud base (steps up the
# front); a rainbow arch carries the sign; a goo waterfall pours off the cloud's side into a goo pool; three pet
# clouds float on little cloud puffs round it (DISPLAYS). Counter top z 4.1 above the ground like the other shops.
import math
import random
from lib import *
from models._phoenix_ranch import *
from models._shop_parts import counter, prism, gcyl
from models._shop_kit import *

R = random.Random(9)
parts = []
DISPLAYS = []
CLOUD = rgb(246, 248, 255)
CLOUD_LO = rgb(206, 212, 240)
BZ = 1.2                  # cloud deck top
HR = 4.6                  # cottage radius
HY = 1.2                  # cottage centre y

# ---- the cloud island: a flat deck with puffs round its rim and under it -------------------------------------
parts.append(gcyl("Deck", 8.4, BZ, (0, 0.6, 0), CLOUD_LO, CLOUD, segs=24))
for k in range(18):
    a = k * math.tau / 18 + R.uniform(-0.1, 0.1)
    rr = R.uniform(1.4, 2.0)
    if -2.0 < math.cos(a) * 8.6 < 2.0 and math.sin(a) < 0:
        continue      # keep the walk-up to the counter clear
    p = blob(f"Puff{k}", rr, (math.cos(a) * 8.6, 0.6 + math.sin(a) * 7.8, BZ - 0.4), CLOUD, subdiv=2, jitter=0, squash=(1, 1, 0.75))
    gradient(p, CLOUD_LO, CLOUD, 0, BZ + 1.2)
    parts.append(p)
for k in range(3):    # cloud steps up the front
    parts.append(bbox(f"Step{k}", (3.6 - k * 0.3, 1.0, 0.4 * (k + 1)), (0, -7.4 + k * 0.9, 0.2 * (k + 1)), CLOUD_LO, CLOUD, bev=0.18))

# ---- round cottage: plank walls, onion roof, gold finial + trophy slime ---------------------------------------
wall = lathe("Wall", [(HR, BZ), (HR, BZ + 6.8), (0, BZ + 6.8)], (0, HY, 0), segs=20, col=WOOD)
paint(wall, lambda c, n: (PLANK if int((math.atan2(c.y - HY, c.x) + math.pi) / math.tau * 20) % 2 else WOOD) if abs(n.z) < 0.5 else WOOD)
parts.append(wall)
parts.append(ring("WallBand", HR + 0.05, BZ + 6.6, thick=0.3, pos=(0, HY), segs=24))
RZ = BZ + 6.8
roof = lathe("Roof", [(HR + 1.1, RZ - 0.2), (HR + 1.3, RZ + 0.6), (HR + 0.9, RZ + 2.2), (HR * 0.55, RZ + 4.0), (0.6, RZ + 5.3), (0, RZ + 5.5)], (0, HY, 0), segs=20, col=LILAC)


def gore(c, n):
    g = int((math.atan2(c.y - HY, c.x) + math.pi) / math.tau * 20) % 2
    t = min(1, max(0, (c.z - RZ) / 5))
    return mix(LILAC_LO, LILAC, t) if g else mix(BUTTER_LO, BUTTER, t)


paint(roof, gore)
parts.append(roof)
parts.append(ring("RoofRim", HR + 1.25, RZ + 0.2, thick=0.3, pos=(0, HY), segs=24))
for k in range(10):
    a = (k + 0.5) * math.tau / 10
    parts.append(bulb(f"RimBulb{k}", (math.cos(a) * (HR + 1.55), HY + math.sin(a) * (HR + 1.55), RZ + 0.15), 0.22))
parts += trophy_slime(0, HY, RZ + 5.2, size=3.0)
# round porthole windows on the sides
for sx in (-1, 1):
    x = sx * (HR + 0.05)
    parts.append(gcyl(f"Port{sx}", 1.05, 0.4, (x - sx * 0.2, HY, BZ + 4.3), GOLD_LO, GOLD, segs=14, rot=(0, 90, 0)))
    parts.append(gcyl(f"PortIn{sx}", 0.8, 0.45, (x - sx * 0.2, HY, BZ + 4.3), rgb(150, 205, 240), rgb(200, 235, 255), segs=14, rot=(0, 90, 0)))

# ---- shop window and counter at the front ------------------------------------------------------------------
FY = HY - HR - 0.4
parts += counter("C", 7.6, FY - 0.8, 2.2, 4.1 - BZ, WOOD, LILAC_LO, LILAC, shade(mix(WOOD, PLAZA, 0.35), 0.85), mix(WOOD, PLAZA, 0.35), np_=7)
for p in parts[-11:]:
    p.location.z += BZ
parts.append(bbox("WinFrame", (8.6, 0.8, 0.8), (0, FY - 0.2, BZ + 6.0), GOLD_LO, GOLD, bev=0.12))
for sx in (-1, 1):
    parts.append(bbox(f"WinPost{sx}", (0.7, 0.8, 4.8), (sx * 3.95, FY - 0.2, BZ + 3.6), GOLD_LO, GOLD, bev=0.12))
parts.append(bbox("WinBack", (7.2, 0.3, 4.6), (0, FY + 1.2, BZ + 3.6), LILAC_LO, mix(LILAC, CREAM, 0.25), bev=0.06))
# little awning over the window
for k in range(6):
    x = -4.0 + 8.0 * (k + 0.5) / 6
    hi, lo = (BUTTER, BUTTER_LO) if k % 2 == 0 else (LILAC, LILAC_LO)
    parts.append(bbox(f"Awn{k}", (8.0 / 6 + 0.01, 1.8, 0.25), (x, FY - 1.0, BZ + 6.55), lo, hi, bev=0, rot=(-18, 0, 0)))
    sc = cylinder(f"AwnScal{k}", 8.0 / 12 - 0.03, 0.22, (x, FY - 1.85, BZ + 6.0), hi, segs=10, rot=(90, 0, 0))
    gradient(sc, mix(lo, hi, 0.5), hi)
    parts.append(sc)

# ---- rainbow arch over the front with the sign at its top ------------------------------------------------------
RAIN = [ROOF, rgb(252, 160, 70), BUTTER, GOO, rgb(110, 180, 245), LILAC]
AY = HY + 2.4             # behind the cottage: a backdrop, never in front of the counter
for i, col in enumerate(RAIN):
    rr = 8.4 - i * 0.45
    pts = [(math.cos(math.radians(a)) * rr, AY, BZ + 0.2 + math.sin(math.radians(a)) * rr * 1.3) for a in range(0, 181, 10)]
    parts.append(tube(f"Bow{i}", pts, [0.26] * len(pts), col, segs=6))
for sx in (-1, 1):
    for k in range(3):
        p = blob(f"BowCloud{sx}{k}", 1.0 - k * 0.15, (sx * (7.6 + k * 0.4), AY + (k - 1) * 0.6, BZ + 0.2 + k * 0.3), CLOUD, subdiv=2, jitter=0)
        gradient(p, CLOUD_LO, CLOUD)
        parts.append(p)
SZ = BZ + 7.5             # sign over the shop window, in front of the roof rim
parts.append(bbox("SignFrame", (6.4, 0.5, 1.7), (0, FY - 0.9, SZ), GOLD_LO, GOLD, bev=0.15))
parts.append(bbox("SignFace", (5.6, 0.3, 1.1), (0, FY - 1.12, SZ), LILAC_LO, LILAC, bev=0.06))

# ---- goo waterfall off the right side into a goo pool on the grass -----------------------------------------------
fx, fy = -7.6, -1.2
fall = []
for i in range(9):
    t = i / 8
    fall.append((fx - 1.5 * t * t, fy - 0.3 * t, BZ + 0.3 - 1.4 * t))
parts.append(tube("Fall", fall, [0.7 - 0.25 * (i / 8) for i in range(9)], GOO, segs=8))
pool = lathe("Pool", [(2.2, 0), (2.4, 0.15), (0, 0.22)], (fx - 1.7, fy - 0.3, 0), segs=16, col=GOO)
paint(pool, lambda c, n: mix(GOO, GOO_HI, 0.5) if n.z > 0.9 else GOO_LO)
parts.append(pool)

# ---- three floating display puffs round the cottage (pet clouds ride on them) ------------------------------------
for k, (x, y, z) in enumerate(((-6.2, -4.2, 5.6), (6.4, -3.6, 6.4), (5.4, 4.6, 7.6))):
    pf = blob(f"Float{k}", 1.0, (x, y, z), CLOUD, subdiv=2, jitter=0, squash=(1.3, 1.3, 0.55))
    gradient(pf, CLOUD_LO, CLOUD)
    parts.append(pf)
    parts.append(ring(f"FloatRing{k}", 1.5, z, thick=0.12, pos=(x, y), segs=18))
    DISPLAYS.append((x, y, z + 0.4))
    for j in range(3):
        parts.append(sparkle_star if False else bulb(f"Spark{k}{j}", (x + math.cos(j * 2.1) * 1.9, y + math.sin(j * 2.1) * 1.9, z + 0.6 + j * 0.3), 0.14))

xs, ys, zs = [], [], []
for o in parts:
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        xs.append(w.x); ys.append(w.y); zs.append(w.z)
OFF = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs))
DISPLAYS = [(round(x - OFF[0], 2), round(y - OFF[1], 2), round(z - OFF[2], 2)) for x, y, z in DISPLAYS]
finish("exclusive_cloud_nine", parts)
