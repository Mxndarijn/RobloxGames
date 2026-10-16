# phoenix_pad_mushroom: squat toadstool, red cap 7.8 across with a flat mesa top at z=3.0 (= stool pad top)
# for the slime, cream spots on the mesa top, chunky flared stem and two baby mushrooms at the foot.
import math
from lib import *
from models._phoenix_pad import *

TOP, CAP_B, CAP_R = 2.97, 1.65, FOOT / 2  # r03: top 2.6 -> 3.0 (= stool pad): r02's low cap hid the stem (read as a cushion)
PATH, PLAZA = P["ranch_path"], P["ranch_plaza"]
parts = []

STEM = [(0, 0), (1.85, 0), (1.9, 0.18), (1.45, 0.55), (1.2, 1.05), (1.15, CAP_B + 0.55), (0, CAP_B + 0.55)]
parts.append(lathe("Stem", STEM, segs=14, color_fn=lambda i, k, z: mix(mix(PLAZA, PATH, 0.5), PATH, z / CAP_B)))

# cap: gill underside -> rounded rim -> shoulder -> flat top
CAP = [(0, CAP_B + 0.45), (1.1, CAP_B + 0.4), (3.2, CAP_B + 0.12), (CAP_R - 0.15, CAP_B), (CAP_R, CAP_B + 0.3),
       (CAP_R - 0.12, CAP_B + 0.7), (CAP_R - 0.5, TOP - 0.22), (CAP_R - 1.1, TOP - 0.03), (2.2, TOP), (1.1, TOP), (0, TOP)]
def cap_col(i, k, z):
    if i <= 2:
        return mix(PLAZA, WOOD, 0.3) if k % 2 else mix(PLAZA, WOOD, 0.15)  # gills
    return mix(ROOF_D, ROOF, min(1.0, (z - CAP_B) / (TOP - CAP_B) * 1.3))
parts.append(lathe("Cap", CAP, segs=18, color_fn=cap_col))

# cream spots (small accents): flush discs on the mesa top (cap top 2.97, spots end at 3.0).
# r05: r04's tilted lenses near the top edge sank to slivers ("crumbs"); flush top discs read as toadstool spots.
for i, (a, r, rad) in enumerate(((0.5, 1.6, 0.55), (2.3, 1.75, 0.45), (3.6, 1.2, 0.6), (5.0, 1.7, 0.5), (1.5, 0.3, 0.35), (4.3, 2.3, 0.35), (1.2, 2.35, 0.3))):
    c = cylinder(f"TopSpot{i}", rad, 0.06, (math.cos(a) * r, math.sin(a) * r, TOP - 0.03), CREAM, segs=10)
    parts.append(c)
# r07: shoulder lenses read either as specks (sunk) or as grey stuck-on buttons (proud): dropped.

# baby mushrooms at the foot (inside the cap footprint)
for i, (a, s, col) in enumerate(((-1.25, 1.3, BUTTER), (-0.7, 1.0, PINK))):
    x, y = math.cos(a) * 2.75, math.sin(a) * 2.75
    parts.append(cylinder(f"BStem{i}", 0.25 * s, 0.75 * s, (x, y, 0), PATH, segs=6))
    parts.append(lathe(f"BCap{i}", [(0, 0.65 * s), (0.6 * s, 0.6 * s), (0.5 * s, 0.85 * s), (0, 1.0 * s)], segs=8,
                       pos=(x, y, 0), color_fn=lambda i_, k, z, c=col: shade(c, 0.85) if i_ == 0 else c))
finish("phoenix_pad_mushroom", parts)
