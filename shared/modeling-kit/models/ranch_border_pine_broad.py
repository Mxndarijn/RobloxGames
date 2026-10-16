# ranch_border_pine_broad: short wide fir with heavy drooping skirts (~13 x 13 x 13).
import random
from lib import *
from models._border_v3 import *

R = random.Random(202)
parts = conifer("Fir", 0, 0, 13.0, R, tiers=4, tips=8, spread=0.5, shape=0.72, trunk=1.2)
parts += tuft("Tuft", (3.2, -3.4, 0), R, h=1.0) + tuft("TuftB", (-3.6, -2.2, 0), R, h=0.9, blades=2)
parts += flower("Bloom", (-3.0, -3.8, 0.3), R, PINK)
finish("ranch_border_pine_broad", parts)
