# ranch_border_hill_dome: tall round grassy hill with a stone outcrop on its flank (~42 x 30 x 22).
import random
from lib import *
from models._border_v3 import *

R = random.Random(242)
parts = hill("Dome", 0, 0, 42.0, 30.0, 15.0, R,
             humps=((0.0, 0.0, 0.9, 0.9, 1.0), (-0.45, -0.15, 0.55, 0.6, 0.4)),
             trees=[(-4.0, 4.0, 13.0), (5.0, 2.0, 11.0), (-11.0, 3.0, 9.0), (11.0, 5.0, 8.0)],
             rocks=[(9.0, -7.0, (4.8, 4.0, 3.6)), (-9.0, -8.0, (3.2, 2.8, 2.4))], tufts_n=8, NS=28, NR=7)
finish("ranch_border_hill_dome", parts)
