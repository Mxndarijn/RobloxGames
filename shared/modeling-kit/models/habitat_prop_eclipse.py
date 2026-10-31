# habitat_prop_eclipse: a little black hole on a stand: dark disc, glowing orange ring, tilted accretion disc.
from models._habitat_prop5 import *

DARK, DARK_HI = rgb(44, 26, 70), rgb(70, 44, 104)
ORANGE, YELLOW = rgb(255, 128, 36), rgb(255, 214, 90)
STAND, STAND_HI = rgb(86, 70, 120), rgb(140, 120, 180)
CZ = 0.76
parts = [
    gcyl("Base", 0.42, 0.1, (0, 0, 0), STAND, STAND_HI, segs=12, r_top=0.38),
    gcyl("Neck", 0.09, 0.2, (0, 0, 0.1), STAND, STAND_HI, segs=8),
    gcyl("Cup", 0.14, 0.06, (0, 0, 0.26), STAND_HI, segs=8, r_top=0.2),
    slab("Hole", circle_pts(0.46, 20), 0.12, DARK, (0, 0, CZ), hi=DARK_HI),
    ring_xz("Ring", 0.44, 0.6, 0.18, ORANGE, (0, 0, CZ), segs=24),
    ring_xz("Rim", 0.4, 0.47, 0.2, YELLOW, (0, 0, CZ), segs=24),
]
disc = ring_xz("Disc", 0.6, 0.8, 0.05, YELLOW, segs=24, hi=ORANGE)
parts.append(xf(disc, (0, 0, CZ), (41, 0, -10)))
ship("habitat_prop_eclipse", parts)
