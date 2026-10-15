# rock_c: warm stone crag with a taller leaning block (replaces v17 rock_c, ~4.6 x 2.7 x 5.4 studs).
from lib import *
from models._rocks import stone, pebble

BASALT = PALETTE["stone_warm"]  # Volcanic Meadow: warm stone (was blue-grey 118,118,130)
parts = [
    stone("Crag", (3.5, 3.6, 3.1), (0.35, 0.7, 0), seed=31, base=BASALT, top=rgb(186, 174, 152), lean=0.4, cuts=4),
    stone("Low", (3.0, 3.0, 1.75), (-1.05, -1.15, 0), seed=32, base=shade(BASALT, 1.06), top=rgb(186, 174, 152), cuts=2),
    pebble("Peb", 0.7, (1.6, -2.3, 0), seed=33, base=shade(BASALT, 0.95)),
]
finish("rock_c", parts)
