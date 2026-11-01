# habitat_prop_cowboy: a golden hay bale tied with red twine, a coiled tan lasso on top and a silver horseshoe
# leaning against its front. Front faces -Y.
import math
import random
from lib import *
from models._habitat_prop4 import *

HAY, HAY_D, HAY_HI = rgb(244, 200, 82), rgb(230, 178, 64), rgb(255, 228, 130)
TWINE, ROPE, ROPE_D = rgb(210, 70, 50), rgb(226, 178, 112), rgb(186, 136, 80)
SHOE, SHOE_HI = rgb(176, 184, 200), rgb(222, 228, 240)
BW, BD, BH, BY = 1.2, 0.66, 0.58, 0.1
parts = []
for k in range(5):  # the bale as five pressed flakes along x, alternating shades, slightly uneven
    fx = -BW / 2 + BW * (k + 0.5) / 5
    fl = box(f"Flake{k}", (BW / 5 - 0.01, BD - (0.02 if k % 2 else 0), BH - (0.025 if k % 2 else 0)), (fx, BY, (BH - (0.025 if k % 2 else 0)) / 2))
    bevel(fl, 0.05, segments=1)
    col = HAY if k % 2 else HAY_D
    paint(fl, lambda c, n, col=col: HAY_HI if n.z > 0.7 else col)
    parts.append(fl)
for i, x in enumerate((-0.36, 0.36)):  # twine bands
    t = box(f"Twine{i}", (0.05, BD + 0.03, BH + 0.03), (x, BY, BH / 2), TWINE)
    bevel(t, 0.02)
    parts.append(t)
# straw tufts: little fans of three sticking up from the top edges
R = random.Random(3)
for k in range(5):
    x, y = R.uniform(-0.5, 0.5), BY + (-1 if k % 2 == 0 else 1) * (BD / 2 - 0.05)
    for j in (-1, 0, 1):
        parts.append(cone(f"Straw{k}{j}", 0.025, 0.12 - abs(j) * 0.025, (x + j * 0.03, y, BH - 0.03), HAY_HI, segs=3,
                          rot=((-30 if y < BY else 30), j * 28, 0)))
# coiled lasso on top: three stacked loops + a loose tail hanging over the right front edge
for k in range(3):
    parts.append(torus(f"Coil{k}", 0.24 - k * 0.012, 0.036, seg=16, seg2=5,
                       pos=(0.12 + k * 0.015, BY, BH + 0.036 + k * 0.062), color=ROPE if k % 2 == 0 else ROPE_D))
tail = [(0.33, BY - 0.05, BH + 0.16), (0.44, -0.08, BH + 0.08), (0.52, -0.2, BH - 0.02), (0.55, -0.25, BH - 0.2)]
parts.append(tube("Tail", tail, [0.034] * 4, ROPE, segs=5))
# horseshoe leaning on the front face, open end up (lucky)
shoe = torus("Shoe", 0.17, 0.045, seg=12, seg2=5, color=SHOE, arc=(math.radians(150), math.radians(390)))
move(shoe, rot=(90, 0, 0))  # stand it up in XZ, the gap at the top
paint(shoe, lambda c, n: SHOE_HI if n.z > 0.3 or n.y < -0.6 else SHOE)
move(shoe, (-0.3, BY - BD / 2 - 0.06, 0.22), (-12, 0, 0))
parts.append(shoe)
prop_finish("habitat_prop_cowboy", parts)
