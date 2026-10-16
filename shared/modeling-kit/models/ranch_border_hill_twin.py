# ranch_border_hill_twin: two humps of different height with a saddle between, a lone oak and rocks (~50 x 22 x 18).
import random
from lib import *
from models._border_v3 import *

R = random.Random(243)
parts = hill("Twin", 0, 0, 50.0, 22.0, 13.0, R,
             humps=((-0.42, 0.0, 0.55, 0.85, 1.0), (0.48, 0.05, 0.45, 0.75, 0.62)),
             trees=[(-14.0, 2.0, 13.0), (-8.0, 4.0, 9.0), (13.0, 2.5, 9.5)],
             rocks=[(1.0, -5.6, (3.6, 3.0, 2.6))], tufts_n=8, NS=28, NR=7)
finish("ranch_border_hill_twin", parts)
