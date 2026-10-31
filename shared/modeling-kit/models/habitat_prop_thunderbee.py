# habitat_prop_thunderbee: signature prop for Thunderbee: a storm-cloud hive: a lumpy grey cloud with an amber
# honeycomb doorway on the front, a honey drip, a tiny yellow bolt out of its side and a little bee. Front -Y.
import math
from lib import *
from models._habitat_prop4 import *

CLOUD_D, CLOUD, CLOUD_HI = rgb(112, 120, 158), rgb(146, 156, 192), rgb(196, 204, 228)
HONEY, HONEY_D, HONEY_HI = rgb(255, 176, 40), rgb(214, 120, 30), rgb(255, 214, 100)
BOLT, BEE_Y, BEE_K, WING = rgb(255, 226, 40), rgb(255, 210, 50), rgb(44, 40, 52), rgb(240, 250, 255)

parts = []
puffs = [(0, 0.05, 0.42, 0.44), (-0.4, 0.08, 0.3, 0.32), (0.42, 0.06, 0.3, 0.33), (-0.18, 0.1, 0.72, 0.3),
         (0.22, 0.12, 0.7, 0.28), (0.0, 0.2, 0.25, 0.36), (-0.62, 0.05, 0.18, 0.2), (0.64, 0.04, 0.17, 0.2)]
for i, (x, y, z, r) in enumerate(puffs):
    b = blob(f"Puff{i}", r, (x, y, z), CLOUD, subdiv=2, jitter=0.04, seed=i, squash=(1.08, 0.9, 0.86))
    paint(b, lambda c, n: CLOUD_HI if n.z > 0.5 else (CLOUD_D if n.z < -0.2 else CLOUD))
    parts.append(floor(b))
# honeycomb doorway: amber hex ring with a dark hex hole, on the front of the big puff
hz = 0.42
ring = cylinder("HexRing", 0.21, 0.12, rot=(90, 0, 0), segs=6, color=HONEY, pos=(0, -0.3, hz))
paint(ring, lambda c, n: HONEY_HI if n.y < -0.5 else HONEY)
parts.append(ring)
parts.append(cylinder("HexHole", 0.13, 0.04, rot=(90, 0, 0), segs=6, color=rgb(120, 70, 30), pos=(0, -0.41, hz)))
for i, (x, z) in enumerate([(-0.28, 0.6), (0.27, 0.58), (0.31, 0.32)]):  # small honeycomb cells round it
    parts.append(cylinder(f"Cell{i}", 0.08, 0.06, rot=(90, 0, 0), segs=6, color=HONEY_D if i % 2 else HONEY,
                          pos=(x, -0.3 - 0.04 * (1 - abs(x)), z)))
# honey drip under the doorway
parts.append(tube("Drip", [(0.08, -0.4, hz - 0.15), (0.09, -0.42, hz - 0.28), (0.09, -0.42, hz - 0.33)], [0.045, 0.04, 0.02], HONEY, segs=6))
parts.append(blob("DripEnd", 0.055, (0.09, -0.42, hz - 0.34), HONEY_HI, subdiv=1, jitter=0, squash=(1, 1, 1.2)))
# tiny bolt jabbing out of the right side
parts.append(slab("Bolt", [(0, 0.3), (0.12, 0.3), (0.06, 0.16), (0.14, 0.16), (-0.02, -0.06), (0.03, 0.1), (-0.04, 0.1)], 0.07,
                  pos=(0.78, -0.05, 0.1), rot=(0, -20, 0), color=BOLT))
# little bee near the doorway
bx, by, bz = -0.42, -0.42, 0.66
bee = blob("Bee", 0.09, (bx, by, bz), BEE_Y, subdiv=2, jitter=0, squash=(1.3, 1, 1))
paint(bee, lambda c, n: BEE_K if int((c.x - bx + 0.2) / 0.06) % 2 == 0 else BEE_Y)
parts.append(bee)
for s in (-1, 1):
    parts.append(blob(f"Wing{s}", 0.065, (bx - 0.02, by + s * 0.05, bz + 0.1), WING, subdiv=1, jitter=0, squash=(1.2, 0.35, 0.8),
                      rot=(s * 20, 0, 0)))
prop_finish("habitat_prop_thunderbee", parts)
