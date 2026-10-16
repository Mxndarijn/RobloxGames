# ranch_border_chunk_a: world-border chunk (Slime Ranch), ~54 x 22. Hedge run on the left, log rail
# fence with a goo dollop in the middle, sandstone clump on the right, three firs behind.
# Front (-Y) = map side. One mesh = one MeshPart slot (WorldBorder.luau places ~40 of these).
import random
from lib import *
from models._border_chunk import *

R = random.Random(101)
parts = []
parts += hedge_run("Hedge", -27.0, -7.5, -3.0, R, h=5.2, blooms=3)
parts += fence_run("Fence", -8.5, 12.0, -4.2, R, goo_at=5.0)
parts += rocks("Rocks", 20.5, -2.8, R, s=1.0, n=3)
hill, hz = mound("Mound", -13.0, 4.5, 30.0, 12.0, 5.0, R)  # r02: mass behind the hedge
parts.append(hill)
parts += pines("Fir", [(-21.0, 5.5, 15.5), (-6.0, 6.5, 12.0), (8.0, 5.0, 17.0), (-14.0, 7.5, 10.5), (16.5, 6.0, 11.0)], R, hz=hz)
parts += bush("BushA", 14.0, -1.0, R)
parts += goo_puddle("Puddle", 1.0, -6.6, R, r=1.5)
parts += tufts("Tuft", [(-4.0, -6.0), (9.5, -6.2), (16.0, -5.0), (25.5, -4.6)], R)
parts += flower("Bloom", (14.8, -5.8, 0.3), R, PINK)
ship("ranch_border_chunk_a", parts)
