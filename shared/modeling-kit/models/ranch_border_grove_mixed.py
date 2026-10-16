# ranch_border_grove_mixed: two oaks, two firs and a bush round a mossy stone (~31 x 15 x 17).
import random
from lib import *
from models._border_v3 import *

R = random.Random(262)
parts = round_tree("OakA", -9.0, 0.5, 13.0, R, crown=5.8, trunk=0.9, lean=0.6, n=5)
parts += round_tree("OakB", 9.5, 1.5, 10.5, R, crown=4.8, trunk=0.8, lean=-0.4, n=5)
parts += conifer("FirA", 0.5, 2.5, 16.0, R, tiers=5, tips=7, spread=0.3, shape=0.7)
parts += conifer("FirB", 4.5, -2.5, 9.0, R, tiers=3, tips=6, spread=0.36, shape=0.7)
parts += bush("Bush", -3.6, -4.0, R, r=1.7)
parts.append(stone("Stone", (4.4, 3.8, 2.8), (-6.0, -5.2, 0), seed=72, base=SAND, moss=MOSS, moss_from=0.6, cuts=2, n=16))
parts += flower("BloomA", (7.0, -5.0, 0.3), R, PINK) + flower("BloomB", (-12.0, -4.4, 0.3), R, BUTTER) + tuft("Tuft", (11.0, -4.0, 0), R, h=1.0)
finish("ranch_border_grove_mixed", parts)
