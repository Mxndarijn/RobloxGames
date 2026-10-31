# habitat_prop_whiskers: a ball of yarn for the Whiskers slime: a pink-red ball wound with raised strands and a
# loose strand curling out along the ground to the front-right.
import math
from mathutils import Matrix, Vector
from lib import *
from models._habitat_prop import *

YARN = rgb(240, 82, 118)
YARN_LO, YARN_HI = shade(YARN, 0.78), mix(YARN, CREAM, 0.25)
RAD = 0.46
CZ = RAD

ball = blob("Ball", RAD, (0, 0, CZ), seed=1, subdiv=2, jitter=0.0)
regrad(ball, YARN_LO, YARN)
parts = [ball]

# wound strands: great circles at several tilts, a hair above the ball
for n, (tx, tz) in enumerate([(8, 0), (62, 30), (-58, 50), (88, 100), (30, -70)]):
    m = Matrix.Rotation(math.radians(tz), 3, "Z") @ Matrix.Rotation(math.radians(tx), 3, "X")
    pts = []
    for j in range(17):
        a = math.tau * j / 16
        p = m @ Vector((math.cos(a) * (RAD + 0.025), math.sin(a) * (RAD + 0.025), 0))
        pts.append((p.x, p.y, p.z + CZ))
    pts[-1] = pts[0]
    strand = tube(f"Wind{n}", pts[:-1] + [pts[0]], [0.03] * 17, segs=6)
    regrad(strand, YARN_LO, YARN_HI)
    parts.append(strand)

# loose strand: leaves the ball low on the right, loops on the ground toward the front
# r02: a smooth S-curve sampled from a function (hand-placed points kinked)
pts = []
for j in range(15):
    t = j / 14
    x = 0.36 + 0.56 * t
    y = -0.22 - 0.18 * math.sin(t * math.pi * 1.6)
    z = 0.04 + 0.16 * max(0.0, 1 - t * 3.5) ** 2
    pts.append((x, y, z))
loose = tube("Loose", pts, [0.04] * len(pts), YARN_HI, segs=6, twist_free=True)
parts.append(loose)

ship("habitat_prop_whiskers", parts)
