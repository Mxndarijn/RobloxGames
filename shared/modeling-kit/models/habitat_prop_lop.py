# habitat_prop_lop: a little carrot patch for the Lop slime: a soil mound with three orange carrot shoulders
# poking out and big green leaf tufts on top.
import math, random
from lib import *
from models._habitat_prop import *

SOIL_LO, SOIL_HI = rgb(112, 74, 50), rgb(160, 112, 74)
ORANGE_LO, ORANGE_HI = rgb(236, 112, 30), rgb(255, 160, 60)
LEAF_LO, LEAF_HI = rgb(58, 150, 56), rgb(132, 216, 84)
R = random.Random(4)

mound = blob("Mound", 0.5, (0, 0, 0), seed=3, subdiv=2, squash=(1.75, 1.08, 0.62), jitter=0.06, lumps=0.12)
# clip below the deck: flatten every vertex under z=0 to z=0
for v in mound.data.vertices:
    v.co.z = max(v.co.z, 0.0)
regrad(mound, SOIL_LO, SOIL_HI)
parts = [mound]

CARROTS = [(-0.48, -0.05, 0.22, 0.9), (0.04, -0.12, 0.27, 1.0), (0.50, 0.04, 0.21, 0.85)]  # x, y, shoulder r, leaf scale
for n, (x, y, r, s) in enumerate(CARROTS):
    zs = 0.30 if abs(x) > 0.3 else 0.36  # carrot shoulder base: well out of the soil (r02)
    # carrot shoulder: rounded top, tapering down into the soil
    prof = [(0, zs - 0.30), (r * 0.6, zs - 0.18), (r * 0.95, zs), (r, zs + 0.10), (r * 0.8, zs + 0.18), (r * 0.35, zs + 0.22), (0, zs + 0.22)]
    parts.append(lathe(f"Carrot{n}", prof, segs=10, pos=(x, y, 0),
                       color_fn=vgrad(ORANGE_LO, ORANGE_HI, zs - 0.1, zs + 0.2, lambda i, k: 1.08 if k % 3 == 0 else 1.0)))
    top = zs + 0.2
    # leaf tuft: 5 tapered blades fanning out
    for j in range(5):
        a = math.radians(-60 + j * 30 + R.uniform(-8, 8))
        L = (0.45 + R.uniform(0, 0.15)) * s
        lean = 0.16 + 0.08 * abs(j - 2)
        tip = (x + math.sin(a) * L * lean * 1.6, y + math.cos(a) * 0.03 - 0.02, top + L)
        mid = (x + math.sin(a) * L * lean * 0.6, y, top + L * 0.55)
        blade = tube(f"Leaf{n}_{j}", [(x, y, top - 0.02), mid, tip], [0.055, 0.075, 0.015], segs=5)
        regrad(blade, LEAF_LO, LEAF_HI)
        parts.append(blade)

# a few soil clods for texture
for j in range(5):
    a = R.uniform(0, math.tau)
    parts.append(blob(f"Clod{j}", 0.07, (math.cos(a) * 0.72, math.sin(a) * 0.4, 0.06), shade(SOIL_LO, 0.9), seed=j, subdiv=1))

ship("habitat_prop_lop", parts)
