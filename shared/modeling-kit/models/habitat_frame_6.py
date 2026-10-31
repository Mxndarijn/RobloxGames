# habitat_frame_6 (Mythic): a pearl-silver band with a scalloped outer edge, big purple gems on the scallops and
# small teal gems between them.
import math
from lib import *
from models._habitat_frame import *

PEARL = rgb(214, 224, 236)
HI = rgb(240, 244, 252)
LO = rgb(170, 180, 204)
PURPLE = rgb(168, 72, 236)
TEAL = rgb(32, 204, 196)
SC, SEGS = 8, 56


def prof(th):
    u = abs(math.cos((th + math.pi / 2) * SC / 2))  # 1 on a scallop's crest, 0 at the dip between two
    ro = R_OUT - 0.2 * (1 - u) ** 1.5
    return [(R_IN, 0), (R_IN, 0.22), (R_IN + 0.08, 0.28), (ro - 0.12, 0.26), (ro, 0.16), (ro, 0)]


def col(si, j, kind, th):
    if kind == "bottom":
        return shade(LO, 0.6)
    if j == 1:
        return HI
    if j == 2:
        return mix(PEARL, rgb(246, 226, 240), 0.35 if si % 2 else 0.15)  # a faint pink pearl sheen
    if j == 3:
        return shade(PEARL, 0.92)
    return LO


parts = [arc_mesh("Band", 0, 0, prof, PEARL, segs=SEGS, closed=True, col_fn=col)]
for i, (x, y, th, deg) in enumerate(spots(SC, r=3.2)):
    parts += gem(f"Big{i}", 0.27, (x, y, 0.2), PURPLE, h=0.18, bezel=HI, rot=(0, 0, deg))
for i, (x, y, th, deg) in enumerate(spots(SC, phase=0.5, r=3.02)):
    parts += gem(f"Small{i}", 0.16, (x, y, 0.22), TEAL, h=0.14, rot=(0, 0, deg))
frame_finish("habitat_frame_6", parts)
