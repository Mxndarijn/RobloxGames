# plot_skin_mushroom: Mushroom Meadow plot decor (replaces the plot's mailbox slot in game).
# One big red-capped toadstool lamp with cream spots, two small ones, a mossy tuft; a soft glow bulb hangs under the big cap.
# Rounded, chunky, ~5.6 x 6.4 x 5.6 studs. Origin bottom-centre (finish()). Target < ~900 tris.
import math, random
from lib import *
from models._phoenix_pad import lathe

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, ROOF, ROOF_D = PALETTE["ranch_cream"], PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
LEAF, LEAF_D = PALETTE["ranch_field_light"], PALETTE["ranch_field_dark"]
BUTTER, GOO_HI = PALETTE["ranch_butter"], PALETTE["ranch_goo_hi"]
R = random.Random(11)
parts = []

# mossy tuft base
TUFT = [(0, 0), (2.5, 0), (2.7, 0.25), (2.5, 0.65), (1.8, 0.95), (0, 1.0)]
parts.append(lathe("Tuft", TUFT, segs=14, color_fn=lambda i, k, z: shade(mix(LEAF_D, LEAF, min(1, z / 0.9)), R.uniform(0.94, 1.05))))


def toadstool(tag, x, y, h, r_cap, stem_r, spots, seed):
    rr = random.Random(seed)
    parts.append(lathe(f"Stem{tag}", [(0, 0), (stem_r * 1.25, 0), (stem_r * 1.05, h * 0.3), (stem_r * 0.9, h), (0, h + 0.05)],
                       segs=8, pos=(x, y, 0.9),
                       color_fn=lambda i, k, z: mix(CREAM, WOOD, 0.25) if i == 0 else mix(CREAM, shade(CREAM, 0.9), z / max(h, 0.1))))
    z0 = 0.9 + h * 0.82
    cap = [(0, 0), (r_cap * 0.9, 0.0), (r_cap, r_cap * 0.22), (r_cap * 0.86, r_cap * 0.58), (r_cap * 0.5, r_cap * 0.84), (0, r_cap * 0.95)]

    def cap_col(i, k, z):
        if i == 0:
            return mix(ROOF_D, WOOD_D, 0.4)  # gills underside
        spot = (k * 7 + i * 3 + seed) % 5 == 0 and i >= 3
        return CREAM if spot else shade(mix(ROOF_D, ROOF, min(1, 0.45 + i * 0.15)), rr.uniform(0.96, 1.04))
    parts.append(lathe(f"Cap{tag}", cap, segs=10, pos=(x, y, z0), color_fn=cap_col))
    return z0


# big lamp-mushroom (centre-back), two small ones
top = toadstool("A", 0.0, 0.2, 3.3, 2.7, 0.55, 5, 1)
toadstool("B", 1.55, -1.25, 1.1, 1.15, 0.28, 3, 2)
toadstool("C", -1.7, -0.85, 1.6, 1.4, 0.32, 3, 3)
# soft glow bulb under the big cap (butter, not neon)
parts.append(blob("Bulb", 0.42, (0.0, -0.1, top - 0.3), BUTTER, seed=4, subdiv=2, squash=(1, 1, 1.15), jitter=0.02))
gradient(parts[-1], mix(BUTTER, WOOD, 0.2), GOO_HI)
# leaf tufts + tiny pebbles for hand-made feel
for i, a in enumerate((20, 110, 200, 290)):
    x, y = 2.35 * math.cos(math.radians(a)), 2.35 * math.sin(math.radians(a))
    parts.append(cone(f"Leaf{i}", 0.38, 0.75, (x, y, 0.45), LEAF, segs=5)); gradient(parts[-1], LEAF_D, LEAF)
finish("plot_skin_mushroom", parts)
