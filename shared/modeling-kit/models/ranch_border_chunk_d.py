# ranch_border_chunk_d: world-border chunk (Slime Ranch), ~54 x 24. A pine grove: seven firs of
# uneven height in two staggered rows, round bushes and two rock clumps at their feet, a short
# hedge on the left end. Front (-Y) = map side.
import random
from lib import *
from models._border_chunk import *

R = random.Random(404)
parts = []
parts += pines("Fir", [(-15.0, 2.0, 17.5), (-6.0, 6.0, 14.0), (2.0, 1.0, 18.5), (10.0, 6.5, 13.0),
                       (18.0, 1.5, 16.0), (-1.0, 8.0, 10.0), (24.5, 6.0, 11.0)], R)
parts += hedge_run("Hedge", -27.0, -16.0, -3.0, R, h=4.6, blooms=2)
parts += bush("BushA", -9.0, -3.5, R, r=1.9)
parts += bush("BushB", 6.5, -3.0, R, r=1.6)
parts += bush("BushC", 22.0, -3.5, R, r=2.0)
parts += rocks("RocksA", -2.5, -4.0, R, s=0.75, n=3)
parts += rocks("RocksB", 13.5, -4.5, R, s=0.6, n=2)
parts += goo_puddle("Puddle", 10.0, -7.0, R, r=1.2)
parts += tufts("Tuft", [(-13.0, -5.0), (3.5, -6.0), (17.0, -6.0), (26.0, -3.0)], R)
parts += flower("BloomA", (-6.5, -5.4, 0.3), R, BUTTER)
parts += flower("BloomB", (19.5, -5.8, 0.3), R, PINK)
ship("ranch_border_chunk_d", parts)
