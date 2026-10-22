# merge_vat: copper goo cauldron for the 3-slime merge vat (9.6 x 7.2 x 9.6 studs, ~1.5k tris).
# Runtime-only (MergeVat3): the client stands it over the owner's plot MergeVat disc (dia 9, top at 4 studs above the
# plot floor, so the cauldron mouth sits at ~4.6 and the goo dome at ~5.2). Three funnel cups round the rim are the
# three slime seats: each holds a goo pool (top at CUP_SEAT_Z, radius 1.05) that a slime in the vat sits on
# (VatDecor.CUPS in the game mirrors CUP_RADIUS / CUP_SEAT_Z). Goo bubbles in the middle and drips over the lip.
# Origin bottom centre, 1 BU = 1 stud.
import math
from lib import *
from models._phoenix_pad import lathe

COP, COP_D, COP_HI = rgb(214, 128, 68), rgb(160, 92, 54), rgb(240, 166, 98)
BRASS, BRASS_D = rgb(250, 204, 92), rgb(196, 150, 60)
GOO, GOO_HI = rgb(104, 226, 160), rgb(200, 252, 222)
parts = []

# body: foot ring, belly, shoulder, lip (profile = (radius, z) from the bottom axis point up)
BODY = [(0, 0), (3.6, 0), (4.0, 0.25), (4.15, 0.9), (4.5, 2.2), (4.65, 3.4), (4.35, 4.5), (4.6, 4.75), (4.45, 5.0), (3.9, 4.85), (0, 4.85)]
def body_col(i, k, z):
    if i in (1, 2):
        return COP_D
    if i in (7, 8):
        return BRASS
    return mix(COP_D, COP_HI, min(1, z / 4.5)) if (k % 2) else mix(COP_D, COP, min(1, z / 4.5))
parts.append(lathe("Body", BODY, segs=16, color_fn=body_col))
# goo dome in the mouth
DOME = [(0, 4.6), (3.95, 4.6), (3.9, 4.95), (3.4, 5.35), (2.4, 5.65), (1.2, 5.8), (0, 5.85)]
parts.append(lathe("Goo", DOME, segs=16, color_fn=lambda i, k, z: GOO_HI if i >= 4 else mix(GOO, GOO_HI, 0.4)))
# brass bands round the belly
for z0, r in ((1.2, 4.32), (3.0, 4.66)):
    parts.append(lathe(f"Band{z0}", [(0, z0), (r + 0.04, z0), (r + 0.18, z0 + 0.12), (r + 0.18, z0 + 0.42), (r + 0.04, z0 + 0.54), (0, z0 + 0.54)], segs=16,
                       color_fn=lambda i, k, z: BRASS if i != 2 else BRASS_D))
# three funnel cups on the rim, one per slime seat, each with a goo pool to sit on (no gem: the slime is the topper)
CUP_RADIUS, CUP_SEAT_Z = 4.45, 6.25
for i in range(3):
    a = math.radians(90 + i * 120)
    x, y = math.cos(a) * CUP_RADIUS, math.sin(a) * CUP_RADIUS
    parts.append(lathe(f"Spout{i}", [(0, 4.5), (0.9, 4.5), (0.95, 5.1), (1.45, 6.0), (1.55, 6.5), (1.2, 6.55), (0.75, 5.35), (0, 5.3)], segs=10,
                       pos=(x, y, 0), color_fn=lambda i2, k, z: BRASS if i2 >= 3 else COP_HI))
    parts.append(lathe(f"Seat{i}", [(0, 5.5), (0.98, 5.5), (1.06, 6.1), (0.8, 6.2), (0, CUP_SEAT_Z)], segs=10,
                       pos=(x, y, 0), color_fn=lambda i2, k, z: GOO_HI if i2 >= 3 else GOO))
# goo bubbles popping in the middle
for i, (bx, by, br) in enumerate(((0.4, 0.3, 0.9), (-1.1, -0.7, 0.62), (1.3, -0.9, 0.5))):
    parts.append(blob(f"Bub{i}", br, (bx, by, 5.9 + br * 0.45), GOO_HI, subdiv=2, squash=(1, 1, 0.9), jitter=0.02, seed=i))
# goo drips over the lip
for i, deg in enumerate((20, 140, 250)):
    a = math.radians(deg)
    parts.append(tube(f"Drip{i}", [(math.cos(a) * 4.5, math.sin(a) * 4.5, 4.8), (math.cos(a) * 4.78, math.sin(a) * 4.78, 3.6)], [0.34, 0.24], GOO, segs=5))
    parts.append(blob(f"DripEnd{i}", 0.3, (math.cos(a) * 4.78, math.sin(a) * 4.78, 3.55), GOO_HI, subdiv=1, jitter=0))
# three stubby feet
for i in range(3):
    a = math.radians(30 + i * 120)
    parts.append(box(f"Foot{i}", (1.1, 1.1, 0.5), (math.cos(a) * 4.0, math.sin(a) * 4.0, 0.25), COP_D, rot=(0, 0, math.degrees(a))))
finish("merge_vat", parts)
