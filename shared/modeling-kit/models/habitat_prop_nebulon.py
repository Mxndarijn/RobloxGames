# habitat_prop_nebulon: a small banded planet with a tilted ring, on a little stand.
import math
from models._habitat_prop5 import *

PINK, PURPLE, LILAC = rgb(250, 120, 200), rgb(150, 90, 230), rgb(210, 170, 255)
RING, RING_HI = rgb(110, 220, 255), rgb(200, 245, 255)
STAND, STAND_HI = rgb(70, 64, 130), rgb(120, 112, 196)
CZ, R = 0.82, 0.4
BANDS = [PURPLE, LILAC, PINK, PURPLE, PINK, LILAC, PINK, PURPLE]
prof = [(0, CZ - R)] + [(R * math.sin(math.pi * k / 8), CZ - R * math.cos(math.pi * k / 8)) for k in range(1, 8)] + [(0, CZ + R)]
parts = [
    gcyl("Base", 0.36, 0.1, (0, 0, 0), STAND, STAND_HI, segs=10, r_top=0.32),
    gcyl("Rod", 0.05, CZ - R, (0, 0, 0.1), STAND_HI, segs=6),
    lathe("Planet", prof, segs=16, color_fn=lambda i, k, z: shade(BANDS[i], 1.0 + 0.05 * (k % 2))),
]
ring = ring_xz("Ring", 0.52, 0.74, 0.04, RING, segs=24, hi=RING_HI)
parts.append(xf(ring, (0, 0, CZ), (44, 0, 16)))
parts.append(blob("Moon", 0.08, (0.62, -0.1, CZ + 0.42), rgb(255, 240, 170), subdiv=1, jitter=0))
ship("habitat_prop_nebulon", parts)
