# habitat_mushroom_ring: mossy mound (7.8 x 4.2 x 7.8), flat moss seat at z=2.4, a fairy ring of red-capped toadstools on the rim.
import math, random
from lib import *
from models._habitat import *

W, H = 7.8, 4.2
LEAF, LEAF_D = P["ranch_field_light"], P["ranch_field_dark"]
R = random.Random(9)
parts = []
MOUND = [(0, 0), (3.7, 0), (3.9, 0.3), (3.7, 1.1), (3.3, 1.8), (2.7, 2.25), (2.3, 2.15), (0, 2.15)]
parts.append(lathe("Mound", MOUND, segs=16, color_fn=lambda i, k, z: shade(mix(WOOD_D, LEAF_D, min(1, z / 1.6)), R.uniform(0.93, 1.04))))
parts.append(seat_disc("Seat", 2.1, mix(LEAF, LEAF_D, 0.25), edge=LEAF_D))
CAPS = [(10, 1.0), (62, 0.7), (115, 1.2), (170, 0.8), (222, 1.0), (275, 0.7), (322, 1.1)]
for i, (a, s) in enumerate(CAPS):
    aa = math.radians(a)
    x, y = math.cos(aa) * 3.05, math.sin(aa) * 3.05
    z = 1.75
    sh = 1.1 * s + 0.5
    parts.append(cylinder(f"St{i}", 0.26 * s + 0.05, sh + 0.2, (x, y, z - 0.2), CREAM, segs=6, r_top=0.2 * s + 0.04))
    cap = lathe(f"Cap{i}", [(0, 0), (0.85 * s, 0.05), (0.75 * s, 0.4 * s), (0.4 * s, 0.62 * s), (0, 0.68 * s)], segs=8, pos=(x, y, z + sh - 0.15),
                color_fn=lambda ii, k, zz, ss=s: CREAM if ii == 0 else (CREAM if k % 3 == 0 and ii >= 2 else ROOF))
    parts.append(cap)
fit(finish("habitat_mushroom_ring", parts), W, H, W)
