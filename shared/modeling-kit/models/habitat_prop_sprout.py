# habitat_prop_sprout: a green watering can for the Sprout slime: round tapered body with a lighter band, an
# arched top handle, and a long spout to the right ending in a sprinkler rose.
import math
from lib import *
from models._habitat_prop import *

G_LO, G_HI = rgb(58, 156, 72), rgb(132, 220, 96)
BAND = rgb(250, 220, 92)
ROSE = rgb(236, 210, 90)
BX = -0.30  # body centre x (spout goes to +x)
BR, BH = 0.40, 0.78

prof = [(0, 0), (BR - 0.02, 0), (BR, 0.04), (BR, 0.44), (BR * 0.98, 0.52), (BR * 0.96, BH - 0.06), (BR * 0.88, BH), (0.22, BH + 0.02),
        (0.22, BH + 0.06), (0, BH + 0.06)]
BAND_ROWS = {2}


def body_col(i, k, z):
    if i == 3:
        return BAND
    return shade(mix(G_LO, G_HI, min(1, z / BH)), 1.06 if k % 4 == 0 else 1.0)


parts = [lathe("Body", prof, segs=16, pos=(BX, 0, 0), color_fn=body_col)]
# top handle: arch across the top, front to back... reads better as a side arch from the back over to the side
pts = []
for j in range(9):
    a = math.pi * j / 8
    pts.append((BX - 0.30 * math.cos(a) - 0.04, 0.0, BH - 0.02 + 0.40 * math.sin(a)))
h = tube("Handle", pts, [0.055] * 9, segs=6)
regrad(h, G_LO, G_HI)
parts.append(h)
# spout from the low front-right of the body up to the right
s0 = (BX + BR * 0.8, 0, 0.18)
s1 = (BX + BR + 0.55, 0, 0.62)
s2 = (BX + BR + 0.82, 0, 0.88)
sp = tube("Spout", [s0, s1, s2], [0.09, 0.06, 0.05], segs=8)
regrad(sp, G_LO, G_HI)
parts.append(sp)
# rose: a short flared cone at the spout tip, pointing along the spout
d = [s2[i] - s1[i] for i in range(3)]
L = math.sqrt(sum(c * c for c in d))
u = [c / L for c in d]
r0 = s2
r1 = tuple(s2[i] + u[i] * 0.16 for i in range(3))
parts.append(tube("Rose", [r0, r1], [0.06, 0.15], ROSE, segs=10))
# sprinkle holes: dark dots on the rose face
from mathutils import Matrix, Vector
n = Vector(u)
q = n.to_track_quat("Z", "Y")
for j in range(6):
    a = math.tau * j / 6
    p = Vector(r1) + q @ Vector((math.cos(a) * 0.08, math.sin(a) * 0.08, 0.005))
    dot = cylinder(f"Hole{j}", 0.022, 0.01, (0, 0, 0), shade(G_LO, 0.6), segs=6)
    dot.data.transform(q.to_matrix().to_4x4())
    dot.data.transform(Matrix.Translation(p))
    parts.append(dot)

ship("habitat_prop_sprout", parts)
