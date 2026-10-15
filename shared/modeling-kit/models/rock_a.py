# rock_a: warm sandstone boulder group with a moss cap (replaces v17 rock_a, ~6.1 x 2.9 x 5.3 studs).
from lib import *
from models._rocks import stone, pebble

SAND = rgb(168, 150, 128)
MOSS = rgb(104, 158, 64)
parts = [
    stone("Main", (5.0, 4.45, 3.1), (0.65, 0.35, 0), seed=3, base=SAND, moss=MOSS, moss_from=0.66, lean=-0.3),
    stone("Side", (2.75, 2.5, 1.85), (-2.1, -1.25, 0), seed=7, base=shade(SAND, 0.94), cuts=2),
    pebble("Peb", 0.75, (2.0, -2.15, 0), seed=9, base=shade(SAND, 0.88)),
]
finish("rock_a", parts)
