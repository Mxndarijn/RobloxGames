# ranch_border_sapling_trio: three young firs of three heights plus a bush (~12 x 8 x 9), fills gaps.
import random
from lib import *
from models._border_v3 import *

R = random.Random(205)
parts = conifer("A", -3.0, 0.0, 8.5, R, tiers=3, tips=6, spread=0.34, shape=0.7)
parts += conifer("B", 0.8, 1.6, 6.0, R, tiers=3, tips=5, spread=0.36, shape=0.7)
parts += conifer("C", 4.2, -0.4, 7.2, R, tiers=3, tips=6, spread=0.34, shape=0.7)
parts += bush("Bush", -0.6, -2.8, R, r=1.5)
finish("ranch_border_sapling_trio", parts)
