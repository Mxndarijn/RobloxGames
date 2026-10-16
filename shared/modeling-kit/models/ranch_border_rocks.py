# ranch_border_rocks: warm sandstone boulder cluster for the world border (Slime Ranch), ~13 x 7 x 9.
# Chiselled hull stones (models/_rocks.py) with moss caps, a goo seep puddle at the foot on the
# map side (-Y), tufts and a bloom. Ranch stone, never basalt (THEME: no rock walls, so keep it a clump).
import random
from lib import *
from models._border import *
from models._rocks import stone, pebble

R = random.Random(41)
SAND = rgb(204, 182, 150)  # r02: +7 % value, the shadow side went brown
MOSS = mix(FIELD, FIELD_D, 0.3)
parts = [
    stone("Big", (6.4, 5.6, 6.8), (-1.6, 0.8, 0), seed=12, base=SAND, moss=MOSS, moss_from=0.6, lean=0.4),
    stone("Mid", (4.6, 4.0, 4.4), (3.2, 1.2, 0), seed=17, base=shade(SAND, 0.95), moss=MOSS, moss_from=0.68, lean=-0.3),
    stone("Low", (3.6, 3.2, 2.3), (1.0, -2.2, 0), seed=21, base=shade(SAND, 1.04), cuts=2),
    stone("Back", (3.4, 3.0, 3.6), (-5.0, 2.0, 0), seed=3, base=shade(SAND, 0.92), moss=MOSS, cuts=2),
    pebble("PebA", 0.8, (5.6, -1.6, 0), seed=5, base=shade(SAND, 0.9)),
    pebble("PebB", 0.6, (-4.6, -2.3, 0), seed=8, base=SAND),
]
# goo seep: flat puddle (squashed blob sunk to the ground) + a highlight lens
g = blob("Goo", 1.5, (-2.4, -3.1, 0.0), GOO, subdiv=2, squash=(1.5, 0.9, 0.16), jitter=0.03)
gradient(g, GOO, mix(GOO, GOO_HI, 0.35))
parts.append(g)
parts.append(blob("GooHi", 0.5, (-2.0, -3.3, 0.14), GOO_HI, subdiv=1, squash=(1.4, 1, 0.3), jitter=0.0))
for k, (x, y) in enumerate([(-4.0, -1.2), (3.6, -1.9), (5.6, 1.6), (-0.6, -3.6)]):
    parts += tuft(f"Tuft{k}", (x, y, 0), R, h=1.0, blades=3 + k % 2)
parts += flower("Bloom", (2.4, -3.2, 0.3), R, PINK)
finish("ranch_border_rocks", parts)
