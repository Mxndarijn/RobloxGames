# habitat_prop_flan: a big caramel spoon leaning on a small dish for the Flan slime. The dish holds a tiny
# wobbly flan (custard with a caramel top and drips) so the idea reads at a glance.
import math
from lib import *
from models._habitat_prop import *

DISH_LO, DISH_HI = rgb(200, 214, 236), rgb(250, 252, 255)
CUSTARD_LO, CUSTARD_HI = rgb(248, 196, 80), rgb(255, 226, 120)
CARAMEL, CARAMEL_LO = rgb(206, 108, 34), rgb(170, 78, 26)
SPOON_LO, SPOON_HI = rgb(222, 140, 46), rgb(250, 190, 84)

DX = -0.32  # dish centre x (spoon leans in from the right)
parts = [lathe("Dish", [(0, 0), (0.34, 0), (0.40, 0.04), (0.51, 0.10), (0.53, 0.13), (0.46, 0.12), (0.30, 0.08), (0, 0.08)],
               segs=16, pos=(DX, 0, 0), color_fn=vgrad(DISH_LO, DISH_HI, 0, 0.13))]
# flan: frustum of custard, caramel cap
FB, FT = 0.08, 0.50
parts.append(lathe("Custard", [(0, FB), (0.34, FB), (0.31, FT - 0.08), (0.27, FT - 0.04), (0, FT - 0.04)], segs=14,
                   pos=(DX, 0, 0), color_fn=vgrad(CUSTARD_LO, CUSTARD_HI, FB, FT)))
parts.append(lathe("Caramel", [(0, FT - 0.06), (0.285, FT - 0.06), (0.29, FT - 0.02), (0.24, FT + 0.01), (0, FT + 0.02)], segs=14,
                   pos=(DX, 0, 0), color_fn=lambda i, k, z: CARAMEL if i else CARAMEL_LO))
# caramel drips down the custard
for j, a in enumerate([200, 250, 300, 345, 30, 140]):
    ar = math.radians(a)
    L = 0.12 + 0.07 * ((j * 7) % 3)
    r0 = 0.285
    pts = [(DX + math.cos(ar) * r0, math.sin(ar) * r0, FT - 0.04), (DX + math.cos(ar) * (r0 + 0.012), math.sin(ar) * (r0 + 0.012), FT - 0.04 - L)]
    parts.append(tube(f"Drip{j}", pts, [0.045, 0.035], CARAMEL, segs=6))

# spoon: oval bowl + long handle, bowl down on the deck right of the dish, handle leaning up onto the dish rim
spoon = []
bowl = lathe("Bowl", [(0, 0), (0.12, 0.004), (0.2, 0.03), (0.23, 0.07), (0.2, 0.075), (0.11, 0.04), (0, 0.035)], segs=12,
             color_fn=lambda i, k, z: SPOON_HI if i >= 4 else SPOON_LO)
spoon.append(xf(bowl, (0, 0, 0), (0, 0, 0), (1.0, 1.35, 1.0)))
spoon.append(lathe("Fill", [(0, 0.04), (0.17, 0.05), (0.18, 0.06), (0, 0.065)], segs=12, color_fn=lambda i, k, z: CARAMEL))
spoon[-1].data.transform(__import__("mathutils").Matrix.Diagonal((1.0, 1.35, 1.0, 1.0)))
spoon.append(tube("Handle", [(0, 0.28, 0.06), (0, 0.55, 0.08), (0, 0.95, 0.09), (0, 1.05, 0.09)], [0.05, 0.045, 0.06, 0.04], segs=6))
regrad(spoon[-1], SPOON_LO, SPOON_HI, 0.0, 0.1)
# lean: spoon lies along +Y, rotate so the handle points up-left onto the dish, bowl on the deck at the right
for o in spoon:
    xf(o, (0, 0, 0), (0, 0, 0), (1.15, 1.15, 1.15))  # r02: a BIG spoon
    xf(o, (0, 0, 0), (34, 0, 0))  # handle up
    xf(o, (0.56, -0.08, 0.03), (0, 0, 90))  # handle points to -X (toward the dish)
parts += spoon

ship("habitat_prop_flan", parts)
