# habitat_frame_5 (Legendary): a shiny gold band with a fat raised outer lip and a small inner bead, red and blue
# gem studs set in gold bezels round the channel.
import math
from lib import *
from models._habitat_frame import *

GOLD = rgb(242, 194, 48)
HI = rgb(255, 226, 112)
LO = rgb(220, 158, 34)
RED = rgb(232, 52, 64)
BLUE = rgb(52, 120, 240)
SEGS = 40
prof = [(R_IN, 0), (R_IN, 0.2), (R_IN + 0.06, 0.26), (R_IN + 0.13, 0.22), (3.36, 0.2), (3.45, 0.29), (3.6, 0.3),
        (3.71, 0.26), (R_OUT, 0.16), (R_OUT, 0)]


def col(si, j, kind, th):
    if kind == "bottom":
        return shade(LO, 0.6)
    if j in (1, 5, 6):
        return HI  # lit bevels
    if j in (2, 7):
        return LO
    return GOLD if kind == "top" else shade(GOLD, 0.88)


parts = [arc_mesh("Band", 0, 0, prof, GOLD, segs=SEGS, closed=True, col_fn=col)]
for i, (x, y, th, deg) in enumerate(spots(10, r=3.03)):
    parts += gem(f"Gem{i}", 0.22, (x, y, 0.19), RED if i % 2 == 0 else BLUE, h=0.17, bezel=LO, rot=(0, 0, deg))
frame_finish("habitat_frame_5", parts)
