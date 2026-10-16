# ranch_border_chunk_e: world-border chunk (Slime Ranch), ~56 x 24. A long clipped hedge across the
# front, a tall hill rising behind its right half, two firs behind the left, a goo-seeping rock
# clump at the right end. Front (-Y) = map side.
import random
from lib import *
from models._border_chunk import *

R = random.Random(505)
parts = []
parts += hedge_run("Hedge", -27.5, 13.0, -4.0, R, h=5.4, blooms=4)
hill, hz = mound("Hill", 8.0, 5.0, 34.0, 18.0, 11.0, R, humps=((0.1, 0.15, 0.6, 0.7, 1.0), (-0.5, 0.1, 0.4, 0.6, 0.55)))
parts.append(hill)
parts += pines("Fir", [(-21.0, 4.0, 16.0), (-12.0, 6.5, 12.5), (24.0, 11.0, 14.0)], R, hz=hz)
parts += rocks("Rocks", 21.5, -3.5, R, s=1.05, n=4)
parts += goo_puddle("Seep", 18.0, -7.0, R, r=1.6)
parts += bush("Bush", 14.5, -3.0, R, r=1.8)
parts += tufts("Tuft", [(-24.0, -7.0), (-8.0, -7.0), (5.0, -7.2), (26.0, -6.0)], R)
for k, (x, y, c) in enumerate([(6.0, 4.0, PINK), (14.0, 6.0, BUTTER), (2.0, 8.0, LILAC)]):
    parts += flower(f"HillBloom{k}", (x, y, hz(x, y) + 0.2), R, c)
ship("ranch_border_chunk_e", parts)
