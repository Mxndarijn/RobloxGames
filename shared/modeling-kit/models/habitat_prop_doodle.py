# habitat_prop_doodle: a little wooden easel holding a painted canvas (sun, hill, heart), a paint pot with a brush.
import math
from models._habitat_prop5 import *

WOOD, WOOD_D = P["ranch_wood"], P["ranch_wood_dark"]
CANVAS = rgb(255, 250, 236)
SKY, HILL, SUN, HEART = rgb(120, 200, 255), rgb(110, 210, 90), rgb(255, 210, 50), rgb(255, 80, 120)
POT, PAINT = rgb(90, 150, 240), rgb(255, 90, 160)
TILT = -12   # canvas leans back
ex = [  # easel, built upright at x around 0.2, then leaned
    rod("LegL", (-0.36, 0, 0), (-0.06, 0, 1.3), 0.04, WOOD),
    rod("LegR", (0.36, 0, 0), (0.06, 0, 1.3), 0.04, WOOD),
    gbox("Ledge", (0.86, 0.14, 0.05), (0, -0.06, 0.38), WOOD_D, WOOD, bev=0.01),
    slab("Canvas", [(-0.42, 0.4), (0.42, 0.4), (0.42, 1.14), (-0.42, 1.14)], 0.05, CANVAS, (0, -0.07, 0)),
    slab("Sky", [(-0.38, 0.62), (0.38, 0.62), (0.38, 1.1), (-0.38, 1.1)], 0.02, SKY, (0, -0.1, 0)),
    slab("Hill", [(-0.38, 0.44)] + circle_pts(0.5, 8, cx=0.0, cz=0.2, a0=math.radians(30), a1=math.radians(150))[::-1][:0]
         + [(0.38, 0.44), (0.38, 0.62), (0.2, 0.74), (0.0, 0.78), (-0.2, 0.72), (-0.38, 0.6)], 0.02, HILL, (0, -0.115, 0)),
    slab("Sun", star_pts(8, 0.12, 0.08, cx=0.22, cz=0.95), 0.02, SUN, (0, -0.12, 0)),
    slab("Heart", [(0, 0.5), (-0.1, 0.6), (-0.1, 0.66), (-0.05, 0.69), (0, 0.65), (0.05, 0.69), (0.1, 0.66), (0.1, 0.6)], 0.02, HEART, (-0.17, -0.125, 0.1)),
]
parts = [xf(o, (-0.22, 0.08, 0), (TILT, 0, 0)) for o in ex]
parts.append(xf(rod("Back", (0, 0, 1.2), (0, 0.5, 0.0), 0.035, WOOD_D), (-0.22, 0.08, 0), (TILT, 0, 0)))
# paint pot with a pink blob of paint and a brush
PX, PY = 0.56, -0.18
parts += [
    gcyl("Pot", 0.17, 0.24, (PX, PY, 0), shade(POT, 0.8), POT, segs=10, r_top=0.19),
    gcyl("Paint", 0.17, 0.03, (PX, PY, 0.22), PAINT, segs=10),
    slab("Drip", [(PX - 0.06, 0.24), (PX + 0.06, 0.24), (PX + 0.03, 0.12), (PX - 0.01, 0.1)], 0.03, PAINT, (0, PY - 0.18, 0)),
    rod("Brush", (PX - 0.04, PY + 0.04, 0.18), (PX + 0.1, PY + 0.12, 0.62), 0.025, WOOD),
    tube("Bristle", [(PX - 0.06, PY + 0.03, 0.12), (PX - 0.04, PY + 0.04, 0.2)], [0.04, 0.035], PAINT, segs=6),
]
ship("habitat_prop_doodle", parts)
