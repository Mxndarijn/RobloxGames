# habitat_prop_soda: a small red crate of soda bottles for the Soda slime: 3 x 2 glass bottles in bright pop
# colours with white labels and silver caps, standing in an open slatted crate.
import math
from lib import *
from models._habitat_prop import *

CRATE, CRATE_LO = rgb(232, 64, 60), rgb(186, 44, 48)
CAP = rgb(226, 232, 240)
LABEL = rgb(255, 250, 240)
POP = [rgb(80, 200, 90), rgb(255, 140, 40), rgb(160, 96, 236), rgb(60, 170, 245), rgb(255, 90, 140), rgb(255, 200, 40)]
CW, CD, CH = 1.44, 0.98, 0.42
T = 0.07

parts = [box("Base", (CW - 0.04, CD - 0.04, 0.08), (0, 0, 0.04), CRATE_LO)]  # r03: inset (coplanar with the walls)
for s in (-1, 1):
    parts.append(box(f"WallF{s}", (CW, T, CH), (0, s * (CD / 2 - T / 2), CH / 2), CRATE))
    parts.append(box(f"WallS{s}", (T, CD - 2 * T, CH), (s * (CW / 2 - T / 2), 0, CH / 2), CRATE))
    # hand-hole on the short sides: dark slot
    parts.append(box(f"Grip{s}", (0.01, 0.34, 0.09), (s * (CW / 2 + 0.002), 0, CH - 0.12), CRATE_LO))
# rim band on the front/back walls (lighter top edge)
for s in (-1, 1):
    parts.append(box(f"Rim{s}", (CW + 0.02, T + 0.02, 0.06), (0, s * (CD / 2 - T / 2), CH - 0.03), shade(CRATE, 1.12)))
# divider
parts.append(box("Div", (CW - 2 * T, 0.04, CH * 0.75), (0, 0, CH * 0.375), CRATE_LO))

n = 0
for j, y in enumerate((-0.22, 0.22)):
    for i, x in enumerate((-0.44, 0.0, 0.44)):
        col = POP[n]
        lo, hi = shade(col, 0.78), mix(col, CREAM, 0.25)
        prof = [(0, 0.08), (0.16, 0.08), (0.17, 0.12), (0.17, 0.58), (0.14, 0.70), (0.07, 0.86), (0.065, 1.02), (0, 1.02)]
        hb = 1.02 + (0.06 if (i + j) % 2 else 0)
        prof = [(r, z if z < 0.7 else z + (hb - 1.02)) for r, z in prof]
        parts.append(lathe(f"Bottle{n}", prof, segs=8, pos=(x, y, 0), color_fn=vgrad(lo, hi, 0.1, hb)))
        parts.append(lathe(f"Label{n}", [(0, 0.42), (0.178, 0.42), (0.178, 0.6), (0, 0.6)], segs=8, pos=(x, y, 0),
                           color_fn=lambda a, b, z: LABEL))
        parts.append(lathe(f"Cap{n}", [(0, hb - 0.02), (0.085, hb - 0.02), (0.085, hb + 0.05), (0, hb + 0.05)], segs=8,
                           pos=(x, y, 0), color_fn=lambda a, b, z: CAP))
        n += 1

ship("habitat_prop_soda", parts)
