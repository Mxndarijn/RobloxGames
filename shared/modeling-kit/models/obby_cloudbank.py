# obby_cloudbank: one piece of the obby world's cloud sea (ObbyBackdrop.luau). ~180 x 34 x 160 studs native, a wide
# flat-bottomed bank of big rolling puffs. The game lays ~20 of them in overlapping rings at two depths over a flat
# base disc, so the sea has hills and depth instead of one flat plane.
import math
import random

from lib import *
from models._obby_backdrop import *

rnd = random.Random(5)
P = []
for i in range(17):
    a = i * 2.39996
    d = 74 * math.sqrt((i + 0.5) / 17)
    r = 22 + 10 * rnd.random() - d * 0.08
    P.append((math.cos(a) * d * 1.1, math.sin(a) * d, r * 0.25 + rnd.random() * 4, r, 2))
ship("obby_cloudbank", cloud_puffs("Bank", P, floor=2.0, seed=9))
