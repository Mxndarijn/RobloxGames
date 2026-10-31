# habitat_frame_4 (Epic): a copper band. Raised rolled lips on both edges, a channel between them crossed by 8
# bright copper straps with two domed rivets each. Pinker and brighter than the Common wood so the two never mix.
import math
from lib import *
from models._habitat_frame import *

COPPER = rgb(204, 108, 66)
LIP = rgb(250, 168, 124)
STRAP = rgb(226, 140, 86)
RIVET = rgb(252, 196, 150)
SEGS, PLATES = 36, 8
prof = [(R_IN, 0), (R_IN, 0.22), (R_IN + 0.05, 0.28), (R_IN + 0.13, 0.28), (R_IN + 0.17, 0.19), (R_OUT - 0.17, 0.19),
        (R_OUT - 0.13, 0.28), (R_OUT - 0.05, 0.28), (R_OUT, 0.22), (R_OUT, 0)]


def col(si, j, kind, th):
    if kind == "bottom":
        return shade(COPPER, 0.55)
    if j in (2, 6):  # lip tops
        return LIP
    if j == 4:  # channel
        return COPPER
    return shade(COPPER, 0.85) if kind == "side" else shade(LIP, 0.92)


parts = [arc_mesh("Band", 0, 0, prof, COPPER, segs=SEGS, closed=True, col_fn=col)]
w = 0.32 / MID  # strap width in radians
for i in range(PLATES):
    th = -math.pi / 2 + i * TAU / PLATES
    parts.append(arc_mesh(f"Strap{i}", th - w / 2, th + w / 2, chamfer_profile(R_IN + 0.13, R_OUT - 0.13, 0.1, 0.26, 0.03),
                          STRAP, segs=1, side_k=0.8))
    for k, rr in enumerate((MID - 0.24, MID + 0.24)):
        parts.append(cylinder(f"Rivet{i}_{k}", 0.09, 0.08, polar(rr, th, 0.25), RIVET, segs=6, r_top=0.045))
frame_finish("habitat_frame_4", parts)
