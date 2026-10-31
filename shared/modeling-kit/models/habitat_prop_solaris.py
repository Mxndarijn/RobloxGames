# habitat_prop_solaris: a sundial: sandstone pedestal, golden dial tilted to the front, orange gnomon, sun rays.
import math
from models._habitat_prop5 import *

STONE, STONE_HI = rgb(214, 176, 124), rgb(246, 222, 176)
GOLD, GOLD_LO = rgb(255, 210, 70), rgb(246, 170, 48)
GNOMON = rgb(236, 104, 40)
TICK = rgb(176, 90, 36)
parts = [
    lathe("Pedestal", [(0, 0), (0.4, 0), (0.4, 0.1), (0.28, 0.16), (0.2, 0.22), (0.2, 0.56), (0.3, 0.62), (0.34, 0.68), (0, 0.68)],
          segs=10, color_fn=vgrad(STONE, STONE_HI, 0, 0.68)),
]
dial = [lathe("Dial", [(0, 0), (0.48, 0), (0.48, 0.08), (0, 0.08)], segs=20, color_fn=vgrad(GOLD_LO, GOLD, 0, 0.08))]
for k in range(12):
    a = k * math.tau / 12
    dial.append(box(f"Tick{k}", (0.11, 0.035, 0.03), (math.cos(a) * 0.38, math.sin(a) * 0.38, 0.09), TICK, rot=(0, 0, math.degrees(a))))
for k in range(8):  # flat sun rays round the dial edge
    a = k * math.tau / 8 + math.pi / 8
    c, s_ = math.cos(a), math.sin(a)
    tri = [(c * 0.44 - s_ * 0.08, s_ * 0.44 + c * 0.08), (c * 0.6, s_ * 0.6), (c * 0.44 + s_ * 0.08, s_ * 0.44 - c * 0.08)]
    dial.append(slab(f"Ray{k}", tri, 0.05, GOLD_LO, (0, 0, 0.015), plane="xy"))
dial.append(slab("Gnomon", [(-0.36, 0), (0.3, 0), (0.24, 0.07), (-0.36, 0.5)], 0.06, GNOMON, (0, 0, 0.08), rot_z=-90))
for o in dial:
    parts.append(xf(o, (0, 0, 0.66), (-24, 0, 0)))
ship("habitat_prop_solaris", parts)
