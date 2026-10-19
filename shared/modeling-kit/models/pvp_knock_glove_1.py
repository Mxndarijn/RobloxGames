# pvp_knock_glove_1 "Bonk Glove" (Knockback line, rank 1): a simple soft red mitt on a white cuff with one red stripe.
# Held tool, built upright like ranch_bat: see models/_pvp_glove.py for axes, grip and the shared builders.
from models._pvp_glove import *

S = 1.0
RED, RED_HI, RED_LO = rgb(226, 62, 58), rgb(246, 112, 100), rgb(190, 50, 50)
WHITE, WHITE_LO = rgb(240, 245, 252), rgb(214, 220, 232)
HOLE = rgb(150, 58, 58)

mitt_parts = mitt("Mitt", mitt_colour(RED_LO, RED, RED_HI, S), S=S, tris=320, thumb_tris=80)
band = {"hole": HOLE, "lip": WHITE_LO, "band_lo": WHITE, "band": RED, "band_hi": WHITE, "top": WHITE}
c = cuff("Cuff", lambda row, k: band[row], S=S, segs=14)

ship("pvp_knock_glove_1", mitt_parts + [c], grip=(0, 0, GRIP_Z * S))
