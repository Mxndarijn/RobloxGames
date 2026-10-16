# ranch_border_chunk_h: deep world-border chunk for the Ground corners (Slime Ranch), ~54 x 46.
# A wide mound carrying a grove of tall firs, with rocks and a goo pond in front; reads from far
# away behind the front row. Front (-Y) = map side.
import random
from lib import *
from models._border_chunk import *

R = random.Random(808)
parts = []
hill, hz = mound("Hill", 0.0, 4.0, 54.0, 42.0, 10.0, R, humps=((-0.25, 0.2, 0.6, 0.6, 1.0), (0.4, 0.3, 0.45, 0.5, 0.8)), NS=26, NR=7)
parts.append(hill)
spots = [(-16.0, 4.0, 18.0), (-6.0, 12.0, 20.0), (5.0, 3.0, 15.0), (14.0, 12.0, 19.0), (-20.0, 15.0, 14.0),
         (22.0, 2.0, 13.0), (2.0, 18.0, 16.0), (-10.0, -5.0, 11.0)]
parts += pines("Fir", [(x, y, h) for x, y, h in spots], R, hz=hz)
parts += rocks("Rocks", 14.0, -9.0, R, s=1.1, n=4)
parts += goo_puddle("Pond", -2.0, -13.0, R, r=2.4)
parts += bush("BushA", -18.0, -8.0, R, r=2.0)
parts += bush("BushB", 4.0, -9.0, R, r=1.7)
parts += tufts("Tuft", [(-24.0, -6.0), (-8.0, -12.0), (8.0, -14.0), (22.0, -8.0)], R, hz=hz)
ship("ranch_border_chunk_h", parts)
