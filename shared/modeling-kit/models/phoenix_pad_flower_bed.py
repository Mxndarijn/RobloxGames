# phoenix_pad_flower_bed: octagonal plank planter (7.8 flat-to-flat) with a flower ring in soil and a
# sawn tree stump in the middle; the slime stands on the flat stump top (r 2.5) at z=2.4 (= crate pad).
import math
from lib import *
from models._phoenix_pad import *

TOP = 2.4
WALL_H, APO, T = 1.45, 3.75, 0.5  # r02/r03: corner posts set the bbox (r01 7.98)
LEAF, LEAF_D = P["ranch_field_light"], P["ranch_field_dark"]
LILAC, PLAZA, PATH = P["ranch_lilac"], P["ranch_plaza"], P["ranch_path"]
FLOWERS = [PINK, LILAC, BUTTER]
parts = []

# planter walls: 8 boards around an octagon, corner posts at the joints
side = 2 * APO * math.tan(math.pi / 8)
for i in range(8):
    a = i * math.tau / 8
    col = WOOD if i % 2 else shade(WOOD, 0.94)
    parts.append(bbox(f"Board{i}", (side + 0.05, T, WALL_H), (math.cos(a) * (APO - T / 2), math.sin(a) * (APO - T / 2), WALL_H / 2),
                      mix(WOOD_D, col, 0.5), col, bev=0.1, rot=(0, 0, math.degrees(a) + 90)))
    b = a + math.pi / 8
    rc = 3.72  # r03: proud of the boards again so the corners read
    parts.append(bbox(f"Post{i}", (0.7, 0.7, WALL_H + 0.25), (math.cos(b) * rc, math.sin(b) * rc, (WALL_H + 0.25) / 2),
                      shade(WOOD_D, 0.95), WOOD_D, bev=0.0, rot=(0, 0, math.degrees(b))))  # r05: bevel cost 260 tris, unseen
soil = cylinder("Soil", APO - 0.3, 0.2, (0, 0, WALL_H - 0.35), shade(WOOD_D, 0.85), segs=8, rot=(0, 0, 22.5))
parts.append(soil)

# stump: bark sides with a root flare, ring-banded sawn top
ROWS = [(0, 0.9), (2.75, 0.9), (2.5, 1.4), (2.4, TOP - 0.1), (2.3, TOP), (1.6, TOP), (0.8, TOP), (0, TOP)]
def stump_col(i, k, z):
    if i >= 5:
        return [PLAZA, mix(PLAZA, WOOD, 0.35), PLAZA][i - 5]
    if i == 4:
        return mix(PATH, WOOD, 0.4)
    c = mix(WOOD_D, mix(WOOD_D, WOOD, 0.45), (z - 0.9) / (TOP - 0.9))  # r05: darker bark vs the planter boards
    return shade(c, 0.92) if k % 2 else c
parts.append(lathe("Stump", ROWS, segs=16, color_fn=stump_col))

# flower ring: leaf tufts + blooms in the soil, kept below the stump top
N = 10
for i in range(N):
    a = i * math.tau / N + 0.2
    r = 3.05 + 0.15 * ((i * 3) % 2)
    x, y = math.cos(a) * r, math.sin(a) * r
    parts.append(blob(f"Leaf{i}", 0.6, (x, y, WALL_H + 0.05), LEAF if i % 2 else mix(LEAF_D, LEAF, 0.5),
                      subdiv=1, squash=(1.2, 1.2, 0.7), jitter=0.12, seed=i))
    h = WALL_H + 0.42 + 0.08 * (i % 3)  # r02: blooms bigger; r03: eyes under the stump top
    parts.append(blob(f"Bloom{i}", 0.5, (x * 0.98, y * 0.98, h), FLOWERS[i % 3], subdiv=1, squash=(1, 1, 0.6), jitter=0.08, seed=20 + i))
    parts.append(blob(f"Eye{i}", 0.17, (x * 0.98, y * 0.98, h + 0.16), BUTTER if i % 3 != 2 else PINK, subdiv=1, jitter=0))
finish("phoenix_pad_flower_bed", parts)
