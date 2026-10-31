# habitat_frame_3 (Rare): grey-blue stone. Chunky chamfered blocks of uneven height and shade with deep grout
# seams; every other block is split into an inner and an outer stone so the seams step like a laid wall.
import math, random
from lib import *
from models._habitat_frame import *

STONE = rgb(142, 151, 163)
GROUT = rgb(86, 92, 108)
R = random.Random(3)
N, GAP = 12, 0.09

parts = [arc_mesh("Grout", 0, 0, [(R_IN, 0), (R_IN, 0.1), (R_OUT, 0.1), (R_OUT, 0)], GROUT, segs=24, closed=True)]
for i in range(N):
    a0 = -math.pi / 2 + (i + 0.5) * TAU / N
    g = GAP / MID
    pieces = [(R_IN, R_OUT)] if i % 2 == 0 else [(R_IN, MID - GAP / 2), (MID + GAP / 2, R_OUT)]
    for k, (r0, r1) in enumerate(pieces):
        col = shade(mix(STONE, rgb(150, 164, 184), R.random()), R.uniform(0.92, 1.08))
        h = R.uniform(0.24, 0.3)
        parts.append(arc_mesh(f"Block{i}_{k}", a0 + g / 2, a0 + TAU / N - g / 2,
                              chamfer_profile(r0, r1, 0.0, h, 0.07), col, segs=3, side_k=0.78))
frame_finish("habitat_frame_3", parts)
