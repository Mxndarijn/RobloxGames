# obby_key_b (option B): the slime key (steal-a-slime obby, Key Run).
# The bow is a little goo slime with big eyes, sitting in a gold cup on top of a gold shaft and two-tooth bit; a goo
# drip runs from the slime over the cup. The game's own mascot on a key: it says "Steal a Slime" from across the lane.
# Upright, the slime's face to -Y. Fits the old 1.5-stud key box (height ~1.6).
import math
from mathutils import Vector
from lib import *
from lib.goo import Ball, metaball_mesh
from models._obby_key_parts import *

parts = []
CUP_Z = 0.96          # top of the gold collar the slime sits on
SY = 0.78             # the slime's depth squash (front to back)

# -- the gold blade and the cup
parts += blade(CUP_Z - 0.1)
parts.append(paint(torus_xz("Collar0", 0.16, 0.07, (0, 0, CUP_Z - 0.2), segs=14, sides=6, rot=(90, 0, 0)), metal))
plate = [(0, CUP_Z - 0.1), (0.22, CUP_Z - 0.1), (0.3, CUP_Z - 0.05), (0.32, CUP_Z), (0.28, CUP_Z + 0.04), (0, CUP_Z + 0.04)]
parts.append(paint(lathe("Plate", plate, GOLD, segs=16), metal))

# -- the slime: a gumdrop lathe squashed front to back
Z0 = CUP_Z - 0.02
body = [(0, Z0), (0.36, Z0 + 0.0), (0.46, Z0 + 0.07), (0.48, Z0 + 0.17), (0.43, Z0 + 0.33), (0.3, Z0 + 0.5),
        (0.13, Z0 + 0.6), (0, Z0 + 0.62)]


def goo_col(co, n):
    t = min(1.0, max(0.0, (co.z - Z0) / 0.6))
    c = mix(GOO_DEEP, GOO, 0.62 + 0.38 * t)  # low end stays near GOO: the shadow side goes teal-black otherwise
    d = n.dot(LIGHT)
    if d > 0.62:
        c = mix(c, GOO_HI, min(1.0, (d - 0.62) / 0.2))
    return c


slime = lathe("Slime", body, GOO, segs=20)
squash(slime, (1, SY, 1))
parts.append(paint(slime, goo_col))


def front_y(x, z):
    r = prof_r(body, z)
    return -math.sqrt(max(r * r - x * x, 0.0)) * SY


# -- eyes: white ovals sunk into the front, dark pupils just proud, a white glint
EZ = Z0 + 0.3
for s in (-1, 1):
    x = s * 0.16
    y = front_y(x, EZ)
    parts.append(paint(blob(f"EyeW{s}", 0.11, (x, y + 0.03, EZ), subdiv=2, jitter=0, squash=(0.85, 0.5, 1.1)),
                       lambda co, n: WHITE))
    parts.append(paint(blob(f"EyeP{s}", 0.07, (x + s * 0.01, y - 0.015, EZ - 0.015), subdiv=2, jitter=0,
                            squash=(0.85, 0.45, 1.05)), lambda co, n: INK))
    parts.append(paint(blob(f"EyeG{s}", 0.025, (x - 0.02, y - 0.05, EZ + 0.03), subdiv=1, jitter=0), lambda co, n: WHITE))

# -- a small smile under the eyes
pts = []
for k in range(5):
    a = math.radians(-50 + k * 25)
    x, z = math.sin(a) * 0.09, EZ - 0.14 - math.cos(a) * 0.04 + 0.04
    pts.append((x, front_y(x, z) + 0.005, z))
parts.append(paint(tube("Smile", pts, [0.016, 0.022, 0.024, 0.022, 0.016], segs=6), lambda co, n: INK))

# -- a short goo drip off the slime's lower left edge (to the side, never between the eyes)
balls = []
x0, z0 = -0.36, Z0 + 0.04
y0 = front_y(x0, z0) + 0.06
for k in range(5):
    t = k / 4
    balls.append(Ball((x0 + 0.02 * t, y0, z0 - 0.18 * t), 0.075 * (1 - 0.45 * t) + 0.02))
balls.append(Ball((x0 + 0.02, y0, z0 - 0.25), 0.07))
drip = metaball_mesh("SlimeDrip", balls, resolution=0.025, tris=200)
parts.append(paint(drip, goo_col))

finish_smooth("obby_key_b", parts)
