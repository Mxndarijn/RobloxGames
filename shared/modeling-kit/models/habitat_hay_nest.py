# habitat_hay_nest: golden straw nest (7.8 x 4.0 x 7.8), flat woven straw seat at z=2.4, tufts round the rim, a few straws.
import math, random
from lib import *
from models._habitat import *

W, H = 7.8, 4.0
HAY = BUTTER
R = random.Random(5)
parts = []
MOUND = [(0, 0), (3.5, 0), (3.85, 0.4), (3.8, 1.2), (3.5, 1.9), (2.9, 2.2), (2.3, 2.1), (0, 2.1)]
parts.append(lathe("Mound", MOUND, segs=16, color_fn=lambda i, k, z: shade(mix(shade(HAY, 0.7), HAY, min(1, z / 2.2)), R.uniform(0.92, 1.05))))
parts.append(seat_disc("Seat", 2.15, shade(HAY, 1.04), edge=shade(HAY, 0.78)))
N = 9
for i in range(N):
    a = i * math.tau / N + 0.2
    r = 3.0 + 0.1 * (i % 2)
    parts.append(blob(f"Tuft{i}", 0.85 + 0.15 * (i % 3 == 0), (math.cos(a) * r, math.sin(a) * r, 2.35 + 0.3 * (i % 2)),
                      shade(HAY, R.uniform(0.9, 1.05)), subdiv=1, squash=(1.4, 1.0, 1.0), jitter=0.05, seed=i, rot=(0, 0, math.degrees(a) + 90)))
for i in range(6):
    a = i * math.tau / 6 + 0.6
    parts.append(tube(f"Straw{i}", [(math.cos(a) * 3.3, math.sin(a) * 3.3, 2.5), (math.cos(a) * 3.55, math.sin(a) * 3.55, 3.5 + 0.2 * (i % 2))],
                      [0.14, 0.05], shade(HAY, 1.08), segs=4))
# a little brown egg in the rim at the back
parts.append(blob("Egg", 0.5, (0.9, 3.0, 2.75), CREAM, subdiv=1, squash=(0.8, 0.8, 1.0), jitter=0))
fit(finish("habitat_hay_nest", parts), W, H, W)
