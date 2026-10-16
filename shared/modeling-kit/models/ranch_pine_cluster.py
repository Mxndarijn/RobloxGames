# ranch_pine_cluster: three firs of uneven height + a round bush, a border tree clump (Slime Ranch).
# ~14 x 16 x 10. Firs use the tree_pine skirt recipe in ranch greens (darks >= field_dark).
import random
from lib import *
from models._border import *

R = random.Random(7)
parts = []
parts += fir("A", -2.6, 0.9, 16.0, R, tips=8)
parts += fir("B", 2.9, 1.4, 12.0, R, tips=7)
parts += fir("C", 0.4, -2.0, 8.6, R, tips=7, tiers=4)
bush = blob("Bush", 1.5, (4.9, -1.9, 1.05), FIELD, seed=4, subdiv=2, squash=(1.2, 1.0, 0.75), jitter=0.06)
gradient(bush, FIELD_D, FIELD_L)
parts.append(bush)
parts += flower("Bloom", (4.3, -3.2, 1.3), R, PINK)
for k, (x, y) in enumerate([(-4.8, -1.6), (-0.9, -3.4), (2.2, -1.2)]):
    parts += tuft(f"Tuft{k}", (x, y, 0), R, h=0.9)
finish("ranch_pine_cluster", parts)
