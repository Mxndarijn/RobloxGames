# habitat_prop_octo: signature prop for Octo: a striped spiral (nautilus) shell standing upright, facing front,
# on a splash of purple ink with a few drops. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

CREAM, STRIPE, LIP = rgb(252, 238, 214), rgb(244, 128, 72), rgb(255, 170, 190)
INK, INK_HI = rgb(96, 64, 168), rgb(140, 104, 214)

parts = []
# spiral: points in the XZ plane, growing radius; the tube grows with it
N, T = 22, 3.1 * math.pi
pts, rads = [], []
for i in range(N + 1):
    t = i / N * T
    rr = 0.075 * math.exp(0.21 * t)
    pts.append((math.cos(t) * rr, 0.0, math.sin(t) * rr))
    rads.append(max(0.03, rr * 0.5))
cz = -min(p[2] - rd for p, rd in zip(pts, rads)) + 0.02
pts = [(x, y, z + cz) for x, y, z in pts]
for k in range(0, N, 2):  # alternate cream and orange bands, two steps each, overlapping one point
    seg = tube(f"Shell{k}", pts[k:k + 3], rads[k:k + 3], CREAM if (k // 2) % 2 else STRIPE, segs=7)
    parts.append(seg)
# aperture lip at the open end + pink inside
ex, ey, ez = pts[-1]
dx, dz = pts[-1][0] - pts[-2][0], pts[-1][2] - pts[-2][2]
ang = math.degrees(math.atan2(dz, dx))
lip = torus("Lip", rads[-1] * 0.92, 0.06, seg=12, seg2=5, rot=(0, 90, 0), color=LIP)
move(lip, (ex, ey, ez), (0, -ang, 0))
inner = cylinder("Inner", rads[-1] * 0.9, 0.04, rot=(0, 90, 0), color=shade(LIP, 0.85), segs=12)
move(inner, (ex + 0.01, ey, ez), (0, -ang, 0))
parts += [lip, inner]

# ink splash: a flat lobed puddle under the shell's front right plus drops
pud = cylinder("Ink", 0.5, 0.05, (0.25, -0.15, 0), INK, segs=14, jitter=0.25, seed=4)
paint(pud, lambda c, n: INK_HI if n.z > 0.5 else INK)
parts.append(pud)
for i, (x, y, rr) in enumerate([(0.78, -0.42, 0.11), (0.62, 0.22, 0.08), (-0.35, -0.4, 0.09), (0.85, -0.05, 0.06)]):
    d = blob(f"Drop{i}", rr, (x, y, rr * 0.35), INK_HI, subdiv=1, squash=(1, 1, 0.45), jitter=0.05, seed=i)
    parts.append(floor(d))
# two ink drops flying up off the splash
for i, (x, y, z, rr) in enumerate([(0.7, -0.25, 0.42, 0.075), (0.84, -0.1, 0.24, 0.055)]):
    parts.append(blob(f"Fly{i}", rr, (x, y, z), INK_HI, subdiv=1, squash=(0.85, 0.85, 1.25), jitter=0, seed=9 + i))
prop_finish("habitat_prop_octo", parts)
