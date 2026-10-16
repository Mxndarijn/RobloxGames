# ranch_border_chunk_g: world-border chunk (Slime Ranch), ~56 x 24. A rail fence that steps back
# round a hill (two runs, the right one set behind), a hedge plug in the step, pines on and behind
# the hill, rocks at the left end. Front (-Y) = map side.
import random
from lib import *
from models._border_chunk import *

R = random.Random(707)
parts = []
parts += rocks("Rocks", -23.0, -3.0, R, s=0.9, n=3)
parts += fence_run("FenceA", -17.5, 2.0, -4.5, R, goo_at=-6.0)
parts += hedge_run("Hedge", 1.0, 11.0, -2.0, R, h=4.8, blooms=1)
parts += fence_run("FenceB", 10.0, 28.0, 1.5, R, broken=1)
hill, hz = mound("Hill", 12.0, 8.5, 30.0, 14.0, 8.0, R)
parts.append(hill)
parts += pines("Fir", [(-12.0, 5.0, 17.0), (-3.0, 6.5, 13.0), (8.0, 10.0, 12.0), (20.0, 9.0, 15.5)], R, hz=hz)
parts += bush("Bush", -9.0, -1.5, R, r=1.8)
parts += goo_puddle("Puddle", 16.0, -2.5, R, r=1.5)
parts += tufts("Tuft", [(-14.0, -6.5), (-1.0, -6.4), (6.0, -4.5), (22.0, -0.8), (26.0, 0.0)], R)
parts += flower("BloomA", (19.0, -1.0, 0.3), R, PINK)
parts += flower("BloomB", (-19.0, -5.8, 0.3), R, BUTTER)
ship("ranch_border_chunk_g", parts)
