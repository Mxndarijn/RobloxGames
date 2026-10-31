# habitat_frame_8 (Celestial): deep blue starry glass. A domed band whose facets shift between night blues and a
# little nebula violet, flat gold and white stars lying on it and tiny star dots scattered between.
import math, random
from lib import *
from models._habitat_frame import *

NIGHT = rgb(40, 44, 100)
GLASS = rgb(60, 70, 150)
NEBULA = rgb(110, 76, 170)
STAR = rgb(255, 226, 90)
WHITE = rgb(240, 247, 255)
R = random.Random(8)
SEGS = 40
prof = [(R_IN, 0), (R_IN, 0.18), (R_IN + 0.1, 0.26), (2.95, 0.29), (3.4, 0.29), (3.65, 0.24), (R_OUT, 0.14),
        (R_OUT, 0)]
tint = [R.random() for _ in range(SEGS * 8)]


def col(si, j, kind, th):
    if kind == "bottom":
        return shade(NIGHT, 0.6)
    t = tint[si * 8 + j]
    c = mix(NIGHT, GLASS, 0.4 + 0.6 * t)
    if t > 0.85:
        c = mix(c, NEBULA, 0.6)
    return c if kind == "top" else shade(c, 0.85)


parts = [arc_mesh("Band", 0, 0, prof, GLASS, segs=SEGS, closed=True, col_fn=col)]
for i, (x, y, th, deg) in enumerate(spots(8, r=3.18)):
    big = i % 2 == 0
    parts.append(star_prism(f"Star{i}", 0.34 if big else 0.24, 0.14 if big else 0.1, 0.06,
                            polar(3.18, th, 0.27), STAR if big else WHITE, rot=(0, 0, deg - 90)))
for i, (x, y, th, deg) in enumerate(spots(16, phase=0.5)):
    rr = R.uniform(2.85, 3.5)
    th += R.uniform(-0.08, 0.08)
    z = 0.29 if 2.95 < rr < 3.4 else 0.26
    parts.append(octa(f"Dot{i}", 0.05, polar(rr, th, z), WHITE if i % 3 else STAR, squash=(1, 1, 0.8)))
frame_finish("habitat_frame_8", parts)
