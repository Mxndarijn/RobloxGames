# ranch_border_pine_tall: slim tall fir for the world-border v3 mid layer (~9 x 9 x 24).
import random
from lib import *
from models._border_v3 import *

R = random.Random(201)
parts = conifer("Fir", 0, 0, 24.0, R, tiers=6, tips=7, spread=0.2, shape=0.7, trunk=0.9)
parts += tuft("Tuft", (2.6, -2.4, 0), R, h=1.0) + tuft("TuftB", (-2.5, 1.4, 0), R, h=0.9, blades=2)
finish("ranch_border_pine_tall", parts)
