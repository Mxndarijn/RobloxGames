# ranch_border_rock_spire: tall chiselled sandstone pillar with a foot of rubble (~10 x 7 x 15).
import random
from lib import *
from models._border_v3 import *

R = random.Random(224)
parts = [
    stone("Spire", (5.6, 4.8, 15.0), (0.0, 0.4, 0), seed=61, base=SAND, moss=MOSS, moss_from=0.82, lean=0.8, cuts=4, n=24),
    stone("Side", (4.0, 3.6, 5.0), (3.4, -0.6, 0), seed=62, base=shade(SAND, 0.95), moss=MOSS, moss_from=0.7, cuts=2),
    stone("Foot", (3.4, 3.0, 2.2), (-3.2, -1.0, 0), seed=63, base=shade(SAND, 1.03), cuts=1),
    pebble("Peb", 0.7, (1.0, -3.0, 0), seed=64, base=shade(SAND, 0.9)),
]
parts += tuft("TuftA", (-1.6, -3.4, 0), R, h=1.0)
finish("ranch_border_rock_spire", parts)
