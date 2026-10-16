# ranch_border_rock_boulder: one big mossy boulder with a smaller one leaning on it (~12 x 8 x 8).
import random
from lib import *
from models._border_v3 import *

R = random.Random(221)
parts = [
    stone("Big", (8.4, 7.0, 7.4), (-0.8, 0.4, 0), seed=31, base=SAND, moss=MOSS, moss_from=0.6, lean=0.5, cuts=3),
    stone("Small", (4.4, 3.8, 3.6), (4.6, -1.4, 0), seed=32, base=shade(SAND, 0.96), moss=MOSS, moss_from=0.7, cuts=2),
    pebble("Peb", 0.8, (-4.6, -2.8, 0), seed=33, base=shade(SAND, 0.92)),
]
parts += tuft("TuftA", (-3.6, -3.4, 0), R, h=1.0) + tuft("TuftB", (2.4, -3.8, 0), R, h=0.9, blades=2)
finish("ranch_border_rock_boulder", parts)
