# habitat_prop_moo: dairy milk can (churn) for the Moo slime: silver body, blue band, domed lid with knob,
# two loop handles on the shoulders.
import math
from lib import *
from models._habitat_prop import *

SIL_LO, SIL_HI = rgb(138, 152, 176), rgb(228, 236, 248)
BLUE = rgb(58, 132, 236)
H = 1.28

prof = [(0, 0), (0.40, 0), (0.43, 0.06), (0.43, 0.30), (0.44, 0.34), (0.44, 0.46), (0.43, 0.50), (0.43, 0.72),
        (0.36, 0.86), (0.24, 0.96), (0.22, 1.04), (0.25, 1.06), (0.25, 1.12), (0.0, 1.12)]
BAND_ROWS = {3, 4, 5}  # 0.30..0.50: the blue band


def can_col(i, k, z):
    if i in BAND_ROWS:
        return shade(BLUE, 1.0 if z > 0.4 else 0.9)
    return shade(mix(SIL_LO, SIL_HI, min(1.0, z / 1.0)), 1.06 if k % 4 == 0 else 1.0)


parts = [lathe("Can", prof, segs=16, color_fn=can_col)]
# lid: dome with a blue knob
parts.append(lathe("Lid", [(0, 1.10), (0.29, 1.10), (0.29, 1.15), (0.22, 1.20), (0.0, 1.22)], segs=14,
                   color_fn=lambda i, k, z: SIL_HI if i < 1 else shade(SIL_HI, 0.97)))
parts.append(lathe("Knob", [(0, 1.20), (0.07, 1.20), (0.09, 1.25), (0.07, H), (0, H)], segs=8,
                   color_fn=lambda i, k, z: BLUE))
# loop handles on both shoulders
for s in (-1, 1):
    pts = []
    for j in range(7):
        a = math.pi * j / 6
        pts.append((s * (0.36 + 0.17 * math.sin(a)), 0.0, 0.78 + 0.16 * math.cos(a)))
    parts.append(tube(f"Handle{s}", pts, [0.04] * 7, SIL_HI, segs=6))

ship("habitat_prop_moo", parts)
