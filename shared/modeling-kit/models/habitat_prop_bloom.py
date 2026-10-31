# habitat_prop_bloom: a small blossom arch: two white posts and a curved top bar heaped with pink flowers.
import math
from lib import *
from models._habitat_prop2 import *

LEAFC = rgb(104, 192, 88)
W2 = 0.72  # half the post spacing
parts = []
for s in (-1, 1):
    p = box(f"Post{s}", (0.12, 0.12, 0.95), (s * W2, 0, 0.475), WHITE)
    bevel(p, 0.02)
    parts.append(p)
    parts.append(box(f"Foot{s}", (0.2, 0.2, 0.08), (s * W2, 0, 0.04), shade(WHITE, 0.9)))
# arched top: a tube over the posts
arc = []
for j in range(9):
    t = j / 8
    a = math.pi * t
    arc.append((-math.cos(a) * W2, 0, 0.92 + math.sin(a) * 0.28))
parts.append(tube("Arc", arc, [0.06] * len(arc), WHITE, segs=6))
# flowers: leaf puffs then pink 5-petal blossoms along the arc and climbing the posts
R = __import__("random").Random(5)
spots = [arc[j] for j in (0, 2, 3, 4, 5, 6, 8)] + [(s * W2, 0, z) for s in (-1, 1) for z in (0.35, 0.62)]
for j, (x, y, z) in enumerate(spots[:7]):
    parts.append(blob(f"Leaf{j}", 0.13, (x + R.uniform(-0.04, 0.04), y + 0.03, z - 0.04), shade(LEAFC, R.uniform(0.9, 1.05)),
                      subdiv=1, squash=(1.2, 1.0, 0.8), jitter=0.1, seed=j))
for j, (x, y, z) in enumerate(spots):
    c = PINK if j % 3 else mix(PINK, WHITE, 0.45)
    parts += flower(f"F{j}", 0.15, (x, y - 0.08, z), c, rot=(90, j * 23, 0))
# a few petals fallen at the feet
for j in range(3):
    parts.append(blob(f"Fall{j}", 0.06, (R.uniform(-0.4, 0.4), R.uniform(-0.3, 0.1), 0.015), PINK, subdiv=1,
                      squash=(1, 0.7, 0.25), jitter=0))
ship("habitat_prop_bloom", parts)
