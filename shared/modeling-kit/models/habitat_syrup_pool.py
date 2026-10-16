# habitat_syrup_pool: shallow wooden dish (7.8 x 3.6 x 7.8) of amber syrup, a raised syrup puck seat at z=2.4, syrup drips over the rim and gumdrop bubbles on the edge.
import math, random
from lib import *
from models._habitat import *

W, H = 7.8, 3.6
SYR, SYR_HI = rgb(236, 150, 40), rgb(255, 205, 100)
R = random.Random(3)
parts = []
DISH = [(0, 0), (3.5, 0), (3.9, 0.4), (3.9, 1.6), (3.6, 1.95), (3.2, 1.8), (3.0, 1.2), (0, 1.2)]
parts.append(lathe("Dish", DISH, segs=16, color_fn=lambda i, k, z: SYR if i >= 5 else shade(mix(WOOD_D, WOOD, min(1, z / 1.8)), 0.92 + 0.1 * (k % 2))))
# syrup mound rising from the dish into the seat puck
MOUND = [(0, 1.1), (3.0, 1.1), (3.05, 1.5), (2.75, 1.9), (2.5, 2.2), (2.3, SEAT - 0.05), (2.15, SEAT), (0, SEAT)]
parts.append(lathe("Syrup", MOUND, segs=16, color_fn=lambda i, k, z: SYR_HI if i >= 6 else mix(SYR, SYR_HI, min(1, z / 2.4))))
for i in range(6):
    a = i * math.tau / 6 + 0.4
    parts.append(blob(f"Bub{i}", 0.38 + 0.12 * (i % 3), (math.cos(a) * 3.4, math.sin(a) * 3.4, 2.15 + 0.15 * (i % 2)), SYR_HI, subdiv=2, squash=(1, 1, 0.8), jitter=0.02, seed=i))
for i, a in enumerate((70, 200, 320)):
    aa = math.radians(a)
    parts.append(tube(f"Drip{i}", [(math.cos(aa) * 3.92, math.sin(aa) * 3.92, 1.9), (math.cos(aa) * 4.0, math.sin(aa) * 4.0, 0.5)], [0.3, 0.2], SYR, segs=5))
    parts.append(blob(f"DripEnd{i}", 0.27, (math.cos(aa) * 4.0, math.sin(aa) * 4.0, 0.5), SYR_HI, subdiv=1, jitter=0))
# butter pat on the rim
parts.append(bbox("Butter", (0.9, 0.9, 0.45), (-2.9, 2.2, 2.2), BUTTER, shade(BUTTER, 1.1), bev=0, rot=(0, 0, 30)))
fit(finish("habitat_syrup_pool", parts), W, H, W)
