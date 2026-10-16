# ranch_border_chunk_f: world-border chunk (Slime Ranch), ~54 x 22. A big sandstone outcrop in the
# middle with a goo pool at its foot, hedges either side, a fir and a fence stub behind.
# Front (-Y) = map side.
import random
from lib import *
from models._border_chunk import *
from models._rocks import stone

R = random.Random(606)
parts = []
parts += hedge_run("HedgeL", -27.0, -12.0, -2.5, R, h=5.0, blooms=2)
parts += hedge_run("HedgeR", 11.0, 27.0, -3.0, R, h=4.6, blooms=2)
for k, (size, x, y, moss) in enumerate([((10.0, 8.0, 10.5), -3.0, 2.0, 0.6), ((7.0, 6.0, 7.0), 4.0, 0.0, 0.66),
                                        ((5.0, 4.4, 3.4), -0.5, -3.5, None), ((5.5, 5.0, 6.0), -9.0, 3.0, 0.7),
                                        ((4.0, 3.6, 2.6), 7.5, -3.2, None)]):
    parts.append(stone(f"Out{k}", size, (x, y, 0), seed=R.randint(0, 999), base=shade(SAND, R.uniform(0.94, 1.04)),
                       moss=MOSS if moss else None, moss_from=moss or 0.7, lean=R.uniform(-0.6, 0.6), cuts=3, n=18))
parts += goo_puddle("Pool", -5.5, -6.0, R, r=2.4)
parts += goo_puddle("Pool2", 3.0, -6.3, R, r=1.1)
parts += pines("Fir", [(8.0, 7.0, 15.0), (-16.0, 6.0, 12.0)], R)
parts += fence_run("Fence", 14.0, 26.0, 5.0, R)
parts += tufts("Tuft", [(-11.0, -5.0), (9.5, -6.0), (-1.5, -7.5), (12.0, 1.0)], R)
parts += flower("Bloom", (8.5, -6.0, 0.3), R, LILAC)
ship("ranch_border_chunk_f", parts)
