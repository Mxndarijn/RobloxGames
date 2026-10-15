# ranch_crate: 3 x 3 x 3 stud slatted wooden crate (Slime Ranch). Stackable: flat top and
# bottom, same footprint as ranch_crate_goo. Builder in models/_ranch_crate.py.
from lib import *
from models._ranch_crate import crate

# Slime Ranch palette (theme table, sRGB 0-255)
WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM = PALETTE["ranch_cream"]
WOOD_LO = mix(WOOD_D, WOOD, 0.4)   # lifted: the roblox look turned WOOD_D posts brown
WOOD_HI = mix(WOOD, CREAM, 0.2)
C = {"core": WOOD_D}
parts = crate(C, slat_lo=WOOD, slat_hi=WOOD_HI, post_lo=WOOD_LO, post_hi=WOOD,
              deck_lo=WOOD_LO, deck_hi=WOOD_HI)
finish("ranch_crate", parts)
