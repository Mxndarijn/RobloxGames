# habitat_frame_9 (Divine): white-gold. A pale ivory band with thin gold rims, gold sun-ray points fanning out
# across it and gold filigree arches (wire + bead) between the rays.
import math
from lib import *
from models._habitat_frame import *

WHITE = rgb(254, 248, 232)  # the brief's (255, 244, 214) cooled a bit: the warm sun turns it peach
IVORY = rgb(250, 240, 214)
GOLD = rgb(244, 182, 46)
GOLD_HI = rgb(255, 214, 96)
SEGS, RAYS = 32, 16
prof = [(R_IN, 0), (R_IN, 0.2), (R_IN + 0.04, 0.25), (R_IN + 0.1, 0.23), (3.6, 0.23), (3.66, 0.27), (3.72, 0.25),
        (R_OUT, 0.18), (R_OUT, 0)]


def col(si, j, kind, th):
    if kind == "bottom":
        return shade(GOLD, 0.6)
    if j in (1, 5):
        return GOLD_HI
    if j in (2, 6):
        return GOLD
    if j == 3:
        return WHITE if si % 2 else IVORY
    return shade(IVORY, 0.9)


parts = [arc_mesh("Band", 0, 0, prof, WHITE, segs=SEGS, closed=True, col_fn=col)]
for i, (x, y, th, deg) in enumerate(spots(RAYS)):
    long = i % 2 == 0
    parts.append(ray(f"Ray{i}", 2.72, 3.64 if long else 3.4, th, 0.2 if long else 0.14, 0.14, GOLD, z=0.22))
for i, (x, y, th, deg) in enumerate(spots(RAYS, phase=0.5)):
    # filigree: a gold wire arch between two rays, bowed outward, a bead on its crest
    half = 0.36 * TAU / RAYS
    pts = [polar(2.92 + 0.42 * math.sin(math.pi * k / 4), th - half + 2 * half * k / 4, 0.25) for k in range(5)]
    parts.append(tube(f"Wire{i}", pts, [0.05] * 5, GOLD_HI, segs=3))
    parts.append(octa(f"Bead{i}", 0.09, polar(3.34, th, 0.26), GOLD_HI, squash=(1, 1, 0.9)))
frame_finish("habitat_frame_9", parts)
