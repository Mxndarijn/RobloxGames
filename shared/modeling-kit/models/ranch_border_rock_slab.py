# ranch_border_rock_slab: low wide ledge of two flat stones, grassy top (~14 x 7 x 3.6).
import random
from lib import *
from models._border_v3 import *

R = random.Random(222)
parts = [
    stone("SlabA", (9.6, 6.0, 3.4), (-1.8, 0.3, 0), seed=41, base=shade(SAND, 1.02), moss=MOSS, moss_from=0.5, cuts=2, n=18),
    stone("SlabB", (6.4, 4.6, 2.4), (4.4, -0.6, 0), seed=42, base=shade(SAND, 0.95), moss=MOSS, moss_from=0.55, cuts=2),
    pebble("PebA", 0.7, (-6.2, -2.4, 0), seed=43, base=SAND), pebble("PebB", 0.55, (0.8, -3.4, 0), seed=44, base=shade(SAND, 0.9)),
]
parts += tuft("TuftA", (-4.0, -3.2, 0), R, h=1.0, blades=4) + flower("Bloom", (2.6, -3.0, 0.3), R, LILAC)
finish("ranch_border_rock_slab", parts)
