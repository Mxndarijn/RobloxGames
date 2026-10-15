# ranch_water_trough: long double-bay goo-water trough on log cradles, centre divider, pump spout end (Slime Ranch).
# Variant of ranch_feed_trough: no pellets, two bays, round log body look. rot= in DEGREES.
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
METAL = PALETTE["ranch_metal"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
parts = []


def pbox(n, s, p, bot, top, bev=0.1, rot=(0, 0, 0)):
    o = box(n, s, p, bot, rot=rot); bevel(o, bev); gradient(o, bot, top); return o


L, D, Z0, TOP = 9.0, 2.6, 0.6, 2.1
for sx in (-3.3, 0, 3.3):
    parts.append(pbox(f"Cradle{sx}", (0.8, D + 0.6, Z0 + 0.1), (sx, 0, (Z0 + 0.1) / 2), WOOD_LO, WOOD_D, 0.15))
parts.append(pbox("Floor", (L - 0.4, D - 0.4, 0.45), (0, 0, Z0 + 0.22), WOOD_LO, WOOD, 0.1))
for sy in (-1, 1):
    parts.append(pbox(f"Side{sy}", (L, 0.45, TOP - Z0), (0, sy * (D / 2 - 0.22), (Z0 + TOP) / 2), WOOD_LO, WOOD, 0.14, rot=(sy * -8, 0, 0)))
for sx in (-1, 0, 1):
    w = 0.5 if sx else 0.4
    parts.append(pbox(f"End{sx}", (w, D, TOP - Z0 + 0.15), (sx * (L / 2 - 0.25), 0, (Z0 + TOP + 0.15) / 2), WOOD_LO, WOOD, 0.14))
for sx in (-1, 1):
    parts.append(pbox(f"Goo{sx}", (L / 2 - 0.75, D - 0.9, 0.3), (sx * (L / 4), 0, TOP - 0.3), GOO, mix(GOO, GOO_HI, 0.45), 0.12))
    parts.append(blob(f"Bub{sx}", 0.22, (sx * L / 4 + 0.6, 0.2, TOP - 0.12), GOO_HI, subdiv=1, squash=(1, 1, .6), jitter=0.03))
# metal bands
for sx in (-2.0, 2.0):
    parts.append(pbox(f"Band{sx}", (0.2, D + 0.12, TOP - Z0 + 0.05), (sx, 0, (Z0 + TOP) / 2), METAL, METAL, 0.04))
# spout on +X end
parts.append(pbox("SpoutPost", (0.6, 0.6, 3.6), (L / 2 + 0.35, 0, 1.8), WOOD_D, WOOD, 0.1))
parts.append(cylinder("Spout", 0.2, 1.1, (L / 2 + 0.35, 0, 3.3), METAL, segs=6, rot=(0, -90, 0)))
parts.append(blob("Drip", 0.22, (L / 2 - 0.8, 0, TOP - 0.05), GOO_HI, subdiv=1, squash=(1, 1, 0.7), jitter=0.03))
finish("ranch_water_trough", parts)
