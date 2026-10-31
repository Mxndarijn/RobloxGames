# habitat_prop_zap: signature prop for Zap: a copper lightning rod on a small steel base, struck by a big yellow
# zigzag bolt from the upper left, with sparks at the tip. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

STEEL, STEEL_D, STEEL_HI = rgb(130, 150, 186), rgb(96, 112, 146), rgb(176, 196, 226)
COPPER, COPPER_HI = rgb(234, 136, 72), rgb(255, 184, 118)
BOLT, BOLT_HI, SPARK = rgb(255, 214, 30), rgb(255, 242, 120), rgb(255, 255, 210)
HAZ = rgb(40, 44, 60)

parts = []
base = box("Base", (0.7, 0.6, 0.16), (0.12, 0, 0.08), STEEL)
bevel(base, 0.04)
paint(base, lambda c, n: STEEL_HI if n.z > 0.5 else STEEL)
parts.append(base)
plinth = cylinder("Plinth", 0.17, 0.14, (0.12, 0, 0.16), STEEL_D, segs=8, r_top=0.13)
parts.append(plinth)
# hazard stripes on the base front
for k in range(4):
    parts.append(slab(f"Haz{k}", [(0, 0), (0.07, 0), (0.12, 0.1), (0.05, 0.1)], 0.02, pos=(-0.15 + k * 0.15, -0.305, 0.03), color=HAZ))
    parts.append(slab(f"HazY{k}", [(0.07, 0), (0.15, 0), (0.2, 0.1), (0.12, 0.1)], 0.02, pos=(-0.15 + k * 0.15, -0.305, 0.03), color=BOLT))
# the rod: copper with two insulator rings and a sharp tip
TIP = 0.8
rod = cylinder("Rod", 0.05, 0.34, (0.12, 0, 0.3), COPPER, segs=6)
parts.append(rod)
for z in (0.36, 0.52):
    parts.append(cylinder(f"Ins{z}", 0.1, 0.07, (0.12, 0, z), STEEL_HI, segs=8))
parts.append(blob("Ball", 0.085, (0.12, 0, 0.64), COPPER_HI, subdiv=1, jitter=0))
parts.append(cone("Tip", 0.055, TIP - 0.66, (0.12, 0, 0.66), COPPER_HI, segs=6))
# the bolt: a classic zigzag bolt striking down onto the tip from the upper left
outline = [(-0.05, 1.0), (0.27, 1.0), (0.11, 0.58), (0.3, 0.58), (-0.14, 0.0), (0.0, 0.42), (-0.18, 0.42)]
bolt = slab("Bolt", [(x * 1.0, z * 0.56) for x, z in outline], 0.11, color=BOLT)
paint(bolt, lambda c, n: BOLT_HI if abs(n.y) > 0.5 else BOLT)
move(bolt, (0.12 + 0.14, -0.02, TIP - 0.01))
parts.append(bolt)
for i, (x, z, r) in enumerate([(0.3, TIP + 0.04, 0.045), (0.27, TIP - 0.12, 0.035), (-0.06, TIP - 0.1, 0.035), (0.0, TIP + 0.12, 0.03)]):
    parts.append(blob(f"Spark{i}", r, (x, -0.03, z), SPARK, subdiv=1, jitter=0.2, seed=i))
prop_finish("habitat_prop_zap", parts)
