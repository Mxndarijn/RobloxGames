# habitat_prop_prism: signature prop for Prism: a small six-band rainbow arch whose feet rest in two white cloud
# puffs. Front faces -Y (the arch face).
import math
from lib import *
from models._habitat_prop4 import *

BANDS = [rgb(170, 110, 236), rgb(80, 156, 250), rgb(96, 210, 96), rgb(255, 222, 60), rgb(255, 152, 48), rgb(255, 80, 86)]
CLOUD, CLOUD_D = rgb(255, 255, 255), rgb(214, 222, 240)

parts = []
CZ, R0, r = 0.26, 0.34, 0.054
for i, col in enumerate(BANDS):  # inner purple .. outer red
    R = R0 + i * 2 * r * 0.95
    parts.append(torus(f"Band{i}", R, r, seg=10, seg2=4, rot=(90, 0, 0), arc=(0, math.pi), pos=(0, 0, CZ), color=col))
# cloud puffs round each foot
for s in (-1, 1):
    fx = s * (R0 + 2.5 * 2 * r * 0.95)
    for k, (dx, dy, dz, rr) in enumerate([(0, -0.02, 0.2, 0.24), (s * 0.16, 0.04, 0.13, 0.18), (-s * 0.17, -0.04, 0.12, 0.17)]):
        b = blob(f"Cl{s}{k}", rr, (fx + dx, dy, dz), CLOUD, subdiv=2, jitter=0.03, seed=k + (s > 0) * 5)
        paint(b, lambda c, n: CLOUD if n.z > -0.1 else CLOUD_D)
        parts.append(floor(b))
prop_finish("habitat_prop_prism", parts)
