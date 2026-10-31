# habitat_prop_boo: an old iron lantern with warm glowing panes, hanging from a crooked hook post on a rock.
import math
from models._habitat_prop5 import *

IRON, IRON_HI = rgb(70, 78, 92), rgb(112, 122, 140)
GLOW, GLOW_HI = rgb(255, 170, 60), rgb(255, 236, 140)
WOOD, WOOD_D = rgb(130, 96, 76), rgb(98, 70, 58)
LX, LT = 0.22, 0.95   # lantern centre x, top of the lantern body
parts = [
    blob("Rock", 0.3, (-0.55, 0.05, 0.08), rgb(150, 144, 150), subdiv=1, squash=(1.2, 1, 0.55), jitter=0.12, seed=3),
    gradient(tube("Post", [(-0.58, 0.05, 0.0), (-0.56, 0.05, 0.7), (-0.5, 0.05, 1.1), (-0.36, 0.05, 1.22), (-0.1, 0.05, 1.24),
                           (LX, 0.05, 1.22)], [0.07, 0.06, 0.055, 0.05, 0.045, 0.04], WOOD, segs=6), WOOD_D, WOOD),
    rod("Chain", (LX, 0.05, 1.22), (LX, 0.05, LT + 0.18), 0.02, IRON_HI, segs=4),
]
B = 0.42
parts += [
    gbox("Floor", (B + 0.08, B + 0.08, 0.06), (LX, 0.05, LT - 0.6), IRON, IRON_HI, bev=0.02),
    gbox("Glass", (B - 0.04, B - 0.04, 0.48), (LX, 0.05, LT - 0.33), GLOW, GLOW_HI, bev=0.0),
    lathe("Roof", [(0, LT - 0.04), (B * 0.8, LT - 0.04), (B * 0.8, LT), (0.06, LT + 0.16), (0, LT + 0.16)], segs=4,
          color_fn=vgrad(IRON, IRON_HI, LT, LT + 0.16), pos=(LX, 0.05, 0), phase=math.pi / 4),
    ring_xz("Ring", 0.04, 0.07, 0.03, IRON_HI, (LX, 0.05, LT + 0.2), segs=8),
    gbox("Mid", (B + 0.04, B + 0.04, 0.05), (LX, 0.05, LT - 0.33), IRON, bev=0.0),
]
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(gbox(f"Bar{sx}{sy}", (0.06, 0.06, 0.56), (LX + sx * B / 2, 0.05 + sy * B / 2, LT - 0.31), IRON, IRON_HI, bev=0.01))
ship("habitat_prop_boo", parts)
