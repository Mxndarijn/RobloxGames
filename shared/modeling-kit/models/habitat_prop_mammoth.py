# habitat_prop_mammoth: signature prop for Mammoth: a snow-capped grey rock with one big ancient ivory tusk
# coming out of its left side and curling round the front and up on the right, ice crystals at the foot.
# Front faces -Y.
import math
from mathutils import Vector
from lib import *
from models._habitat_prop4 import *

ROCK, ROCK_LO, ROCK_HI = rgb(178, 176, 210), rgb(152, 148, 190), rgb(204, 202, 230)
SNOW, SNOW_LO = rgb(252, 254, 255), rgb(220, 236, 252)
IVORY, IVORY_LO, IVORY_TIP = rgb(250, 236, 196), rgb(226, 200, 150), rgb(255, 250, 232)
ICE, ICE_HI = rgb(140, 214, 255), rgb(206, 242, 255)


def spline(ctrl, n):
    """Catmull-Rom through the control points, n samples."""
    P = [Vector(p) for p in ctrl]
    P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    out = []
    for i in range(n):
        u = i / (n - 1) * (len(P) - 3)
        k = min(int(u), len(P) - 4)
        t = u - k
        p0, p1, p2, p3 = P[k:k + 4]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return out


parts = []
rock = blob("Rock", 0.5, (-0.05, 0.12, 0.22), ROCK, subdiv=2, squash=(1.25, 0.95, 0.95), jitter=0.12, seed=9)
paint(rock, lambda c, n: ROCK_HI if n.z > 0.5 else (ROCK if n.z > -0.2 else ROCK_LO))
parts.append(floor(rock))
for i, (x, y, z, r, sq) in enumerate(((-0.12, 0.1, 0.64, 0.36, (1.35, 1.1, 0.42)), (0.25, 0.05, 0.55, 0.2, (1.2, 1.1, 0.5)))):
    s = blob(f"Snow{i}", r, (x, y, z), SNOW, subdiv=2, squash=sq, jitter=0.06, seed=20 + i)
    gradient(s, SNOW_LO, SNOW)
    parts.append(s)
# the tusk: from the rock's left flank, sweeping round the front and curling up on the right
path = spline([(-0.42, 0.05, 0.38), (-0.32, -0.3, 0.2), (0.0, -0.45, 0.14), (0.38, -0.36, 0.24), (0.6, -0.2, 0.5),
               (0.56, -0.12, 0.8), (0.4, -0.12, 0.9)], 20)
radii = [0.115 - 0.09 * (i / 19) ** 1.3 for i in range(20)]
tusk = tube("Tusk", path, radii, IVORY, segs=7, twist_free=True)
L = len(path)
paint(tusk, lambda c, n: IVORY_TIP if min(range(L), key=lambda j: (path[j] - c).length) > 15 else
      (IVORY if n.z > -0.2 else IVORY_LO))
parts.append(tusk)
# ice crystals at the foot
for i, (x, y, h, tilt) in enumerate(((-0.62, -0.15, 0.3, -18), (-0.5, -0.25, 0.2, 10), (0.5, 0.25, 0.26, 15))):
    c = cylinder(f"Ice{i}", 0.07, h, (x, y, 0.0), ICE, segs=5, r_top=0.0, rot=(0, tilt, 0))
    gradient(c, ICE, ICE_HI)
    parts.append(c)
prop_finish("habitat_prop_mammoth", parts)
