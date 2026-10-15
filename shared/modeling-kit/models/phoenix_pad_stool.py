# phoenix_pad_stool: barn stool stand, round seat 7.2 diameter at z=3.0 on 4 splayed legs; footprint ~7.8.
import math
from lib import *
from models._phoenix_ranch import *
SEAT_Z = 3.0
parts = []
s = cylinder("Seat", 3.6, 0.6, (0, 0, SEAT_Z - 0.6), ROOF, segs=14)
bevel(s, 0.15); gradient(s, ROOF_D, ROOF); parts.append(s)
c = cylinder("Cushion", 3.2, 0.22, (0, 0, SEAT_Z - 0.05), CREAM, segs=14); bevel(c, 0.08); parts.append(c)
for i in range(4):
    a = i * math.tau / 4 + math.pi / 4
    top = (math.cos(a) * 2.3, math.sin(a) * 2.3, SEAT_Z - 0.6)
    bot = (math.cos(a) * 3.5, math.sin(a) * 3.5, 0.0)
    parts.append(tube(f"Leg{i}", [bot, top], [0.45, 0.4], WOOD_D, segs=6))
    gradient(parts[-1], shade(WOOD_D, 0.92), WOOD)
parts.append(cylinder("Ring", 2.95, 0.35, (0, 0, 0.9), WOOD, segs=14, r_top=2.85))
parts.append(cylinder("RingIn", 2.6, 0.36, (0, 0, 0.9), WOOD, segs=14))  # visual only (overlap)
finish("phoenix_pad_stool", parts)
