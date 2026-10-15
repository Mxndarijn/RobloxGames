# rock_b: warm stone stacked slabs (replaces v17 rock_b, ~4.3 x 2.4 x 4.3 studs).
from lib import *
from models._rocks import stone, pebble

SLATE = PALETTE["stone_warm"]  # Volcanic Meadow: warm stone, no blue-grey
parts = [
    stone("Slab", (4.5, 4.55, 1.3), (0.1, 0.1, 0), seed=21, base=shade(SLATE, 0.94), cuts=2),
    stone("Top", (2.9, 2.6, 1.6), (-0.25, 0.25, 0.85), seed=22, base=SLATE, top=rgb(186, 174, 152),
          moss=rgb(104, 158, 64), moss_from=0.8, sink=0.35),
    pebble("Peb", 0.6, (1.75, -1.6, 0), seed=23, base=shade(SLATE, 0.88)),
]
finish("rock_b", parts)
