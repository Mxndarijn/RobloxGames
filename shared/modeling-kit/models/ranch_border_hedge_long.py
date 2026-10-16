# ranch_border_hedge_long: long clipped hedge with a few blooms (~25 x 5 x 5.5).
import random
from lib import *
from models._border_v3 import *

R = random.Random(211)
parts = hedge_run("Hedge", -12.0, 12.0, 0.0, R, h=5.0, d=3.6, blooms=4)
parts += tuft("TuftA", (-9.0, -2.6, 0), R, h=1.0) + tuft("TuftB", (7.0, -2.8, 0), R, h=1.0)
finish("ranch_border_hedge_long", parts)
