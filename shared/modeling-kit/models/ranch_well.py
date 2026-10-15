# ranch_well: stone-and-wood ranch well with a goo surface, two posts, red gable roof, crank + bucket (Slime Ranch).
# NOTE: lib shapes rot= is in DEGREES.
# Ring wall = 10 wood-dark staves on a stone-ish wood plinth; goo disc inside; roof ridge along X. cylinder() pos = base.
import math
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
METAL = PALETTE["ranch_metal"]
STONE = mix(PALETTE["ranch_plaza"], WOOD_D, 0.35)
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
parts = []
R = 2.4
parts.append(cylinder("Base", R + 0.3, 0.5, (0, 0, 0), STONE, segs=12)); gradient(parts[-1], shade(STONE, .8), STONE)
for i in range(12):
    a = 2 * math.pi * (i + 0.5) / 12
    x, y = R * math.cos(a), R * math.sin(a)
    parts.append(box(f"Stone{i}", (1.3, 0.6, 1.6), (x, y, 1.3), shade(STONE, 0.9 + 0.12 * (i % 3) / 2), rot=(0, 0, math.degrees(a) + 90)))
    bevel(parts[-1], 0.08)
parts.append(cylinder("Rim", R + 0.35, 0.3, (0, 0, 2.1), WOOD_D, segs=12)); gradient(parts[-1], WOOD_D, WOOD)
parts.append(cylinder("Goo", R - 0.25, 0.2, (0, 0, 1.8), GOO, segs=12)); gradient(parts[-1], GOO, mix(GOO, GOO_HI, 0.4))
parts.append(blob("Bub", 0.25, (0.6, -0.5, 2.05), GOO_HI, subdiv=1, squash=(1, 1, .6), jitter=0.03))
parts.append(blob("Bub2", 0.18, (-0.7, 0.3, 2.02), GOO_HI, subdiv=1, squash=(1, 1, .6), jitter=0.03))
for s in (-1, 1):
    parts.append(box(f"Post{s}", (0.45, 0.45, 4.6), (s * (R + 0.1), 0, 3.9), WOOD)); gradient(parts[-1], WOOD_LO, WOOD)
# roof: two slanted slabs, ridge along X
for s in (-1, 1):
    parts.append(box(f"Roof{s}", (6.4, 2.4, 0.25), (0, s * 1.0, 6.9), ROOF, rot=(-s * 32, 0, 0)))
    gradient(parts[-1], ROOF_D, ROOF)
parts.append(box("Ridge", (6.6, 0.35, 0.35), (0, 0, 7.55), ROOF_D))
# crank axle + handle, rope + bucket
parts.append(cylinder("Axle", 0.18, 5.6, (-2.8, 0, 5.2), WOOD_D, segs=6, rot=(0, 90, 0)))
parts.append(cylinder("Drum", 0.38, 1.6, (-0.8, 0, 5.2), WOOD, segs=8, rot=(0, 90, 0)))
parts.append(tube("Crank", [(2.9, 0, 5.2), (3.2, 0, 5.2), (3.2, 0, 4.5), (3.6, 0, 4.5)], [0.09] * 4, METAL, segs=5))
parts.append(cylinder("Rope", 0.05, 1.7, (0, 0, 3.3), WOOD_D, segs=4))
parts.append(cylinder("Bucket", 0.35, 0.6, (0, 0, 2.75), WOOD, segs=8, r_top=0.42))
parts.append(cylinder("Band", 0.4, 0.1, (0, 0, 3.05), METAL, segs=8))
finish("ranch_well", parts)
