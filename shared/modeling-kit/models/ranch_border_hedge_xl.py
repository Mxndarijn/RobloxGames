# ranch_border_hedge_xl: forty-stud hedge wall in three clipped heights with bloom patches (~41 x 5 x 7).
import random
from lib import *
from models._border_v3 import *

R = random.Random(252)
parts = hedge_run("A", -20.0, -6.5, 0.0, R, h=4.2, d=3.4, blooms=2)
parts += hedge_run("B", -7.0, 8.5, 0.0, R, h=6.6, d=3.8, blooms=2)
parts += hedge_run("C", 8.0, 20.5, 0.0, R, h=5.0, d=3.6, blooms=3)
parts += tuft("TuftA", (-14.0, -2.8, 0), R, h=1.0) + tuft("TuftB", (2.0, -3.0, 0), R, h=1.1) + tuft("TuftC", (15.0, -2.8, 0), R, h=1.0)
finish("ranch_border_hedge_xl", parts)
