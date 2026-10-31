# habitat_prop_nightwing: a half-moon lamp: a round lamp disc, left half glowing white, right half night purple.
import math
from models._habitat_prop5 import *

WHITE, WHITE_LO = rgb(255, 252, 240), rgb(236, 232, 250)
PURPLE, PURPLE_HI = rgb(70, 44, 120), rgb(108, 72, 170)
BASE, BASE_HI = rgb(80, 56, 130), rgb(130, 100, 190)
GOLD = rgb(255, 210, 90)
CZ, R, T = 0.74, 0.46, 0.24
parts = [
    gcyl("Base", 0.36, 0.1, (0, 0, 0), BASE, BASE_HI, segs=12, r_top=0.32),
    gcyl("Neck", 0.06, CZ - R + 0.06, (0, 0, 0.1), BASE_HI, segs=8),
    slab("Light", circle_pts(R, 10, a0=math.pi / 2, a1=1.5 * math.pi), T, WHITE_LO, (0, 0, CZ), hi=WHITE),
    slab("Dark", circle_pts(R, 10, a0=-math.pi / 2, a1=math.pi / 2), T, PURPLE, (0, 0, CZ), hi=PURPLE_HI),
    ring_xz("Rim", R - 0.01, R + 0.05, T + 0.04, GOLD, (0, 0, CZ), segs=20),
]
# a few small stars on the dark half
for k, (x, z, s) in enumerate(((0.2, 0.14, 0.07), (0.28, -0.12, 0.05), (0.1, -0.24, 0.045))):
    parts.append(slab(f"Star{k}", star_pts(4, s, s * 0.4, cx=x, cz=CZ + z), 0.04, GOLD, (0, -T / 2 - 0.01, 0)))
ship("habitat_prop_nightwing", parts)
