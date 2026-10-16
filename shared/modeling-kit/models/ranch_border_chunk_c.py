# ranch_border_chunk_c: world-border chunk (Slime Ranch), ~56 x 20. A long log rail fence (one rail
# dropped) in front of a low mound, a four-fir stand on the right, goo dollop + puddle, bushes.
# Front (-Y) = map side.
import random
from lib import *
from models._border_chunk import *

R = random.Random(303)
parts = []
parts += fence_run("Fence", -27.5, 9.0, -4.0, R, broken=2, goo_at=-15.0)
hill, hz = mound("Mound", -10.0, 4.0, 34.0, 14.0, 5.5, R, humps=((0.1, 0.1, 0.8, 0.7, 1.0),))
parts.append(hill)
parts += pines("Fir", [(13.0, 3.0, 16.5), (20.0, 5.5, 13.0), (25.0, 1.0, 10.0), (17.0, -2.5, 8.5)], R, hz=hz)
parts += bush("BushA", 10.5, -3.8, R, r=1.8)
parts += bush("BushB", -22.0, 2.0, R, r=2.0)
parts += bush("BushC", -2.0, 3.5, R, r=1.7)
parts += goo_puddle("Puddle", -13.5, -6.5, R, r=1.3)
parts += rocks("Rocks", 24.0, -4.0, R, s=0.7, n=2)
parts += tufts("Tuft", [(-25.0, -5.5), (-6.0, -5.6), (3.0, -5.8), (7.0, -2.0), (-18.0, 0.0), (-8.0, 1.0)], R, hz=hz)
for k, (x, y, c) in enumerate([(-20.0, -5.6, LILAC), (1.0, -5.2, PINK), (-11.0, 2.0, BUTTER)]):
    parts += flower(f"Bloom{k}", (x, y, hz(x, y) + 0.2), R, c)
ship("ranch_border_chunk_c", parts)
