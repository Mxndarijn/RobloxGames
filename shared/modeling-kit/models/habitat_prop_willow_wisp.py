# habitat_prop_willow_wisp: a mossy tree stump with roots, glowing teal mushrooms at its foot and on top, and a
# yellow-green firefly hovering over it. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

BARK, BARK_D, BARK_HI = rgb(178, 120, 76), rgb(150, 100, 62), rgb(204, 146, 94)
WOOD, RING = rgb(236, 200, 140), rgb(200, 150, 96)
MOSS, MOSS_HI = rgb(96, 190, 76), rgb(150, 222, 96)
CAP, CAP_HI, STALK = rgb(70, 226, 214), rgb(180, 255, 244), rgb(226, 246, 236)
FLY, FLY_HI, FLY_D, WING = rgb(226, 255, 90), rgb(250, 255, 190), rgb(90, 80, 70), rgb(214, 238, 255)
SX, SY, SH, SR = 0.0, 0.12, 0.6, 0.36
parts = []
stump = lathe("Stump", [(0, 0), (SR + 0.12, 0), (SR + 0.04, 0.08), (SR, 0.2), (SR - 0.01, SH - 0.04), (SR - 0.04, SH),
                        (0, SH)], segs=12, pos=(SX, SY, 0))


def stump_col(c, n):
    r = math.hypot(c.x - SX, c.y - SY)
    if n.z > 0.8:
        return RING if int(r / 0.08) % 2 else WOOD
    return BARK_D if int((math.atan2(c.y - SY, c.x - SX) + math.pi) / (math.tau / 12)) % 2 else BARK


paint(stump, stump_col)
parts.append(stump)
for k, a in enumerate((-60, 40, 150, 230)):  # roots
    ar = math.radians(a)
    d = lambda t: (SX + math.cos(ar) * t, SY + math.sin(ar) * t)
    parts.append(tube(f"Root{k}", [(*d(SR - 0.05), 0.2), (*d(SR + 0.12), 0.07), (*d(SR + 0.26), 0.02)], [0.09, 0.06, 0.03],
                      BARK_HI if k % 2 else BARK, segs=6))
# moss: draped over the back-left rim and a patch on the front
for k, (a, z, r) in enumerate(((120, SH - 0.02, 0.15), (170, SH - 0.06, 0.12), (-110, 0.18, 0.11), (60, SH - 0.03, 0.1))):
    ar = math.radians(a)
    m = blob(f"Moss{k}", r, (SX + math.cos(ar) * (SR - 0.02), SY + math.sin(ar) * (SR - 0.02), z), MOSS, subdiv=2,
             squash=(1.2, 1.2, 0.55), jitter=0.12, seed=k)
    paint(m, lambda c, n: MOSS_HI if n.z > 0.5 else MOSS)
    parts.append(m)


def shroom(i, x, y, z, h, r, lean=(0, 0)):
    st = lathe(f"St{i}", [(r * 0.35, 0), (r * 0.28, h), (0, h)], segs=6, color=STALK)
    cap = lathe(f"Cap{i}", [(0, h - 0.01), (r, h - 0.01), (r * 0.85, h + r * 0.4), (r * 0.4, h + r * 0.7), (0, h + r * 0.75)],
                segs=10)
    paint(cap, lambda c, n: CAP if c.z < h + r * 0.25 else CAP_HI)
    for o in (st, cap):
        move(o, (x, y, z), (lean[0], lean[1], 0))
    return [st, cap]


parts += shroom(0, 0.42, -0.24, 0.0, 0.22, 0.17, (8, 10))
parts += shroom(1, 0.62, -0.08, 0.0, 0.14, 0.12, (0, 18))
parts += shroom(2, 0.26, -0.36, 0.0, 0.1, 0.09, (10, -6))
parts += shroom(3, -0.12, 0.04, SH, 0.13, 0.12, (6, -10))
parts += shroom(4, -0.5, -0.2, 0.0, 0.12, 0.1, (6, -16))
# firefly hovering front-left above the stump: glowing tail, dark head, two pale wings
FX, FY, FZ = -0.34, -0.14, 1.06
parts.append(blob("Tail", 0.11, (FX + 0.02, FY, FZ - 0.04), FLY, subdiv=2, squash=(1.2, 1, 0.9), jitter=0))
parts.append(blob("TailHi", 0.065, (FX + 0.03, FY - 0.05, FZ - 0.02), FLY_HI, subdiv=1, jitter=0))
parts.append(blob("Head", 0.05, (FX - 0.1, FY, FZ + 0.03), FLY_D, subdiv=1, jitter=0))
for s in (-1, 1):
    wing = slab(f"Wing{s}", [(0, 0), (0.14, 0.03), (0.16, 0.09), (0.06, 0.07)], 0.015, color=WING)
    move(wing, rot=(0, 0, 90 + s * 25))
    move(wing, (FX - 0.04, FY + s * 0.01, FZ + 0.07), (0, s * -20, 0))
    parts.append(wing)
prop_finish("habitat_prop_willow_wisp", parts)
