# habitat_prop_honey_toad: a round clay honey pot overflowing with honey that drips down its sides, and a
# wooden honey dipper standing in it.
import math
from lib import *
from models._habitat_prop2 import *

POT, POT_D = rgb(214, 132, 76), rgb(176, 100, 60)
HON, HON_HI = rgb(255, 176, 30), rgb(255, 206, 70)
DIP, DIP_D = rgb(214, 160, 100), rgb(170, 118, 70)

# pot: squat round belly, short neck, rolled rim
pot_prof = [(0.26, 0.0), (0.36, 0.06), (0.43, 0.2), (0.43, 0.34), (0.36, 0.48), (0.3, 0.54), (0.33, 0.58), (0.34, 0.63), (0.29, 0.64), (0.0, 0.6)]
parts = [lathe("Pot", pot_prof, segs=14, col=lambda c, i, k: POT_D if c.z < 0.12 else POT)]
# a cloth-tie band under the neck
parts.append(lathe("Tie", [(0.335, 0.47), (0.36, 0.49), (0.32, 0.54), (0.305, 0.53)], segs=14, col=rgb(250, 120, 140)))
# honey: a domed pool heaped over the rim
parts.append(smooth(lathe("HoneyTop", [(0.355, 0.6), (0.36, 0.64), (0.31, 0.69), (0.18, 0.72), (0.0, 0.73)], segs=14,
                   col=lambda c, i, k: HON_HI if c.z > 0.7 else HON)))
# drips down the side: each a tapered tube hugging the pot, ending in a round bead
SEGS = 14


def pot_r(z):
    for (r0, z0), (r1, z1) in zip(pot_prof, pot_prof[1:]):
        if z0 <= z <= z1 and z1 > z0:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return 0.3


for j, (a, length) in enumerate([(-98, 0.3), (-58, 0.13), (-138, 0.2), (-20, 0.24), (30, 0.1), (100, 0.27), (160, 0.14), (215, 0.22)]):
    ar = math.radians(a)
    zs = [0.64 - length * t for t in (0, 0.35, 0.7, 1.0)]
    pts = [(math.cos(ar) * (pot_r(z) + 0.01), math.sin(ar) * (pot_r(z) + 0.01), z) for z in zs]
    parts.append(smooth(tube(f"Drip{j}", pts, [0.085, 0.055, 0.045, 0.045], HON, segs=6)))
    zb = zs[-1]
    parts.append(smooth(blob(f"Bead{j}", 0.052, (math.cos(ar) * (pot_r(zb) + 0.015), math.sin(ar) * (pot_r(zb) + 0.015), zb - 0.005),
                      HON, subdiv=1, squash=(1, 1, 1.15), jitter=0)))
# honey dipper: handle out of the pot leaning back-right, grooved head sticking up in the honey
d0, d1 = (0.02, 0.06, 0.62), (0.3, 0.16, 1.22)
parts.append(tube("Handle", [d0, d1], [0.035, 0.03], DIP, segs=6))
parts.append(blob("Knob", 0.05, d1, DIP_D, subdiv=1, jitter=0))
head = lathe("DipHead", [(0.0, 0.0), (0.07, 0.01), (0.09, 0.04), (0.07, 0.07), (0.09, 0.1), (0.07, 0.13), (0.09, 0.16),
                         (0.07, 0.19), (0.0, 0.2)], segs=8, col=lambda c, i, k: DIP if i % 2 else DIP_D)
# put the head on the handle at the honey surface, along the handle direction
dx, dy, dz = (d1[0] - d0[0], d1[1] - d0[1], d1[2] - d0[2])
ln = math.sqrt(dx * dx + dy * dy + dz * dz)
tilt_y = math.degrees(math.atan2(dx, dz))
tilt_x = -math.degrees(math.atan2(dy, math.hypot(dx, dz)))
parts.append(move(head, (d0[0] + dx * 0.08, d0[1] + dy * 0.08, d0[2] + dz * 0.08), (tilt_x, tilt_y, 0)))
# honey on the dipper head
parts.append(smooth(blob("DipHoney", 0.08, (d0[0] + dx * 0.16, d0[1] + dy * 0.16, d0[2] + dz * 0.16 - 0.02), HON, subdiv=2, squash=(1.1, 1.1, 0.8), jitter=0)))
ship("habitat_prop_honey_toad", parts)
