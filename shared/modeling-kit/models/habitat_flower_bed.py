# habitat_flower_bed: octagonal plank planter (7.8 x 4.0 x 7.8) with soil, flowers on the rim and a stump seat at z=2.4.
import math
from lib import *
from models._habitat import *

W, H = 7.8, 4.0
LEAF, LEAF_D = P["ranch_field_light"], P["ranch_field_dark"]
LILAC = P["ranch_lilac"]
APO, WALL_H, T = 3.75, 1.7, 0.5
parts = []
side = 2 * APO * math.tan(math.pi / 8)
for i in range(8):
    a = i * math.tau / 8
    col = WOOD if i % 2 else shade(WOOD, 0.94)
    parts.append(bbox(f"Board{i}", (side + 0.05, T, WALL_H), (math.cos(a) * (APO - T / 2), math.sin(a) * (APO - T / 2), WALL_H / 2),
                      mix(WOOD_D, col, 0.5), col, bev=0, rot=(0, 0, math.degrees(a) + 90)))
parts.append(cylinder("Soil", APO - 0.3, 1.9, (0, 0, 0), mix(WOOD_D, P["bark_dark"], 0.5), segs=8, rot=(0, 0, 22.5)))
for i in range(8):
    b = i * math.tau / 8 + math.pi / 8
    parts.append(bbox(f"Post{i}", (0.6, 0.6, WALL_H + 0.3), (math.cos(b) * 3.7, math.sin(b) * 3.7, (WALL_H + 0.3) / 2), WOOD_D, shade(WOOD_D, 1.1), bev=0, rot=(0, 0, math.degrees(b))))
# stump seat
STUMP = [(0, 0.9), (2.6, 0.9), (2.35, 1.5), (2.2, SEAT - 0.1), (2.15, SEAT), (0, SEAT)]
parts.append(lathe("Stump", STUMP, segs=12, color_fn=lambda i, k, z: shade(P["bark"], 0.9 + 0.1 * (k % 2)) if i < 4 else mix(WOOD, CREAM, 0.35)))
# flowers: stem + petal blob, round the rim between stump and boards
COLS = [PINK, LILAC, BUTTER, CREAM]
for i in range(10):
    a = i * math.tau / 10 + 0.15
    r = 3.05
    h = 2.9 + 0.4 * (i % 3)
    x, y = math.cos(a) * r, math.sin(a) * r
    parts.append(cylinder(f"Stem{i}", 0.07, h - 1.4, (x, y, 1.4), LEAF_D, segs=4))
    parts.append(blob(f"Fl{i}", 0.42, (x, y, h + 0.1), COLS[i % 4], subdiv=1, squash=(1, 1, 0.7), jitter=0.04, seed=i))
    parts.append(blob(f"Ct{i}", 0.17, (x, y, h + 0.3), BUTTER if i % 4 != 2 else ROOF, subdiv=0, jitter=0))
    if i % 2:
        parts.append(blob(f"Lf{i}", 0.35, (x * 0.93, y * 0.93, 1.85), LEAF, subdiv=1, squash=(1.2, 0.6, 0.5), jitter=0.05, seed=i, rot=(0, 0, math.degrees(a))))
fit(finish("habitat_flower_bed", parts), W, H, W)
