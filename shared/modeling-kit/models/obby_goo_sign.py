# obby_goo_sign: the Obby portal's status sign (steal-a-slime), standing beside the Goo Ring. Two chunky wood posts
# carry a wood-framed board with a deep plum face on both sides (blank: the game puts a SurfaceGui on each face);
# goo from the ring oozes along the top and drips over the frame only, so the text area stays clean. A little
# goo puddle at the foot ties it to the ring.
# Face (each side): 8.0 x 3.6 at centre z ZC, 0.12 proud of the frame.
import math
from mathutils import Vector
from lib import *
from lib.goo import Ball, metaball_mesh, paint_goo, frame_quat
from models._phoenix_ranch import bbox, WOOD, WOOD_D

GOO = hexc("#4FC234")
HI = hexc("#A8F062")
DEEP = hexc("#1F6E25")
PLUM = hexc("#2E2646")
PLUM_LO = hexc("#221B36")
WOOD_LO = mix(WOOD_D, WOOD, 0.5)

PW, PH = 0.9, 7.2  # post width / height
PX = 3.9  # posts at x = +-PX
ZC = 4.9  # board centre height
FW, FH, FD = 9.0, 4.6, 0.5  # frame
BW, BH = 8.0, 3.6  # face
parts = []

for s in (-1, 1):
    x = s * PX
    parts.append(bbox(f"Post{s}", (PW, PW, PH), (x, 0, PH / 2), WOOD_LO, WOOD, bev=0.14))
    parts.append(blob(f"Knob{s}", 0.5, (x, 0, PH + 0.12), WOOD, subdiv=2, squash=(1, 1, 0.7), jitter=0))
parts.append(bbox("Frame", (FW, FD, FH), (0, 0, ZC), shade(WOOD_D, 0.93), WOOD_D, bev=0.14))
for s in (-1, 1):  # the plum face on both sides, a little proud of the frame
    parts.append(bbox(f"Face{s}", (BW, 0.12, BH), (0, s * (FD / 2 + 0.04), ZC), PLUM_LO, PLUM, bev=0.04))

# Goo along the top: a soft ridge of lenses, then short drips over the frame band on both faces (never into the
# face), and one longer drip down the frame's right end.
ZT = ZC + FH / 2
balls = []
for i in range(23):
    x = -FW / 2 + 0.3 + i * (FW - 0.6) / 22
    h = 0.3 + 0.07 * math.sin(i * 1.3) + 0.05 * math.sin(i * 2.9)
    balls.append(Ball((x, 0, ZT + 0.04), (0.6, FD / 2 + 0.24, h)))
for x, ln in ((-3.6, 0.4), (-2.1, 0.32), (-0.6, 0.42), (1.1, 0.3), (2.6, 0.4)):  # bulges hanging over the frame band
    for s in (-1, 1):
        balls.append(Ball((x, s * (FD / 2 + 0.12), ZT - ln * 0.5), (0.34, 0.16, ln * 0.6)))
        balls.append(Ball((x, s * (FD / 2 + 0.16), ZT - ln), 0.22))
# one longer drip down the right end of the frame (a full run down the post read as a green column)
xr = FW / 2 - 0.22
for k in range(9):
    t = k / 8
    balls.append(Ball((xr, -(FD / 2 + 0.06), ZT - 1.5 * t), (0.26, 0.2 * (1 - 0.35 * t) + 0.06, 0.16)))
balls.append(Ball((xr, -(FD / 2 + 0.1), ZT - 1.7), 0.3))
goo = metaball_mesh("SignGoo", balls, resolution=0.15, tris=1100)


def goo_color(co, n):
    c = mix(DEEP, GOO, min(1.0, 0.45 + co.z / ZT * 0.6))
    if n.z > 0.5:
        c = mix(c, HI, (n.z - 0.5) / 0.5 * 0.55)
    return c


parts.append(paint_goo(goo, goo_color))
pb = [Ball((PX + 0.3, -1.2, 0), (1.4, 1.0, 0.24)), Ball((PX - 0.6, -1.9, 0), (0.7, 0.55, 0.2)),
      Ball((PX + 1.2, -0.4, 0), (0.6, 0.6, 0.2))]
puddle = metaball_mesh("SignPuddle", pb, resolution=0.15, tris=240, clamp_z=0.02)
parts.append(paint_goo(puddle, lambda co, n: mix(GOO, HI, 0.25 * max(0.0, n.z) ** 4)))

finish("obby_goo_sign", parts)
