# habitat_frame_1 (Common): plain warm wood. Two rows of curved boards round the slime, the outer row staggered half
# a board so the seams step like a boardwalk, a dark wood base ring showing through the seams, one nail per board.
import math, random
from lib import *
from models._habitat_frame import *

WOOD = rgb(164, 114, 66)
DARK = rgb(96, 62, 34)
NAIL = rgb(92, 88, 86)
R = random.Random(1)
GAP = 0.05  # seam width (studs)

parts = [arc_mesh("Base", 0, 0, [(R_IN, 0), (R_IN, 0.09), (R_OUT, 0.09), (R_OUT, 0)], DARK, segs=24, closed=True)]
rows = [(R_IN, MID - 0.01, 0.0), (MID + 0.01, R_OUT, 0.5)]
N = 8
for ri, (r0, r1, phase) in enumerate(rows):
    for i in range(N):
        a0 = -math.pi / 2 + (i + phase) * TAU / N
        a1 = a0 + TAU / N
        rm = (r0 + r1) / 2
        g = GAP / rm  # same seam width on both rows
        h = R.uniform(0.21, 0.26)
        col = shade(mix(WOOD, rgb(178, 132, 84), R.random()), R.uniform(0.92, 1.06))
        parts.append(arc_mesh(f"Board{ri}_{i}", a0 + g / 2, a1 - g / 2, chamfer_profile(r0, r1, 0.0, h, 0.04),
                              col, segs=3, side_k=0.78))
        th = a0 + (0.18 if ri == 0 else 0.82) * TAU / N
        parts.append(cylinder(f"Nail{ri}_{i}", 0.06, h + 0.025, polar(rm, th), NAIL, segs=4, rot=(0, 0, 45)))
frame_finish("habitat_frame_1", parts)
