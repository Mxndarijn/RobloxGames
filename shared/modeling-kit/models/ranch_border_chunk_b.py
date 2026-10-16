# ranch_border_chunk_b: world-border chunk (Slime Ranch), ~56 x 24. A big two-hump grassy hill on
# the left with a goo seep at its foot, a sandstone clump and a short hedge on the right, two firs
# on the hill's shoulder. Front (-Y) = map side.
import random
from lib import *
from models._border_chunk import *

R = random.Random(202)
parts = []
hill, hz = mound("Hill", -10.0, 2.0, 36.0, 20.0, 9.0, R)
parts.append(hill)
parts += pines("Fir", [(-17.0, 7.0, 14.0), (-3.0, 8.0, 11.0), (20.0, 5.0, 16.0), (-24.0, 4.0, 10.0)], R, hz=hz)
parts += rocks("Rocks", 12.0, -3.5, R, s=1.15, n=4)
parts += hedge_run("Hedge", 17.5, 28.5, -2.6, R, h=4.8, blooms=2)
parts += goo_puddle("Seep", -6.0, -8.2, R, r=1.8)
from models._rocks import stone
parts.append(stone("HillStone", (3.0, 2.6, 2.2), (-19.0, -4.5, hz(-19.0, -4.5) - 0.5), seed=5, base=SAND, moss=MOSS, cuts=2, n=16))
parts += tufts("Tuft", [(-22.0, -3.0), (-12.0, -6.0), (2.0, -6.5), (5.0, -2.0), (-16.0, 1.0)], R, hz=hz)
for k, (x, y, c) in enumerate([(-14.0, -4.0, PINK), (-1.0, -4.0, BUTTER), (-9.0, 0.0, LILAC)]):
    parts += flower(f"Bloom{k}", (x, y, hz(x, y) + 0.15), R, c)
ship("ranch_border_chunk_b", parts)
