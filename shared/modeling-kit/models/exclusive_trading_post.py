# exclusive_trading_post (concept): the Exclusive Shop as a chunky two-storey ranch boutique. Wood plank ground floor
# with an open counter under a lilac / butter awning, a lilac-painted upper floor that overhangs with three round
# display windows (the exclusive clouds sit behind them: DISPLAYS), a red ranch gable roof with a gold ridge, a big gold
# star crest on the gable over the sign, goo barrels and gift crates out front. Glass is its own mesh.
import math
from lib import *
from models._phoenix_ranch import *
from models._shop_parts import counter, prism, gcyl
from models._shop_kit import *

parts, glassy = [], []
DISPLAYS = []
HW, D = 7.0, 9.0          # half width, depth
GZ = 7.4                  # ground floor height
UZ = 13.0                 # upper floor top
FY = -D / 2               # front face y

# ---- ground floor: plank walls on three sides, open front, corner posts ----------------------------------------
parts.append(bbox("Floor", (2 * HW + 1.0, D + 1.0, 0.6), (0, 0, 0.3), WOOD_LO, mix(WOOD, PLAZA, 0.3), bev=0.15))
for k in range(9):
    z = 0.6 + k * (GZ - 0.6) / 9
    h = (GZ - 0.6) / 9 - 0.08
    c = WOOD if k % 2 else PLANK
    for sx in (-1, 1):
        parts.append(bbox(f"Side{sx}{k}", (0.5, D, h), (sx * HW, 0, z + h / 2), shade(c, 0.86), c, bev=0.05))
    parts.append(bbox(f"Back{k}", (2 * HW, 0.5, h), (0, D / 2, z + h / 2), shade(c, 0.86), c, bev=0.05))
for sx in (-1, 1):
    for y in (FY, D / 2):
        parts.append(bbox(f"Post{sx}{y:.0f}", (1.1, 1.1, GZ + 0.2), (sx * HW, y, (GZ + 0.2) / 2), shade(WOOD_D, 0.9), WOOD_D, bev=0.15))
parts += counter("C", 10.4, FY + 0.4, 2.6, 3.6, WOOD, LILAC_LO, LILAC, shade(mix(WOOD, PLAZA, 0.35), 0.85), mix(WOOD, PLAZA, 0.35), np_=9)
# back shelf with gift boxes and goo jars behind the counter
parts.append(bbox("Shelf", (2 * HW - 1.4, 1.2, 0.35), (0, D / 2 - 0.9, 5.4), LILAC_LO, LILAC, bev=0.08))
for k, col in enumerate((PINK, BUTTER, GOO, LILAC, PINK)):
    x = -4.4 + k * 2.2
    parts.append(bbox(f"Gift{k}", (1.0, 0.9, 0.9), (x, D / 2 - 0.9, 6.05), shade(col, 0.85), col, bev=0.08))
    parts.append(box(f"Ribbon{k}", (0.2, 0.95, 0.95), (x, D / 2 - 0.9, 6.05), GOLD))

# ---- awning over the counter ------------------------------------------------------------------------------
NS = 8
for k in range(NS):
    x = -HW - 0.5 + (2 * HW + 1.0) * (k + 0.5) / NS
    hi, lo = (LILAC, LILAC_LO) if k % 2 == 0 else (BUTTER, BUTTER_LO)
    parts.append(bbox(f"Awn{k}", ((2 * HW + 1) / NS + 0.01, 2.6, 0.3), (x, FY - 1.1, GZ - 0.4), lo, hi, bev=0, rot=(-20, 0, 0)))
    sc = cylinder(f"AwnScal{k}", (2 * HW + 1) / NS / 2 - 0.03, 0.24, (x, FY - 2.35, GZ - 1.25), hi, segs=10, rot=(90, 0, 0))
    gradient(sc, mix(lo, hi, 0.5), hi)
    parts.append(sc)

# ---- upper floor: overhanging, lilac boards, gold trim, three round display windows ---------------------------
parts.append(bbox("Joist", (2 * HW + 1.6, D + 1.6, 0.6), (0, 0, GZ + 0.3), shade(WOOD_D, 0.9), WOOD_D, bev=0.12))
UY0 = FY - 0.8
for k in range(7):
    z = GZ + 0.6 + k * (UZ - GZ - 0.6) / 7
    h = (UZ - GZ - 0.6) / 7 - 0.07
    c = LILAC if k % 2 else mix(LILAC, CREAM, 0.15)
    parts.append(bbox(f"UFront{k}", (2 * HW + 0.8, 0.5, h), (0, UY0, z + h / 2), shade(c, 0.85), c, bev=0.04))
    for sx in (-1, 1):
        parts.append(bbox(f"USide{sx}{k}", (0.5, D + 0.8, h), (sx * (HW + 0.4), 0.0, z + h / 2), shade(c, 0.85), c, bev=0.04))
    parts.append(bbox(f"UBack{k}", (2 * HW + 0.8, 0.5, h), (0, D / 2 + 0.4, z + h / 2), shade(c, 0.85), c, bev=0.04))
parts.append(box("UCore", (2 * HW, D - 2.6, UZ - GZ - 0.8), (0, 1.5, (GZ + UZ) / 2 + 0.2), LILAC_LO))
WZc = GZ + (UZ - GZ) / 2 + 0.2
for k, x in enumerate((-4.3, 0.0, 4.3)):
    r = 1.75 if k == 1 else 1.45
    frame = gcyl(f"WinFrame{k}", r + 0.35, 0.5, (x, UY0 - 0.25, WZc), GOLD_LO, GOLD, segs=16, rot=(90, 0, 0))
    paint(frame, lambda c, n: GOLD_HI if n.z > 0.5 else GOLD)
    parts.append(frame)
    # a bubble window bulging out of the wall: butter back plate, goo shelf, the cloud sits inside the glass
    parts.append(gcyl(f"Niche{k}", r - 0.05, 0.2, (x, UY0 - 0.35, WZc), mix(BUTTER, CREAM, 0.4), mix(BUTTER, CREAM, 0.6), segs=16, rot=(90, 0, 0)))
    parts.append(bbox(f"NicheGoo{k}", (2 * r - 0.6, 1.2, 0.3), (x, UY0 - 0.9, WZc - r * 0.55), GOO_LO, GOO, bev=0.1))
    glassy.append(glass(blob(f"Bubble{k}", r + 0.05, (x, UY0 - 0.4, WZc), GLASS, subdiv=2, squash=(1, 0.85, 1), jitter=0), 0.8))
    DISPLAYS.append((x, UY0 - 0.95, WZc - r * 0.55 + 0.15))
# balcony rail along the upper floor front
for k in range(13):
    x = -HW - 0.2 + k * (2 * HW + 0.4) / 12
    parts.append(gcyl(f"Bal{k}", 0.13, 1.0, (x, UY0 - 1.0, GZ + 0.6), WOOD_LO, WOOD, segs=5))
parts.append(bbox("BalRail", (2 * HW + 0.8, 0.35, 0.3), (0, UY0 - 1.0, GZ + 1.7), GOLD_LO, GOLD, bev=0.08))
parts.append(bbox("BalFloor", (2 * HW + 1.2, 1.4, 0.3), (0, UY0 - 0.8, GZ + 0.6), shade(WOOD_D, 0.9), WOOD_D, bev=0.08))

# ---- roof: red gable along x, shingle rows, gold ridge, gold star crest + sign on the front gable ---------------
RW, RH = HW + 1.4, 5.2
ang = math.degrees(math.atan2(RH, RW))
LS = math.hypot(RH, RW)
for side in (-1, 1):   # left / right slopes, ridge front to back, the gable faces the plaza
    for r in range(5):
        t = (r + 0.5) / 5
        c = ROOF if r % 2 else mix(ROOF, PINK, 0.15)
        parts.append(bbox(f"Shingle{side}{r}", (LS / 5 + 0.3, D + 2.6, 0.45), (side * RW * (1 - t), 0.2, UZ + 0.2 + RH * t + 0.08 * (r % 2)),
                          ROOF_D, c, bev=0.1, rot=(0, side * ang, 0)))
parts.append(gcyl("Ridge", 0.45, D + 3.0, (0, -D / 2 - 1.3, UZ + RH + 0.25), GOLD_LO, GOLD, segs=8, rot=(-90, 0, 0)))
gable = [(-HW - 0.4, UZ), (HW + 0.4, UZ), (0, UZ + RH - 0.2)]
parts.append(prism("GableF", gable, UY0 - 0.25, UY0 + 0.25, LILAC_LO, LILAC))
parts.append(prism("GableB", gable, D / 2 + 0.15, D / 2 + 0.65, LILAC_LO, LILAC))
# star crest standing on the front of the roof
CZ = UZ + RH + 1.6
st = [(math.cos(math.radians(90 + i * 36)) * (2.4 if i % 2 == 0 else 1.05), CZ + math.sin(math.radians(90 + i * 36)) * (2.4 if i % 2 == 0 else 1.05)) for i in range(10)]
parts.append(prism("Star", st, UY0 - 0.3, UY0 + 0.3, GOLD_LO, GOLD))
st2 = [(x * 0.62, CZ + (z - CZ) * 0.62) for x, z in st]
parts.append(prism("StarIn", st2, UY0 - 0.45, UY0 - 0.25, GOLD, GOLD_HI))
for k in range(10):
    a = math.radians(90 + k * 36)
    if k % 2 == 0:
        parts.append(bulb(f"StarBulb{k}", (math.cos(a) * 2.6, UY0 - 0.4, CZ + math.sin(a) * 2.6), 0.24))
# sign on the gable under the star (SurfaceGui "EXCLUSIVE")
parts.append(bbox("SignFrame", (7.0, 0.5, 1.9), (0, UY0 - 0.5, UZ + 1.5), GOLD_LO, GOLD, bev=0.15))
parts.append(bbox("SignFace", (6.2, 0.3, 1.3), (0, UY0 - 0.72, UZ + 1.5), LILAC_LO, LILAC, bev=0.06))

# ---- out front: goo barrels and gift crates, two lanterns ---------------------------------------------------
for k, (x, y) in enumerate(((-HW - 1.6, FY - 0.6), (-HW - 1.2, FY + 1.6))):
    parts.append(gcyl(f"Barrel{k}", 0.95, 2.2, (x, y, 0), WOOD_LO, WOOD, segs=10))
    for j, z in enumerate((0.4, 1.7)):
        parts.append(cylinder(f"Hoop{k}{j}", 1.0, 0.2, (x, y, z), GOLD, segs=10))
    parts.append(goo_ring(f"BarrelGoo{k}", x, y, 2.05, 0.85, n=20, seed=k + 2, drip=(0.3, 0.8), thick=0.9))
parts.append(bbox("Crate", (1.7, 1.7, 1.5), (HW + 1.5, FY + 0.4, 0.75), WOOD_LO, WOOD, bev=0.1))
parts.append(bbox("Gift", (1.2, 1.2, 1.0), (HW + 1.5, FY + 0.4, 2.0), shade(PINK, 0.85), PINK, bev=0.1))
parts.append(box("GiftRibbon", (0.25, 1.25, 1.05), (HW + 1.5, FY + 0.4, 2.0), GOLD))
for sx in (-1, 1):
    x = sx * (HW + 0.0)
    parts.append(gcyl(f"LampCage{sx}", 0.5, 0.9, (x, FY - 0.7, GZ - 2.8), GOLD_LO, GOLD, segs=6))
    parts.append(blob(f"LampGoo{sx}", 0.34, (x, FY - 0.7, GZ - 2.35), mix(GOO_HI, BUTTER, 0.3), subdiv=1, jitter=0))
    parts.append(cone(f"LampHat{sx}", 0.62, 0.5, (x, FY - 0.7, GZ - 1.9), GOLD, segs=6))

xs, ys, zs = [], [], []
for o in parts + glassy:
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        xs.append(w.x); ys.append(w.y); zs.append(w.z)
OFF = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs))
DISPLAYS = [(round(x - OFF[0], 2), round(y - OFF[1], 2), round(z - OFF[2], 2)) for x, y, z in DISPLAYS]
finish("exclusive_trading_post", parts)
g = finish("exclusive_trading_post_glass", glassy)
g["rbx_transparency"] = 0.8
