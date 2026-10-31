# habitat_prop_aurora: signature prop for Aurora: a slim white ribbon pole with a gold star ball on top and three
# wavy ribbons (green, purple, pink) streaming out to the side like aurora light. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

POLE, POLE_HI, BASE, BASE_HI = rgb(236, 240, 250), rgb(255, 255, 255), rgb(120, 96, 200), rgb(156, 132, 232)
GOLD = rgb(255, 210, 70)
RIBS = [(rgb(90, 236, 150), 1.12), (rgb(176, 110, 250), 1.02), (rgb(255, 120, 200), 0.92)]

parts = []
PX = -0.48
b = cylinder("Base", 0.3, 0.12, (PX, 0, 0), BASE, segs=10, r_top=0.26)
paint(b, lambda c, n: BASE_HI if n.z > 0.5 else BASE)
parts.append(b)
parts.append(cylinder("Pole", 0.045, 1.08, (PX, 0, 0.12), POLE, segs=6))
parts.append(torus("Collar", 0.065, 0.03, seg=8, seg2=4, pos=(PX, 0, 1.12), color=GOLD))
parts.append(blob("TopBall", 0.09, (PX, 0, 1.24), GOLD, subdiv=1, jitter=0))
# ribbons: start at the pole, stream right with a travelling wave in y and z, sagging a little
for i, (col, z0) in enumerate(RIBS):
    pts, wd = [], []
    n = 10
    for k in range(n + 1):
        t = k / n
        x = PX + 0.05 + t * 1.2
        y = math.sin(t * 5.2 + i * 1.3) * 0.16 * t - 0.04 * i
        z = z0 - t * (0.32 + i * 0.06) + math.sin(t * 4.0 + i) * 0.06 * t
        pts.append((x, y, z))
        wd.append(0.11 * (1 - 0.35 * t))
    rb = ribbon(f"Rib{i}", pts, wd, thick=0.03, color=col)
    paint(rb, lambda c, n, col=col: shade(col, 1.12) if n.z > 0.3 or n.y < -0.3 else col)
    parts.append(rb)
    parts.append(slab(f"Tip{i}", [(0, -0.05), (0.12, -0.06), (0.06, 0), (0.12, 0.06), (0, 0.05)], 0.03,
                      pos=(pts[-1][0] - 0.01, pts[-1][1], pts[-1][2] - 0.0), color=col))
prop_finish("habitat_prop_aurora", parts)
