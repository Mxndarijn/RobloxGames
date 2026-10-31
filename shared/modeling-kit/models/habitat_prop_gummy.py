# habitat_prop_gummy: a pile of sugared gumdrops for the Gummy slime: four on the bottom, two on top of them,
# one crowning the pile, each a different bright candy colour.
import math, random
from lib import *
from models._habitat_prop import *

R = random.Random(2)
COLS = [P["ranch_roof"], rgb(255, 196, 40), rgb(110, 214, 92), rgb(170, 110, 236), rgb(255, 128, 40),
        rgb(70, 170, 245), rgb(255, 110, 170)]


def gumdrop(name, r, h, col, pos, tilt=(0, 0)):
    prof = [(0, 0), (r, 0), (r * 0.97, h * 0.3), (r * 0.72, h * 0.72), (r * 0.34, h * 0.95), (0, h)]
    lo, hi = shade(col, 0.88), mix(col, CREAM, 0.3)
    g = lathe(name, prof, segs=10, color_fn=lambda i, k, z: shade(mix(lo, hi, min(1.0, z / h)), 1.08 if k % 3 == 0 else 1.0))
    # sugar crystals: a few cream specks
    return xf(g, pos, (tilt[0], tilt[1], R.uniform(0, 36)))


PILE = [  # x, y, z, r, h, tilt
    (-0.58, -0.12, 0, 0.30, 0.42, (0, -6)), (-0.02, -0.22, 0, 0.33, 0.46, (0, 0)), (0.56, -0.08, 0, 0.30, 0.42, (0, 7)),
    (0.08, 0.24, 0, 0.30, 0.42, (0, 0)),
    (-0.30, 0.0, 0.30, 0.29, 0.42, (-6, -14)), (0.30, 0.04, 0.30, 0.29, 0.42, (-4, 14)),
    (0.0, -0.02, 0.60, 0.27, 0.40, (-8, 0)),
]
parts = [gumdrop(f"Gum{n}", r, h, COLS[n], (x, y, z), t) for n, (x, y, z, r, h, t) in enumerate(PILE)]
ship("habitat_prop_gummy", parts)
