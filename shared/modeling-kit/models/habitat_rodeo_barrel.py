# habitat_rodeo_barrel: hooped rodeo barrel (7.8 x 4.5 x 7.8) with a flat lid at z=2.4, rope ring and a lucky horseshoe + hay at the rim.
import math
from lib import *
from models._habitat import *

W, H = 7.8, 4.5
METAL = P["ranch_metal"]
parts = []
def barrel_col(i, k, z):
    if i in (1, 2) or i in (5, 6):
        return mix(P["slate"], METAL, 0.3)
    return shade(WOOD, 0.9 + 0.12 * (k % 2))
BARREL = [(0, 0), (3.2, 0), (3.5, 0.2), (3.85, 0.7), (3.9, 1.2), (3.85, 1.7), (3.5, 2.2), (3.3, SEAT - 0.3), (3.1, SEAT - 0.3), (0, SEAT - 0.3)]
parts.append(lathe("Barrel", BARREL, segs=16, color_fn=lambda i, k, z: mix(P["slate"], METAL, 0.3) if (0.5 < z < 0.95 or 1.7 < z < 2.1) else shade(WOOD, 0.88 + 0.14 * (k % 2))))
LID = [(0, 2.0), (3.2, 2.0), (3.28, SEAT + 0.25), (2.9, SEAT + 0.32), (2.7, SEAT), (0, SEAT)]  # raised rope lip, flat seat inside
parts.append(lathe("Lid", LID, segs=16, color_fn=lambda i, k, z: (mix(CREAM, WOOD, 0.45) if k % 2 else CREAM) if i in (1, 2, 3) else mix(WOOD, CREAM, 0.3)))
# hay bundle and clover-green rodeo flag at the back rim
parts.append(cylinder("FlagPole", 0.12, 2.3, (-2.7, 2.1, 2.3), CREAM, segs=5))
parts.append(bbox("Flag", (1.5, 0.08, 0.9), (-1.95, 2.1, 4.1), shade(ROOF_D, 0.9), ROOF, bev=0))
for i in range(4):
    parts.append(blob(f"Hay{i}", 0.5, (2.0 + 0.35 * i, 2.5 - 0.25 * i, SEAT + 0.55), BUTTER, subdiv=1, squash=(1.5, 0.9, 0.9), jitter=0.05, seed=i, rot=(0, 0, 40)))
fit(finish("habitat_rodeo_barrel", parts), W, H, W)
