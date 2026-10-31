# habitat_prop_mecha_goo: a red toolbox with a handle and latches, a big steel wrench leaning on its front.
from models._habitat_prop5 import *

RED, RED_HI = rgb(220, 50, 50), rgb(255, 100, 90)
LID = rgb(200, 40, 46)
METAL, METAL_HI = rgb(170, 180, 196), rgb(226, 232, 242)
BLACK = rgb(60, 60, 70)
parts = [
    gbox("Box", (1.2, 0.6, 0.46), (0, 0.15, 0.23), shade(RED, 0.85), RED, bev=0.05),
    gbox("Lid", (1.24, 0.64, 0.14), (0, 0.15, 0.53), LID, RED_HI, bev=0.04),
    gbox("Seam", (1.22, 0.62, 0.04), (0, 0.15, 0.46), BLACK, bev=0.0),
    tube("Handle", [(-0.3, 0.15, 0.6), (-0.28, 0.15, 0.78), (0.28, 0.15, 0.78), (0.3, 0.15, 0.6)], [0.04] * 4, BLACK, segs=6),
    gbox("Grip", (0.36, 0.11, 0.1), (0, 0.15, 0.79), BLACK, bev=0.03),
]
for sx in (-1, 1):
    parts.append(gbox(f"Latch{sx}", (0.14, 0.05, 0.16), (sx * 0.38, -0.16, 0.46), METAL, METAL_HI, bev=0.015))
# wrench, built in its own xz frame (handle along +z), then leaned back against the box front
wr = [gbox("WHandle", (0.12, 0.06, 0.7), (0, 0, 0.35), METAL, METAL_HI, bev=0.015),
      slab("WJaw", crescent_pts(0.2, 0.12, 0.13, n=8, cz=0.82), 0.07, METAL_HI),
      slab("WRing", circle_pts(0.12, 10, cz=0.0), 0.07, METAL),
      slab("WHole", circle_pts(0.05, 8, cz=0.0), 0.08, BLACK)]
for o in wr:
    parts.append(xf(o, (0.36, -0.34, 0.1), (-12, 0, 0)))
ship("habitat_prop_mecha_goo", parts)
