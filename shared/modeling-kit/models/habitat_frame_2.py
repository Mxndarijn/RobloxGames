# habitat_frame_2 (Uncommon): painted wood. Radial boards painted fresh green (each a touch different), dark green
# seams between them and a raised cream trim line round the outer edge.
import math, random
from lib import *
from models._habitat_frame import *

GREEN = rgb(95, 174, 106)
SEAM = rgb(52, 112, 64)
CREAM = rgb(246, 234, 200)
R = random.Random(2)
N, GAP = 20, 0.05
TRIM_IN = R_OUT - 0.17

parts = [arc_mesh("Base", 0, 0, [(R_IN, 0), (R_IN, 0.1), (TRIM_IN, 0.1), (TRIM_IN, 0)], SEAM, segs=24, closed=True),
         arc_mesh("Trim", 0, 0, [(TRIM_IN, 0), (TRIM_IN, 0.27), (TRIM_IN + 0.05, 0.3), (R_OUT - 0.04, 0.3),
                                 (R_OUT, 0.26), (R_OUT, 0)], CREAM, segs=36, closed=True, side_k=0.86)]
for i in range(N):
    a0 = -math.pi / 2 + i * TAU / N
    g = GAP / MID
    col = shade(GREEN, R.uniform(0.95, 1.06))
    parts.append(arc_mesh(f"Board{i}", a0 + g / 2, a0 + TAU / N - g / 2,
                          chamfer_profile(R_IN, TRIM_IN - 0.01, 0.0, R.uniform(0.21, 0.24), 0.035), col, segs=1,
                          side_k=0.8))
frame_finish("habitat_frame_2", parts)
