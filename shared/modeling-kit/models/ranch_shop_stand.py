# ranch_shop_stand: Slime Ranch market stall replacing the greybox ShopStand (Props.shopStand:
# counter 10 x 3.7 x 4, back wall 9 tall, striped awning ~9.4, SHOP sign 7 x 1.8 at ~10.8).
# Plank counter with a cream top, barn-red / cream striped awning with a scalloped valance,
# back wall with a shelf of goo jars, butter SHOP sign board on top. Front faces -Y.
# Sign face (blank for SurfaceGui "SHOP"): 7.6 x 2.0, centre z 12.2, outer face y = 1.75.
# Counter top: 11 x 4.2, top at z 4.1 (prompts go on a Counter part placed over it in-game).
import math
from lib import *
from models._phoenix_ranch import *

LILAC = PALETTE["ranch_lilac"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
CREAM_LO = mix(CREAM, WOOD, 0.25)
BUTTER_LO = mix(BUTTER, WOOD, 0.25)
ROOF_LO = mix(ROOF_D, ROOF, 0.5)
W = 10.4                     # stall width (post centres at +-X)
X = W / 2
CY, CD, CH = -1.2, 3.6, 3.6  # counter centre y, depth, height
BY = 2.4                     # back wall centre y
parts = []

# counter: core, vertical front planks, cream band + top
parts.append(bbox("CounterCore", (W - 0.6, CD, CH), (0, CY, CH / 2), WOOD_LO, WOOD, bev=0.1))
NP = 9
for k in range(NP):
    x = -X + 0.3 + (W - 0.6) * (k + 0.5) / NP
    c = WOOD if k % 2 else mix(WOOD, CREAM, 0.12)
    h = CH - 0.6 + 0.08 * ((k * 5) % 3 - 1)
    parts.append(bbox(f"Plank{k}", ((W - 0.6) / NP - 0.08, 0.4, h), (x, CY - CD / 2 - 0.1, h / 2 + 0.1), WOOD_LO, c, bev=0))   # r02: no bevel (tris)
parts.append(bbox("Band", (W - 0.4, 0.5, 0.6), (0, CY - CD / 2 - 0.2, CH - 0.25), CREAM_LO, CREAM, bev=0.1))
parts.append(bbox("Top", (W + 0.6, CD + 0.6, 0.5), (0, CY, CH + 0.25), CREAM_LO, CREAM, bev=0.15))

# corner posts: front shorter (awning slopes down to the front)
FZ, BZ = 9.0, 11.0           # awning front / back heights
for sx in (-1, 1):
    parts.append(bbox(f"PostF{sx}", (0.9, 0.9, FZ), (sx * X, CY - CD / 2 - 0.1, FZ / 2), WOOD_LO, WOOD, bev=0.15))
    parts.append(bbox(f"PostB{sx}", (0.9, 0.9, 13.4), (sx * X, BY, 6.7), WOOD_LO, WOOD, bev=0.15))
    parts.append(bbox(f"CapB{sx}", (1.3, 1.3, 0.4), (sx * X, BY, 13.6), CREAM_LO, CREAM, bev=0.12))
    parts.append(bbox(f"Foot{sx}", (1.4, 1.4, 0.5), (sx * X, CY - CD / 2 - 0.1, 0.25), shade(WOOD_D, 0.9), WOOD_D, bev=0.12))

# back wall: vertical boards + cream shelf with goo jars
for k in range(8):
    x = -X + 0.45 + (W - 0.9) * (k + 0.5) / 8
    c = WOOD if k % 2 else mix(WOOD, CREAM, 0.12)
    parts.append(bbox(f"Wall{k}", ((W - 0.9) / 8 - 0.06, 0.5, BZ - 0.4), (x, BY, (BZ - 0.4) / 2), WOOD_LO, c, bev=0))
parts.append(box("WallCore", (W - 1.0, 0.3, BZ - 0.5), (0, BY, (BZ - 0.5) / 2), WOOD_LO))   # r04: board gaps showed jars from behind
for k, z in enumerate((2.5, 8.0)):   # cream battens on the back (plaza side)
    parts.append(bbox(f"Batten{k}", (W - 1.0, 0.3, 0.7), (0, BY + 0.38, z), CREAM_LO, CREAM, bev=0.08))
parts.append(bbox("Shelf", (W - 1.0, 1.2, 0.35), (0, BY - 0.8, 7.0), CREAM_LO, CREAM, bev=0.08))
JARS = [GOO, PINK, BUTTER, LILAC, GOO]
for k, col in enumerate(JARS):
    x = -3.6 + k * 1.8
    parts.append(cylinder(f"Jar{k}", 0.5, 1.0, (x, BY - 0.8, 7.17), col, segs=8))
    parts.append(cylinder(f"Lid{k}", 0.56, 0.25, (x, BY - 0.8, 8.15), CREAM, segs=8))
# goo jars on the counter top
for k, (x, col) in enumerate(((-3.4, GOO), (-2.3, PINK), (3.2, LILAC))):
    parts.append(cylinder(f"CJar{k}", 0.55, 1.1, (x, CY + 0.6, CH + 0.48), col, segs=8))
    parts.append(cylinder(f"CLid{k}", 0.62, 0.28, (x, CY + 0.6, CH + 1.55), CREAM, segs=8))

# striped awning: 7 stripes from the back (BZ) down to the front (FZ), barn red / cream
y0, y1 = CY - CD / 2 - 1.2, BY + 0.6       # front / back edge y
run = math.hypot(y1 - y0, BZ - FZ)
ang = math.degrees(math.atan2(BZ - FZ, y1 - y0))
NS, AW = 7, W + 1.6
sw = AW / NS
for k in range(NS):
    x = -AW / 2 + sw * (k + 0.5)
    hi = ROOF if k % 2 == 0 else CREAM
    lo = ROOF_LO if k % 2 == 0 else CREAM_LO
    parts.append(bbox(f"Stripe{k}", (sw + 0.01, run, 0.4), (x, (y0 + y1) / 2, (FZ + BZ) / 2 + 0.2), lo, hi, bev=0, rot=(ang, 0, 0)))
    # scalloped valance: flap + half-round hanging off the front edge
    parts.append(bbox(f"Flap{k}", (sw - 0.04, 0.3, 0.7), (x, y0 - 0.05, FZ - 0.15), lo, hi, bev=0))
    sc = cylinder(f"Scal{k}", sw / 2 - 0.02, 0.3, (x, y0 + 0.1, FZ - 0.5), hi, segs=10, rot=(90, 0, 0))
    gradient(sc, mix(lo, hi, 0.6), hi)   # r03: flat lo went maroon / grey
    parts.append(sc)

# SHOP sign over the awning, on the back posts: wood frame, butter face, red roof cap
SZ = 12.2
parts.append(bbox("SignFrame", (8.6, 0.6, 3.0), (0, BY - 0.1, SZ), shade(WOOD_D, 0.9), WOOD_D, bev=0.15))
parts.append(bbox("SignFace", (7.6, 0.3, 2.0), (0, BY - 0.5, SZ), BUTTER_LO, BUTTER, bev=0.06))   # r03: was flush with the frame
parts.append(bbox("SignCap", (9.4, 1.2, 0.5), (0, BY - 0.1, SZ + 1.7), ROOF_LO, ROOF, bev=0.15))

finish("ranch_shop_stand", parts)
