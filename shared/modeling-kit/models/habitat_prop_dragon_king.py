# habitat_prop_dragon_king: a dragon's gold hoard: a heaped coin pile, a gold goblet and a big red gem.
import math, random
from models._habitat_prop3 import *

RUBY, RUBY_LO = rgb(255, 70, 96), rgb(200, 30, 70)
R = random.Random(4)
parts = []
# the heap: a squashed lumpy dome, clipped flat at the deck
heap = blob("Heap", 0.7, (0, 0.05, 0.0), GOLD, subdiv=2, squash=(1.25, 0.75, 0.62), jitter=0.06, lumps=0.12, seed=3)
parts.append(grad(floor(heap), GOLD_LO, rgb(255, 222, 100)))
# coins: flat discs on the heap surface and spilling onto the deck in front
def coin(i, x, y, z, tilt, toward):
    c = cylinder(f"Coin{i}", 0.12, 0.035, (0, 0, -0.0175), rgb(255, 214, 80), segs=8)
    paint_faces(c, lambda p, n: rgb(255, 230, 120) if abs(n.z) > 0.9 else GOLD_LO)
    return place(c, (x, y, z), tilt, toward)

k = 0
for ring_r, n, zf in ((0.35, 5, 0.36), (0.62, 7, 0.24)):
    for j in range(n):
        a = j / n * math.tau + R.uniform(-0.3, 0.3)
        x, y = math.cos(a) * ring_r * 1.25, 0.05 + math.sin(a) * ring_r * 0.75
        parts.append(coin(k, x, y, zf + R.uniform(0, 0.05), R.uniform(15, 35), math.degrees(a)))
        k += 1
for x, y in ((-0.55, -0.42), (0.05, -0.47), (0.62, -0.38), (-0.2, -0.5)):  # flat spills on the deck
    parts.append(coin(k, x, y, 0.02, R.uniform(0, 8), R.uniform(0, 360)))
    k += 1
# goblet on the right side of the heap, leaning a little
gob = lathe("Goblet", [(0, 0), (0.17, 0.0), (0.17, 0.04), (0.05, 0.08), (0.04, 0.3), (0.16, 0.38), (0.2, 0.6),
                       (0.17, 0.6), (0.13, 0.42), (0, 0.4)], segs=10,
            color_fn=lambda i, k, z: rgb(255, 226, 110) if i in (5, 6) else (GOLD_LO if i >= 7 else GOLD))
place(gob, (0.5, 0.12, 0.2), 10, 0)
parts.append(gob)
parts.append(place(blob("GobGem", 0.05, (0, -0.19, 0.5), rgb(80, 180, 255), subdiv=1, jitter=0), (0.5, 0.12, 0.2), 10, 0))
# the big gem: faceted ruby on top-left of the pile
gem = lathe("Ruby", [(0, 0), (0.27, 0.24), (0.19, 0.36), (0, 0.36)], segs=8,
            color_fn=lambda i, k, z: RUBY_LO if i == 0 else (RUBY if k % 2 else rgb(255, 130, 150)))
place(gem, (-0.38, 0.05, 0.22), 8, -90, 22.5)
parts.append(gem)
ship("habitat_prop_dragon_king", parts)
