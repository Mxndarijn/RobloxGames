# ranch_flower_planter: long wooden flower box with soil and low-poly pink/lilac/butter blooms + leaf tufts (Slime Ranch).
# Box along X, front -Y. Small prop, target < 500 tris.
import math
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
LEAF, LEAF_D = PALETTE["ranch_field_light"], PALETTE["ranch_field_dark"]
FLOWERS = [PALETTE["ranch_pink"], PALETTE["ranch_lilac"], PALETTE["ranch_butter"]]
SOIL = mix(WOOD_D, rgb(90, 64, 44), 0.6)
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
L, D, H = 5.0, 1.8, 1.4
parts = []
parts.append(box("Box", (L, D, H), (0, 0, H / 2 + 0.2), WOOD)); bevel(parts[-1], 0.08); gradient(parts[-1], WOOD_LO, WOOD)
for s in (-1, 1):
    parts.append(box(f"Foot{s}", (0.5, D + 0.1, 0.25), (s * (L / 2 - 0.4), 0, 0.12), WOOD_D))
parts.append(box("Trim", (L + 0.2, D + 0.2, 0.2), (0, 0, H + 0.2), WOOD_D))
parts.append(box("Soil", (L - 0.3, D - 0.3, 0.1), (0, 0, H + 0.25), SOIL))
for i in range(6):
    x = -L / 2 + 0.6 + i * (L - 1.2) / 5
    parts.append(blob(f"Leaf{i}", 0.45, (x, 0.1 * (-1) ** i, H + 0.5), LEAF if i % 2 else LEAF_D, subdiv=1, squash=(1.2, 1, 0.8), jitter=0.15, seed=i))
    h = 0.8 + 0.25 * ((i * 7) % 3)
    parts.append(cylinder(f"Stem{i}", 0.05, h, (x + 0.15, -0.15, H + 0.3), LEAF_D, segs=4))
    parts.append(blob(f"Bloom{i}", 0.3, (x + 0.15, -0.15, H + 0.3 + h), FLOWERS[i % 3], subdiv=1, squash=(1, 1, 0.6), jitter=0.1, seed=10 + i))
    parts.append(blob(f"Eye{i}", 0.1, (x + 0.15, -0.3, H + 0.38 + h), PALETTE["ranch_butter"] if i % 3 != 2 else WOOD, subdiv=1, jitter=0))
finish("ranch_flower_planter", parts)
