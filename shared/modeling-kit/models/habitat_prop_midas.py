# habitat_prop_midas: a pyramid stack of shiny gold bars (3 + 2 + 1), with a few loose coins.
import math
from models._habitat_prop5 import *

GOLD, GOLD_LO, GOLD_HI = rgb(255, 204, 64), rgb(246, 168, 44), rgb(255, 238, 150)
BW, BT, BH, BL = 0.32, 0.24, 0.2, 0.56   # bottom width, top width, height, length


def bar(name, x, y, z, along_x=False):
    prof = [(-BW / 2, 0), (BW / 2, 0), (BT / 2, BH), (-BT / 2, BH)]
    o = slab(name, prof, BL, GOLD_LO, hi=GOLD)
    top = gbox(name + "Top", (BT - 0.08, BL - 0.16, 0.02), (0, 0, BH), GOLD_HI, bev=0.0)
    out = []
    for p in (o, top):
        out.append(xf(p, (x, y, z), (0, 0, 90 if along_x else 0)))
    return out


parts = []
for i, x in enumerate((-0.36, 0.0, 0.36)):
    parts += bar(f"A{i}", x, 0.05, 0.0)
for i, x in enumerate((-0.18, 0.18)):
    parts += bar(f"B{i}", x, 0.05, BH)
parts += bar("C", 0.0, 0.05, 2 * BH)
# loose coins in front
for k, (x, y, rz) in enumerate(((-0.62, -0.32, 0), (0.6, -0.28, 0), (0.42, -0.4, 0))):
    parts.append(gcyl(f"Coin{k}", 0.1, 0.035, (x, y, 0), GOLD_LO, GOLD, segs=10))
coin = gcyl("CoinUp", 0.12, 0.04, (0, 0, -0.02), GOLD, GOLD_HI, segs=12)
parts.append(xf(coin, (-0.66, -0.12, 0.12), (75, 0, 20)))
ship("habitat_prop_midas", parts)
