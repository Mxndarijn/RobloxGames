# giant_pine_layered: tall fir with seven stacked skirts for the border v5 giant ring (~36 x 36 x 84):
# the ranch_border_pine_tall recipe with a heavy trunk and fewer, wider, more drooping tiers.
import random
from lib import *
from models._giant_tree import *

R = random.Random(502)
parts = conifer("Fir", 0, 0, 84.0, R, tiers=7, tips=9, spread=0.235, shape=0.78, trunk=1.55)
finish("giant_pine_layered", parts)
