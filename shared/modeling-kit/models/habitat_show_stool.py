# habitat_show_stool: royal blue show stool (7.8 x 4.6 x 7.8), flat velvet cushion at z=2.4, gold trim, gold stars on the rim.
import math
from lib import *
from models._habitat import *

W, H = 7.8, 4.6
BLUE, BLUE_D = rgb(80, 120, 214), rgb(52, 80, 160)
GOLD = rgb(255, 214, 90)
parts = []
BASE = [(0, 0), (3.6, 0), (3.85, 0.15), (3.85, 0.55), (3.3, 0.75), (2.4, 1.1), (2.4, 1.6), (3.3, 1.75), (3.7, 1.9), (3.75, 2.15), (3.4, 2.3), (0, 2.3)]
def col(i, k, z):
    if i in (1, 2, 3) or i in (7, 8):
        return GOLD
    return mix(BLUE_D, BLUE, min(1, z / 2.3)) if i < 7 else shade(GOLD, 0.9)
parts.append(lathe("Base", BASE, segs=16, color_fn=col))
parts.append(lathe("Cushion", [(0, 2.0), (3.35, 2.0), (3.5, 2.2), (3.25, SEAT - 0.08), (3.0, SEAT), (0, SEAT)], segs=16,
                   color_fn=lambda i, k, z: BLUE if i >= 3 else mix(BLUE_D, BLUE, 0.6)))
# gold tassels hanging, and gold stars on the rim (diamonds)
for i in range(6):
    a = i * math.tau / 6 + 0.3
    parts.append(blob(f"Tas{i}", 0.2, (math.cos(a) * 3.5, math.sin(a) * 3.5, 1.9), GOLD, subdiv=0, jitter=0))
for i, a in enumerate((90, 150, 210)):
    aa = math.radians(a)
    x, y = math.cos(aa) * 3.1, math.sin(aa) * 3.1
    parts.append(cylinder(f"Pin{i}", 0.12, 0.9, (x, y, 2.3), GOLD, segs=4))
    parts.append(blob(f"Star{i}", 0.62, (x, y, 3.5 + 0.55 * (i % 2)), GOLD, subdiv=1, squash=(1, 0.5, 1), jitter=0, rot=(0, 0, math.degrees(aa))))
for i, a in enumerate((20, -30)):
    aa = math.radians(a)
    parts.append(blob(f"Rose{i}", 0.45, (math.cos(aa) * 3.1, math.sin(aa) * 3.1, 2.85), ROOF, subdiv=1, squash=(1, 1, 0.7), jitter=0.05, seed=i))
fit(finish("habitat_show_stool", parts), W, H, W)
