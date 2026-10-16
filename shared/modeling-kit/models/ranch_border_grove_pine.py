# ranch_border_grove_pine: six firs of mixed heights and spreads on a shared patch, with a stone (~34 x 14 x 21).
import random
from lib import *
from models._border_v3 import *

R = random.Random(261)
parts = []
for k, (x, y, h, sp, ti) in enumerate([(-13.0, 1.0, 17.0, 0.3, 5), (-7.0, -3.0, 10.5, 0.4, 4), (-1.0, 2.5, 21.0, 0.27, 6),
                                       (5.0, -2.5, 13.0, 0.36, 4), (10.5, 1.5, 17.5, 0.3, 5), (15.0, -3.0, 9.0, 0.42, 3)]):
    parts += conifer(f"Fir{k}", x, y, h, R, tiers=ti, tips=6 + k % 2, spread=sp, shape=0.7)
parts.append(stone("Stone", (4.0, 3.4, 2.4), (2.0, -5.0, 0), seed=71, base=SAND, moss=MOSS, moss_from=0.6, cuts=2, n=16))
parts += tuft("TuftA", (-10.0, -5.0, 0), R, h=1.1) + tuft("TuftB", (9.0, -5.2, 0), R, h=1.0) + tuft("TuftC", (-2.5, -4.0, 0), R, h=1.0, blades=2)
finish("ranch_border_grove_pine", parts)
