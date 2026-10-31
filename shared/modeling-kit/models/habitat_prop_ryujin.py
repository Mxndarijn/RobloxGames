# habitat_prop_ryujin: a small red torii gate on stone feet with a glowing pink dragon pearl on a jade stand beneath.
import math
from models._habitat_prop5 import *
from models._habitat_prop4 import lathe, torus, paint, move

RED, RED_HI = rgb(236, 52, 52), rgb(255, 100, 86)
TOP = rgb(120, 58, 70)
STONE = rgb(200, 206, 220)
GOLD = rgb(255, 204, 70)
PEARL, PEARL_HI = rgb(255, 170, 220), rgb(255, 240, 250)
JADE, JADE_HI = rgb(70, 214, 160), rgb(150, 246, 200)

parts = []
PX, PH = 0.48, 1.12
for s in (-1, 1):
    parts.append(gcyl(f"Foot{s}", 0.1, 0.08, (s * PX, 0, 0), STONE, segs=8))
    parts.append(gcyl(f"Post{s}", 0.065, PH - 0.08, (s * PX, 0, 0.08), RED, RED_HI, segs=8, r_top=0.055))
# nuki (lower beam) through the posts, gakuzuka strut up to the top
parts.append(gbox("Nuki", (1.24, 0.1, 0.08), (0, 0, 0.86), RED, bev=0.02))
parts.append(gbox("Gaku", (0.08, 0.08, 0.16), (0, 0, 0.98), RED, bev=0))
# kasagi: upturned top beam (red under a dark cap)
kas = [(-0.78, PH + 0.12), (-0.66, PH + 0.04), (0, PH + 0.0), (0.66, PH + 0.04), (0.78, PH + 0.12),
       (0.8, PH + 0.18), (0.66, PH + 0.12), (0, PH + 0.09), (-0.66, PH + 0.12), (-0.8, PH + 0.18)]
parts.append(slab("Shimaki", [(x, z - 0.06) for x, z in kas], 0.14, RED, hi=RED_HI))
parts.append(slab("Kasagi", [(x * 1.03, z + 0.03) for x, z in kas], 0.18, TOP))
# pearl on a jade stand between the posts
stand = lathe("Stand", [(0.2, 0), (0.2, 0.05), (0.12, 0.1), (0.07, 0.24), (0.14, 0.3), (0.12, 0.33)], segs=10, color=JADE)
parts.append(gradient(stand, JADE, JADE_HI))
pearl = blob("Pearl", 0.17, (0, -0.02, 0.48), PEARL, subdiv=2, jitter=0)
paint(pearl, lambda c, n: PEARL_HI if n.z - n.y * 0.5 > 0.45 else PEARL)
parts.append(pearl)
for k in range(3):  # gold flame wisps round the pearl
    a = math.radians(-40 + 40 * k)
    parts.append(slab(f"Wisp{k}", [(0, 0), (0.05, 0.04), (0.0, 0.16), (-0.05, 0.04)], 0.03, GOLD,
                      (0.22 * math.sin(a), -0.04, 0.6 + 0.04 * math.cos(a))))
ship("habitat_prop_ryujin", parts)
