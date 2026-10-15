# ranch_fence_stile: step-over stile, two posts + top rail with a two-step plank ladder each side (Slime Ranch). rot= DEGREES.
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
parts = []


def pbox(n, s, p, bot, top, bev=0.1, rot=(0, 0, 0)):
    o = box(n, s, p, bot, rot=rot); bevel(o, bev); gradient(o, bot, top); return o


for sx in (-1, 1):
    parts.append(pbox(f"Post{sx}", (0.85, 0.85, 4.6), (sx * 2.0, 0, 2.3), WOOD_LO, WOOD, 0.14))
for z in (1.6, 3.2):
    parts.append(pbox(f"Rail{z}", (4.8, 0.45, 0.55), (0, 0, z), WOOD_LO, WOOD, 0.1))
for sy in (-1, 1):
    for k, (y, z) in enumerate(((1.6, 0.9), (0.9, 1.9))):
        parts.append(pbox(f"Step{sy}{k}", (2.6, 0.9, 0.42), (0, sy * y, z), WOOD_LO, WOOD, 0.1))
        for sx in (-1, 1):
            parts.append(pbox(f"Leg{sy}{k}{sx}", (0.45, 0.45, z), (sx * 1.05, sy * y, z / 2), WOOD_D, WOOD_LO, 0.06))
parts.append(blob("Goo", 0.3, (0.5, -0.9, 2.15), GOO, subdiv=1, squash=(1.5, 1, 0.45), jitter=0.03)); gradient(parts[-1], GOO, GOO_HI)
finish("ranch_fence_stile", parts)
