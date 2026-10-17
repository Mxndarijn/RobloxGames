# ranch_floor_deck: the plaza timber deck: 72 radial planks r 45.5..63.6 between the landing ring and the plaza rim,
# a cream inlay ring (r 49..50.6) and a dark rim (r 64..65.6). Hub-centred, 8-fold symmetric, flat on z = 0.
# Planks leave 0.25 gaps: the cream plaza disc shows through. Walk surface = FloorLayout.FLOOR_Y + PLANK_TOP; no collision.
# Slot colour (MeshTint) = INLAY, the brightest colour; every vertex colour is a ratio of it.
import math, random

from lib import *
from models._ranch_floor import *

BASE = INLAY
R_IN, R_OUT = 45.5, 63.6
PLANKS = 72
GAP = 0.25
r = random.Random(5)

parts = []
step = 360 / PLANKS
for i in range(PLANKS):
    a = step * (i + 0.5)
    c = PLANK_A if i % 2 == 0 else PLANK_B
    # half the angular width at the INNER radius leaves the gap constant: use the mean radius for the angle
    half = step / 2 - math.degrees(GAP / 2 / ((R_IN + R_OUT) / 2))
    parts.append(trapezoid(f"DeckPlank{i}", a - half, a + half, R_IN, R_OUT, 0.0, PLANK_TOP, ratio(c, BASE, 0.97 + r.random() * 0.06)))
parts.append(arc_strip("Inlay", 49.0, 50.6, 0, 360, 3.75, 0.0, TRIM_TOP, ratio(INLAY, BASE)))
parts.append(arc_strip("Rim", 64.0, 65.6, 0, 360, 3.75, 0.0, TRIM_TOP, ratio(TRIM_DARK, BASE)))

finish("ranch_floor_deck", parts)
