# obby_cloud_puff: wide cumulus for the obby world backdrop (ObbyBackdrop.luau). ~64 x 30 x 30 studs native.
# Separate smooth puffs overlapping in three tiers (low wide rim, mid, crown), flat belly, white top fading to a lilac
# underside: the scalloped outline reads as a cloud from far away.
from lib import *
from models._obby_backdrop import *

P = [(0, 0, 10, 11, 3), (-12, 2, 8, 8.5, 3), (12, -1, 7.5, 9, 3), (-5, -2, 17, 7.5, 2), (6, 2, 16, 7, 2), (-22, 0, 4.5, 6, 2),
     (22, 2, 4.5, 6.5, 2), (-15, -6, 5, 6, 2), (15, 6, 5, 6, 2), (2, 9, 6, 8, 2), (-2, -9, 5.5, 7.5, 2), (-28, 3, 2.5, 4, 2)]
ship("obby_cloud_puff", cloud_puffs("Puff", P, floor=1.0))
