# giant_broadleaf: huge spreading broadleaf for the border v5 giant ring (~70 x 62 x 76): a chunky forked
# trunk, four limbs and four lumpy canopy clusters of different size. Palette of ranch_border_oak_round.
import random
from lib import *
from models._giant_tree import *

R = random.Random(501)
parts = [limb("Trunk", [(0, 0, -0.5), (0.8, 0.4, 14), (1.8, 0.6, 30), (2.6, 0.2, 40)], [8.0, 5.2, 4.2, 3.6], R, segs=7)]
# three limbs and their canopy clusters: (end x, y, z), cluster radius
arms = [((-23, -5, 52), 15.5), ((19, 7, 60), 17.5), ((4, -21, 43), 12.5), ((-9, 17, 36), 8.5)]
for i, (end, cr) in enumerate(arms):
    parts.append(limb(f"Limb{i}", [(2.2, 0.3, 36), (end[0] * 0.55, end[1] * 0.55, 0.5 * (36 + end[2]) + 2), (end[0], end[1], end[2] - cr * 0.5)],
                      [3.1, 2.3, 1.7], R))
    parts += puff_cluster(f"Crown{i}", end[0], end[1], end[2], cr, R, n=5 + i % 2)
# a crown cluster on top of the trunk fork ties the three together
parts += puff_cluster("Top", 1, 1, 66, 11.0, R, n=5, leaf=mix(FIELD, FIELD_L, 0.35), leaf_l=mix(FIELD_L, rgb(255, 255, 200), 0.2))
finish("giant_broadleaf", parts)
