# ranch_floor_paths: the Slime Ranch boardwalk: the r 78 ring (r 74..82) and the eight spokes, ONE hub-centred mesh.
# Cross planks 8 studs wide with a 0.2 gap (field sand shows through), two warm tones with a little per-plank jitter,
# dark rails on both edges that open at every spoke mouth. Spokes: inner r 65.6..74, outer r 82..96 (the plot gate ramp
# takes r 96..100). Walk surface = FloorLayout.FLOOR_Y + PLANK_TOP; no collision (decor, MeshAssets.COLLISION).
# Slot colour (MeshTint) = PLANK_BASE, the brightest colour; vertex colours are ratios of it.
import math, random

from lib import *
from models._ranch_floor import *

BASE = (196, 146, 92)
RING_R, HALF = 78.0, 4.0
RING_PLANKS = 160
GAP = 0.2
RAIL_W = 0.8
SPOKES = [45 * k for k in range(8)]
r = random.Random(11)

col_a, col_b, col_rail = PLANK_A, PLANK_B, TRIM_DARK


def plank_col():
    c = col_a if r.random() < 0.5 else col_b
    return ratio(c, BASE, 0.96 + r.random() * 0.08)


parts = []
# ring: radial planks
step = 360 / RING_PLANKS
for i in range(RING_PLANKS):
    a = step * (i + 0.5)
    ang = math.degrees(math.asin((step / 2 * math.pi / 180 * RING_R - GAP / 2) / RING_R)) if False else (step / 2 - math.degrees(GAP / 2 / RING_R))
    parts.append(trapezoid(f"RingPlank{i}", a - ang, a + ang, RING_R - HALF, RING_R + HALF, 0.0, PLANK_TOP, plank_col()))
# ring rails: outside the planks, open at every spoke mouth (flush with the spoke rail's outer face, lateral 4.8)
for k, b in enumerate(SPOKES):
    nxt = b + 45
    for side, (r0, r1) in (("i", (RING_R - HALF - RAIL_W, RING_R - HALF)), ("o", (RING_R + HALF, RING_R + HALF + RAIL_W))):
        rm = (r0 + r1) / 2
        gap = math.degrees(math.asin((HALF + RAIL_W) / rm))
        parts.append(arc_strip(f"RingRail{side}{k}", r0, r1, b + gap, nxt - gap, 3.75, 0.0, TRIM_TOP, ratio(col_rail, BASE)))
# spokes: cross planks + rails
for k, b in enumerate(SPOKES):
    for tag, s_a, s_b, n in (("In", 65.6, RING_R - HALF, 3), ("Out", RING_R + HALF, 96.0, 5)):
        pitch = (s_b - s_a) / n
        for j in range(n):
            s0 = s_a + pitch * j + GAP / 2
            s1 = s_a + pitch * (j + 1) - GAP / 2
            parts.append(slab(f"Spoke{tag}{k}_{j}", b, s0, s1, -HALF, HALF, 0.0, PLANK_TOP, plank_col()))
        for side in (-1, 1):
            l0, l1 = (HALF, HALF + RAIL_W) if side > 0 else (-HALF - RAIL_W, -HALF)
            parts.append(slab(f"Rail{tag}{k}_{side}", b, s_a, s_b, l0, l1, 0.0, TRIM_TOP, ratio(col_rail, BASE)))

finish("ranch_floor_paths", parts)
