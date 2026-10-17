# giant_elder_oak: border v6 giant, a vast gnarled oak (~150 x 140 x 112): a buttressed trunk, five heavy
# limbs reaching out low and wide, each carrying a broad flat-topped canopy cluster, one tall crown on top.
# Palette of ranch_border_oak_round, warmer on top. New mesh, not a scaled v5 giant.
import math, random
from lib import *
from models._giant_tree import *

R = random.Random(601)
parts = [limb("Trunk", [(0, 0, -0.5), (1.0, 0.5, 14), (0.6, 1.4, 32), (-0.4, 0.8, 46)], [11.5, 7.6, 6.2, 5.4], R, segs=8)]
for k in range(4):  # root buttresses
    a = k * math.tau / 4 + 0.4 + R.uniform(-0.3, 0.3)
    parts.append(limb(f"Root{k}", [(math.cos(a) * 15, math.sin(a) * 15, -0.8), (math.cos(a) * 8.5, math.sin(a) * 8.5, 4.5), (math.cos(a) * 3, math.sin(a) * 3, 14)],
                      [2.0, 3.0, 3.6], R, segs=5))
# five limbs: (bearing deg, reach, rise, canopy radius)
for i, (b, reach, rise, cr) in enumerate([(20, 52, 62, 21), (95, 44, 56, 18), (165, 55, 66, 22), (235, 42, 54, 17), (310, 50, 60, 20)]):
    a = math.radians(b + R.uniform(-8, 8))
    ex, ey, ez = math.cos(a) * reach, math.sin(a) * reach, rise
    parts.append(limb(f"Limb{i}", [(0, 0, 38), (ex * 0.35, ey * 0.35, 38 + (ez - 38) * 0.25 + 2), (ex * 0.7, ey * 0.7, 38 + (ez - 38) * 0.7 + 3), (ex, ey, ez - cr * 0.45)],
                      [4.6, 3.6, 2.6, 1.9], R, segs=6))
    parts += puff_cluster(f"Crown{i}", ex, ey, ez, cr, R, n=6, ratio=0.6)
parts += puff_cluster("Top", 0, 1, 84, 17.0, R, n=6, leaf=mix(FIELD, FIELD_L, 0.4), leaf_l=mix(FIELD_L, rgb(255, 255, 200), 0.25))
finish("giant_elder_oak", parts)
