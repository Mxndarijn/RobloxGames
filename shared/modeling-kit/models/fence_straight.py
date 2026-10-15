# fence_straight: one 7-stud picket fence segment (plot kit). Length along X (posts centred on
# x = -3.5 and +3.5, so neighbours share a post exactly), pickets on the -Y (front/outer) face,
# rails behind. Height ~3.5 (posts 3.6 with caps). Snap pitch 7.0 = SEGMENT.
import random
from lib import *
from models._fence import *

L = SEGMENT
R = random.Random(7)
parts = []
for i, x in enumerate((-L / 2, L / 2)):
    parts += post(f"Post{i}", x, 0, 0.7, 3.3)
for k, z in enumerate((0.95, 2.45)):
    parts.append(beam(f"Rail{k}", -L / 2, L / 2, 0.12, z, 0.24, 0.34, RAIL, lo=shade(RAIL, 0.9)))
N, W = 8, 0.62
pitch = (L - 0.7) / N
for i in range(N):
    x = -L / 2 + 0.35 + pitch * (i + 0.5)
    h = 2.95 + (0.12 if i % 2 else 0.0) + R.uniform(-0.05, 0.05)
    col = PLANK if i % 3 else PLANK_ALT
    parts.append(picket(f"Picket{i}", x, W, h, -0.2, -0.02, z0=0.12, tip=0.32, lean=R.uniform(-0.04, 0.04), color=col))
finish("fence_straight", parts)
