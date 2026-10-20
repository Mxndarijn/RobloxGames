# ranch_item_shop: the Item Shop, an open market stall full of goods (vs ranch_upgrade_shop, a closed workshop).
# Reads as "things you buy and carry": pink / butter striped awning, goods piled on and around the counter
# (egg crate, padlock, speed coil, barrels, sack), a big spotted Mystery Egg on top of the sign.
# Same counter as ranch_shop_stand: 10.4 wide, top at z 4.1 (prompts go on a Counter part placed over it).
# Sign face (blank for SurfaceGui "ITEM SHOP"): 7.6 x 2.0. In the exported mesh frame (bbox 15.39 x 8.15 x 16.56,
# origin bottom centre): face centre x 0.06, z 11.53; its outer face is 2.28 behind the bbox centre, 6.35 behind
# the bbox front. Front faces -Y.
import math
from lib import *
from models._phoenix_ranch import *
from models._shop_parts import *

PINK_LO = mix(PINK, ROOF, 0.35)
BUTTER_LO = mix(BUTTER, WOOD, 0.3)
W = 10.4
X = W / 2
CY, CD, CH = -1.2, 3.6, 3.6
BY = 2.4
parts = []

parts += counter("C", W, CY, CD, CH, WOOD, PINK_LO, PINK, BUTTER_LO, BUTTER)

# posts: front lower, the awning slopes to the front
FZ, BZ = 8.6, 10.2
for sx in (-1, 1):
    parts.append(bbox(f"PostF{sx}", (0.9, 0.9, FZ), (sx * X, CY - CD / 2 - 0.1, FZ / 2), WOOD_LO, WOOD, bev=0.15))
    parts.append(bbox(f"PostB{sx}", (0.9, 0.9, 12.6), (sx * X, BY, 6.3), WOOD_LO, WOOD, bev=0.15))
    parts.append(bbox(f"Foot{sx}", (1.4, 1.4, 0.5), (sx * X, CY - CD / 2 - 0.1, 0.25), shade(WOOD_D, 0.9), WOOD_D, bev=0.12))

# back wall with two shelves of goods
for k in range(8):
    x = -X + 0.45 + (W - 0.9) * (k + 0.5) / 8
    c = WOOD if k % 2 else mix(WOOD, CREAM, 0.12)
    parts.append(bbox(f"Wall{k}", ((W - 0.9) / 8 - 0.06, 0.5, BZ - 0.4), (x, BY, (BZ - 0.4) / 2), WOOD_LO, c, bev=0))
parts.append(box("WallCore", (W - 1.0, 0.3, BZ - 0.5), (0, BY, (BZ - 0.5) / 2), WOOD_LO))
for k, z in enumerate((5.4, 7.6)):
    parts.append(bbox(f"Shelf{k}", (W - 1.0, 1.2, 0.35), (0, BY - 0.8, z), PINK_LO, PINK, bev=0.08))
for k, col in enumerate((GOO, BUTTER, LILAC, PINK, GOO)):     # lower shelf: goo jars
    x = -3.6 + k * 1.8
    parts.append(gcyl(f"Jar{k}", 0.5, 1.0, (x, BY - 0.8, 5.57), shade(col, 0.85), col))
    parts.append(cylinder(f"Lid{k}", 0.56, 0.25, (x, BY - 0.8, 6.55), CREAM, segs=8))
for k in range(4):                                              # upper shelf: little gift boxes
    x = -3.3 + k * 2.2
    col = (PINK, BUTTER, GOO, LILAC)[k]
    parts.append(bbox(f"Gift{k}", (1.1, 0.9, 0.9), (x, BY - 0.8, 8.25), shade(col, 0.85), col, bev=0.08))
    parts.append(box(f"Ribbon{k}", (0.22, 0.95, 0.95), (x, BY - 0.8, 8.25), CREAM))

# goods on the counter top: hay crate of eggs (left), padlock (middle), speed coil (right)
T = CH + 0.5
parts.append(bbox("Crate", (2.6, 1.8, 0.9), (-3.2, CY + 0.2, T + 0.45), WOOD_LO, WOOD, bev=0.08))
parts.append(bbox("Hay", (2.3, 1.5, 0.3), (-3.2, CY + 0.2, T + 0.9), BUTTER_LO, BUTTER, bev=0.06))
for k, (dx, col) in enumerate(((-0.7, CREAM), (0.0, PINK), (0.7, LILAC))):
    parts.append(blob(f"Egg{k}", 0.42, (-3.2 + dx, CY + 0.2, T + 1.35), col, subdiv=2, squash=(1, 1, 1.3), jitter=0))
# padlock: brass body + shackle
parts.append(bbox("LockBody", (1.2, 0.6, 1.0), (-0.3, CY - 0.4, T + 0.5), shade(METAL, 0.85), BUTTER, bev=0.12))
parts.append(tube("Shackle", [(-0.7, CY - 0.4, T + 0.95), (-0.7, CY - 0.4, T + 1.5), (-0.3, CY - 0.4, T + 1.8),
                              (0.1, CY - 0.4, T + 1.5), (0.1, CY - 0.4, T + 0.95)], [0.13] * 5, METAL, segs=6))
parts.append(box("Keyhole", (0.2, 0.1, 0.35), (-0.3, CY - 0.72, T + 0.45), WOOD_D))
# speed coil: a fat spring on a little base, goo tipped
pts, rad = [], []
for i in range(25):
    a = i / 24 * math.tau * 3.5
    pts.append((2.4 + 0.5 * math.cos(a), CY - 0.1 + 0.5 * math.sin(a), T + 0.35 + i * 0.065))
    rad.append(0.14)
parts.append(gcyl("CoilBase", 0.75, 0.3, (2.4, CY - 0.1, T), shade(METAL, 0.8), METAL, segs=10))
parts.append(tube("Coil", pts, rad, BUTTER, segs=5))
parts.append(blob("CoilTip", 0.32, (2.4, CY - 0.1, T + 2.05), GOO, subdiv=2, jitter=0))

# striped awning: pink / butter, scalloped valance
y0, y1 = CY - CD / 2 - 1.4, BY + 0.6
run = math.hypot(y1 - y0, BZ - FZ)
ang = math.degrees(math.atan2(BZ - FZ, y1 - y0))
NS, AW = 7, W + 2.0
sw = AW / NS
for k in range(NS):
    x = -AW / 2 + sw * (k + 0.5)
    hi = PINK if k % 2 == 0 else BUTTER
    lo = PINK_LO if k % 2 == 0 else BUTTER_LO
    parts.append(bbox(f"Stripe{k}", (sw + 0.01, run, 0.4), (x, (y0 + y1) / 2, (FZ + BZ) / 2 + 0.2), lo, hi, bev=0, rot=(ang, 0, 0)))
    parts.append(bbox(f"Flap{k}", (sw - 0.04, 0.3, 0.7), (x, y0 - 0.05, FZ - 0.15), lo, hi, bev=0))
    sc = cylinder(f"Scal{k}", sw / 2 - 0.02, 0.3, (x, y0 + 0.1, FZ - 0.5), hi, segs=10, rot=(90, 0, 0))
    gradient(sc, mix(lo, hi, 0.6), hi)
    parts.append(sc)

# sign over the awning: pink frame, butter face, Mystery Egg on top
SZ = 11.4
parts.append(bbox("SignFrame", (8.6, 0.6, 3.0), (0, BY - 0.1, SZ), PINK_LO, PINK, bev=0.15))
parts.append(bbox("SignFace", (7.6, 0.3, 2.0), (0, BY - 0.5, SZ), BUTTER_LO, BUTTER, bev=0.06))
parts.append(bbox("EggNest", (2.6, 1.4, 0.5), (0, BY - 0.1, SZ + 1.75), BUTTER_LO, BUTTER, bev=0.15))
egg = blob("BigEgg", 1.25, (0, BY - 0.1, SZ + 3.4), CREAM, subdiv=2, squash=(1, 1, 1.3), jitter=0)
gradient(egg, mix(CREAM, LILAC, 0.5), CREAM)
parts.append(egg)
for k, (dx, dz, col) in enumerate(((-0.5, 3.0, PINK), (0.45, 3.8, LILAC), (0.5, 2.7, GOO), (-0.35, 4.2, PINK))):
    parts.append(blob(f"Spot{k}", 0.34, (dx, BY - 1.05 - 0.25 * (1 - abs(dx)), SZ + dz), col, subdiv=1, squash=(1, 0.5, 1), jitter=0))

# goods on the ground: barrels left, sack + crate right
for k, (x, y) in enumerate(((-X - 1.6, CY - 0.6), (-X - 1.3, CY + 1.5))):
    parts.append(gcyl(f"Barrel{k}", 0.95, 2.2, (x, y, 0), WOOD_LO, WOOD, segs=10))
    for j, z in enumerate((0.4, 1.7)):
        parts.append(cylinder(f"Hoop{k}{j}", 1.0, 0.2, (x, y, z), METAL, segs=10))
    parts.append(cylinder(f"BarrelGoo{k}", 0.8, 0.15, (x, y, 2.2), (GOO, PINK)[k], segs=10))
sack = blob("Sack", 0.95, (X + 1.5, CY - 0.4, 0.85), BUTTER_LO, subdiv=2, squash=(1, 0.9, 1.0), jitter=0.05)
gradient(sack, shade(BUTTER_LO, 0.85), BUTTER_LO)
parts.append(sack)
parts.append(blob("SackTie", 0.35, (X + 1.5, CY - 0.4, 1.85), PINK, subdiv=1, jitter=0))
parts.append(bbox("GroundCrate", (1.7, 1.7, 1.5), (X + 1.4, CY + 1.6, 0.75), WOOD_LO, WOOD, bev=0.1))
parts.append(blob("CrateEgg", 0.45, (X + 1.4, CY + 1.6, 1.85), LILAC, subdiv=2, squash=(1, 1, 1.3), jitter=0))

finish("ranch_item_shop", parts)
