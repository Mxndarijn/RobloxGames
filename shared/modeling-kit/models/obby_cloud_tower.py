# obby_cloud_tower: tall stacked cumulus for the obby world backdrop (ObbyBackdrop.luau). ~50 x 44 x 40 studs native.
from lib import *
from models._obby_backdrop import *

P = [(0, 0, 9, 12, 3), (-13, 3, 6, 8, 2), (13, -2, 6, 8.5, 2), (-2, 1, 19, 10, 3), (5, -2, 28, 8, 2), (-6, 3, 33, 6.5, 2),
     (9, 5, 18, 7, 2), (-10, -6, 14, 6.5, 2), (2, -8, 8, 7, 2), (-4, 9, 10, 7, 2), (-20, 0, 3, 5, 2), (20, 1, 3, 5, 2)]
ship("obby_cloud_tower", cloud_puffs("Puff", P, floor=1.0, seed=4))
