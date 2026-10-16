# ranch_border_oak_round: round-crowned leafy tree, the soft counterpart to the firs (~13 x 12 x 15).
import random
from lib import *
from models._border_v3 import *

R = random.Random(204)
parts = round_tree("Oak", 0, 0, 13.4, R, crown=6.2, trunk=0.95, lean=0.8, n=6)
parts += flower("BloomA", (-3.0, -3.4, 0.3), R, BUTTER) + flower("BloomB", (3.4, -3.0, 0.3), R, PINK)
parts += tuft("Tuft", (2.0, -3.6, 0), R, h=1.0)
finish("ranch_border_oak_round", parts)
