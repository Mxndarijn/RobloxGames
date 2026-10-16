# ranch_border_hedge_round: short hedge of three fat scalloped bushes, pink blooms (~15 x 6 x 6).
import random
from lib import *
from models._border_v3 import *

R = random.Random(212)
parts = []
core = box("Core", (9.0, 3.0, 3.2), (0, 0, 1.6), FIELD_D)
gradient(core, shade(FIELD_D, 0.92), FIELD)
parts.append(core)
for k, (x, y, r) in enumerate([(-4.6, 0.1, 2.5), (0.2, -0.2, 3.0), (4.8, 0.2, 2.3)]):
    for j, (dx, dy, rr, dz) in enumerate([(0, 0, r, 0.0), (r * 0.5, 0.6, r * 0.7, r * 0.55), (-r * 0.45, -0.5, r * 0.65, r * 0.5)]):
        b = blob(f"Bush{k}_{j}", rr, (x + dx, y + dy, rr * 0.88 + dz), seed=R.randint(0, 99), subdiv=2, squash=(1.1, 0.95, 0.92), jitter=0.06)
        gradient(lowpoly(b, 0.62), FIELD_D, FIELD_L if dz else FIELD)
        parts.append(b)
for k, (x, z, c) in enumerate([(-5.0, 3.0, PINK), (0.6, 4.9, BUTTER), (5.2, 2.6, LILAC), (-1.6, 2.4, PINK)]):
    parts += flower(f"Bloom{k}", (x, -2.6 - (z - 2.4) * 0.05, z), R, c, r=0.42)
finish("ranch_border_hedge_round", parts)
