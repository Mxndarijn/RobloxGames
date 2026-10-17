# giant_round_canopy: one tall egg-shaped crown on a buttressed trunk for the border v5 giant ring (~44 x 44 x 80).
import math, random
from lib import *
from models._giant_tree import *

R = random.Random(503)
parts = [limb("Trunk", [(0, 0, -0.5), (0.4, 0.2, 14), (1.0, 0.0, 30), (1.8, 0.0, 42)], [7.2, 4.4, 3.6, 3.2], R, segs=7)]
for k in range(3):  # root buttresses
    a = k * math.tau / 3 + 0.6 + R.uniform(-0.25, 0.25)
    parts.append(limb(f"Root{k}", [(math.cos(a) * 9.5, math.sin(a) * 9.5, -0.6), (math.cos(a) * 5.6, math.sin(a) * 5.6, 3.2), (math.cos(a) * 2.2, math.sin(a) * 2.2, 9.0)],
                      [1.5, 2.2, 2.6], R, segs=5))
parts += puff_cluster("Crown", 1.8, 0, 44, 20.0, R, n=8)
parts += puff_cluster("Upper", 1.2, -1, 64, 15.0, R, n=6, leaf=mix(FIELD, FIELD_L, 0.3), leaf_l=mix(FIELD_L, rgb(255, 255, 200), 0.2))
finish("giant_round_canopy", parts)
