# ranch_border_pine_twin: two firs of different height sharing a root mound, leaning apart (~14 x 9 x 19).
import random
from lib import *
from models._border_v3 import *

R = random.Random(203)
parts = conifer("A", -2.8, 0.3, 19.0, R, tiers=5, tips=7, spread=0.3, shape=0.7)
parts += conifer("B", 3.6, -0.6, 12.0, R, tiers=4, tips=6, spread=0.34, shape=0.7)
parts.append(stone("Stone", (3.0, 2.6, 1.8), (0.6, -3.0, 0), seed=7, base=SAND, moss=MOSS, moss_from=0.6, cuts=1, n=14))
parts += tuft("Tuft", (-5.6, -2.4, 0), R, h=1.0)
finish("ranch_border_pine_twin", parts)
