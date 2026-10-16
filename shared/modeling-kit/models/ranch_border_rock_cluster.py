# ranch_border_rock_cluster: five stones in a ragged heap, a goo seep at the foot (~15 x 9 x 6.5).
import random
from lib import *
from models._border_v3 import *

R = random.Random(223)
parts = [
    stone("A", (5.4, 4.8, 5.8), (-4.6, 1.0, 0), seed=51, base=SAND, moss=MOSS, moss_from=0.62, cuts=3),
    stone("B", (4.0, 3.6, 3.4), (0.0, 1.8, 0), seed=52, base=shade(SAND, 0.94), cuts=2),
    stone("C", (4.8, 4.2, 4.6), (4.6, 0.4, 0), seed=53, base=shade(SAND, 1.03), moss=MOSS, moss_from=0.66, lean=-0.3, cuts=3),
    stone("D", (3.0, 2.6, 2.0), (-1.6, -2.4, 0), seed=54, base=shade(SAND, 0.97), cuts=1),
    stone("E", (2.4, 2.2, 1.6), (3.4, -3.0, 0), seed=55, base=SAND, cuts=1, n=14),
]
parts += goo_puddle("Seep", 0.4, -4.4, R, r=1.4)
parts += tuft("TuftA", (6.4, -2.2, 0), R, h=1.0) + tuft("TuftB", (-7.2, -1.4, 0), R, h=0.9, blades=2)
finish("ranch_border_rock_cluster", parts)
