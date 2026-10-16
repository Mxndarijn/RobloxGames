# ranch_border_grove_rocky: two firs and an oak behind a rock heap with a spire and a goo seep (~30 x 12 x 16).
import random
from lib import *
from models._border_v3 import *

R = random.Random(263)
parts = conifer("FirA", -6.0, 3.0, 15.0, R, tiers=5, tips=7, spread=0.3, shape=0.7)
parts += conifer("FirB", 8.5, 3.5, 11.0, R, tiers=4, tips=6, spread=0.34, shape=0.7)
parts += round_tree("Oak", 15.5, 1.0, 9.0, R, crown=3.9, trunk=0.7, n=5)
parts += [
    stone("Spire", (4.4, 3.8, 11.0), (-11.5, -1.0, 0), seed=81, base=SAND, moss=MOSS, moss_from=0.82, lean=0.6, cuts=4, n=22),
    stone("A", (5.4, 4.6, 5.0), (-3.0, -2.0, 0), seed=82, base=shade(SAND, 0.97), moss=MOSS, moss_from=0.62, cuts=3),
    stone("B", (4.2, 3.6, 3.2), (3.4, -2.6, 0), seed=83, base=SAND, cuts=2),
    stone("C", (3.2, 2.8, 2.0), (0.2, -4.4, 0), seed=84, base=shade(SAND, 1.03), cuts=1, n=14),
]
parts += goo_puddle("Seep", 8.4, -4.2, R, r=1.3)
parts += tuft("TuftA", (11.5, -3.0, 0), R, h=1.1) + tuft("TuftB", (-8.0, -4.4, 0), R, h=1.0)
finish("ranch_border_grove_rocky", parts)
