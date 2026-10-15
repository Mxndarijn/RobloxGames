# ranch_bench: plank park bench for the plaza: 3 seat planks, 2 back planks, dark-wood legs/arms, little goo blob on the seat.
# Front (seat edge) faces -Y. Small prop, target < 500 tris.
import math
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
L = 6.0
parts = []
for s in (-1, 1):
    x = s * (L / 2 - 0.4)
    parts.append(box(f"LegF{s}", (0.4, 0.4, 1.8), (x, -0.6, 0.9), WOOD_D))
    parts.append(box(f"LegB{s}", (0.4, 0.4, 4.0), (x, 0.9, 2.0), WOOD_D, rot=(-8, 0, 0)))
    parts.append(box(f"Arm{s}", (0.4, 2.2, 0.3), (x, 0.1, 2.65), WOOD_LO)); bevel(parts[-1], 0.06)
    parts.append(box(f"ArmPost{s}", (0.3, 0.3, 0.9), (x, -0.75, 2.2), WOOD_D))
for i, y in enumerate((-0.7, 0.0, 0.7)):
    parts.append(box(f"Seat{i}", (L, 0.6, 0.22), (0, y, 1.9), WOOD if i % 2 == 0 else shade(WOOD, 1.06))); bevel(parts[-1], 0.06)
for i, z in enumerate((2.8, 3.6)):
    parts.append(box(f"Back{i}", (L - 0.2, 0.2, 0.55), (0, 1.0 + 0.11 * (z - 2.0), z), WOOD, rot=(-8, 0, 0))); bevel(parts[-1], 0.05)
parts.append(blob("Goo", 0.32, (1.6, -0.3, 2.1), GOO, subdiv=2, squash=(1.2, 1, 0.6), jitter=0.02))
parts.append(blob("GooHi", 0.1, (1.5, -0.45, 2.25), GOO_HI, subdiv=1, jitter=0))
finish("ranch_bench", parts)
