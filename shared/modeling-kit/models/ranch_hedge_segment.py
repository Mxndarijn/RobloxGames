# ranch_hedge_segment: ~12-stud clipped farm hedge for the world border (Slime Ranch), ~12 x 6 x 4.6.
# Tiles side by side with overlap (ends are rounded puffs, no hard cut). Front (-Y) = map side.
import random
from lib import *
from models._border import *

R = random.Random(11)
W, D, H = 11.4, 3.9, 5.2
parts = []
# solid core so nothing shows through between puffs
core = box("Core", (W - 2.2, D - 1.7, H - 2.0), (0, 0, (H - 2.0) / 2), FIELD_D)  # r03: hidden behind the puffs
bevel(core, 0.3)
gradient(core, shade(FIELD_D, 0.92), FIELD)
parts.append(core)
# body puffs: two staggered rows of uneven blobs + a crown row (LESSONS tree_oak: no bead necklace)
n = 6
for k in range(n):
    x = -W / 2 + 0.9 + k * (W - 1.8) / (n - 1) + R.uniform(-0.25, 0.25)
    for side in (-1, 1):
        r = R.uniform(1.45, 1.75)
        p = blob(f"Puff{k}{side}", r, (x, side * D * 0.2, r * 0.92 + R.uniform(0.0, 0.25)), FIELD,
                 seed=R.randint(0, 999), subdiv=2, squash=(1.0, 0.72, 0.9), jitter=0.05)
        gradient(p, FIELD_D, FIELD)
        parts.append(p)
for k in range(5):
    x = -W / 2 + 1.5 + k * (W - 3.0) / 4 + R.uniform(-0.3, 0.3)
    r = R.uniform(1.25, 1.55)
    p = blob(f"Crown{k}", r, (x, R.uniform(-0.3, 0.3), H - r * 0.85 + R.uniform(-0.25, 0.15)), FIELD_L,
             seed=R.randint(0, 999), subdiv=2, squash=(1.1, 0.95, 0.75), jitter=0.05)
    gradient(p, FIELD, FIELD_L)
    parts.append(p)
# a few blooms on the map side (-Y) and the top
for k, (x, z, col) in enumerate([(-3.8, 3.4, PINK), (-1.2, 4.6, BUTTER), (2.0, 2.6, LILAC), (4.1, 4.2, PINK), (0.6, 3.6, PINK)]):
    parts += flower(f"Bloom{k}", (x, -D * 0.2 - 0.75, z), R, col)
finish("ranch_hedge_segment", parts)
