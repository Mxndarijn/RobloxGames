# ranch_border_hedge_stepped: hedge that steps from tall to low (~20 x 5 x 8.5).
import random
from lib import *
from models._border_v3 import *

R = random.Random(213)
parts = hedge_run("Tall", -10.0, -1.0, 0.0, R, h=7.4, d=3.8, blooms=1)
parts += hedge_run("Low", -1.5, 10.0, 0.0, R, h=3.9, d=3.4, blooms=2)
parts += flower("BloomT", (-8.0, -2.4, 6.0), R, PINK, r=0.45) + flower("BloomT2", (-4.0, -2.5, 4.4), R, BUTTER, r=0.45)
parts += tuft("Tuft", (5.0, -2.8, 0), R, h=1.0)
finish("ranch_border_hedge_stepped", parts)
