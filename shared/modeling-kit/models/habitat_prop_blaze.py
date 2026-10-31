# habitat_prop_blaze: a campfire: a ring of stones, crossed logs and big chunky layered flames.
import math, random
from models._habitat_prop3 import *

LOG, LOG_LO, CUT = rgb(150, 94, 58), rgb(112, 68, 44), rgb(236, 196, 132)
RED, ORA, YEL = rgb(255, 78, 40), rgb(255, 150, 30), rgb(255, 230, 90)
R = random.Random(5)
parts = []
# stones round the fire (elliptical ring, wider than deep)
n = 9
for i in range(n):
    a = i / n * math.tau
    parts.append(floor(blob(f"Stone{i}", 0.16, (math.cos(a) * 0.72, math.sin(a) * 0.41, 0.04),
                            shade(ROCK, R.uniform(0.92, 1.08)), subdiv=1, squash=(1.2, 1, 0.75), jitter=0.12, seed=i)))
# logs: three crossed, ends lifted onto each other
for i, (ang, lift) in enumerate(((20, 0.12), (-25, 0.12), (90, 0.2))):
    a = math.radians(ang)
    dx, dy = math.cos(a) * 0.5, math.sin(a) * 0.32
    lg = tube(f"Log{i}", [(-dx, -dy, 0.1), (dx, dy, 0.1 + lift)], (0.1, 0.1), LOG, segs=7)
    paint_faces(lg, lambda p, nn: CUT if abs(nn.z) < 0.97 and abs(Vector((nn.x, nn.y)).normalized().dot(Vector((math.cos(a), math.sin(a))))) > 0.95 else (LOG if nn.z > 0 else LOG_LO))
    parts.append(lg)
# flames: chunky solid teardrops, red outside, orange and yellow cores bulging out of the front
def tongue(name, r, h, col, lo, pos, tilt=0.0, toward=0.0):
    prof = [(0, 0), (r * 0.8, h * 0.05), (r, h * 0.25), (r * 0.85, h * 0.5), (r * 0.45, h * 0.78), (0, h)]
    o = lathe(name, prof, segs=8, phase=0.3,
              color_fn=lambda i, k, z: mix(lo, col, min(1.0, i / 3)))
    return place(o, pos, tilt, toward)


parts.append(tongue("Red", 0.36, 1.12, RED, rgb(230, 60, 40), (0, 0.05, 0.12)))
parts.append(tongue("RedL", 0.2, 0.72, RED, rgb(230, 60, 40), (-0.2, 0.0, 0.14), 24, 180))
parts.append(tongue("RedR", 0.18, 0.66, RED, rgb(230, 60, 40), (0.22, 0.02, 0.14), 26, 0))
parts.append(tongue("Ora", 0.27, 0.8, ORA, rgb(255, 120, 30), (0.0, -0.1, 0.14)))
parts.append(tongue("OraB", 0.22, 0.6, ORA, rgb(255, 120, 30), (0.04, 0.17, 0.14)))
parts.append(tongue("Yel", 0.17, 0.5, YEL, rgb(255, 200, 60), (0.0, -0.2, 0.14)))
# a few spark bits
for i, (x, y, z) in enumerate(((0.3, -0.1, 1.05), (-0.28, 0.05, 1.18), (0.12, 0.1, 1.3))):
    parts.append(blob(f"Spark{i}", 0.045, (x, y, z), YEL, subdiv=1, jitter=0))
ship("habitat_prop_blaze", parts)
