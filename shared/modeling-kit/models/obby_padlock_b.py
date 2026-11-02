# obby_padlock_b (option B): a round "vault dial" padlock for the Key Run gates (steal-a-slime obby).
# A fat round puck body through the gate (bevelled rim), on each face a raised dial ring with six bolts round a big
# keyhole; a thick round-bar U shackle on each face. Open = the shackle lifts and swings out round its long leg
# (the short leg tips out to the side), the classic "unlocked" icon pose. Old size 2.2 x 3.0 x 1.7.
# See models/_obby_padlock_parts.py for the pieces / preview switch.
import math
from lib import *
from models._obby_padlock_parts import *
from models._obby_cannon_parts import lathe, band

R = 1.1  # body radius (2.2 wide like the old body)
ZB = R  # body centre
RC, BAR = 0.66, 0.2
SY = 0.63  # each face's shackle plane: a 0.2 bar stays inside the body face (0.85), its inner edge in the gate
TOP_AT_LEG = ZB + math.sqrt(R * R - RC * RC)  # body surface over each leg
ZC = TOP_AT_LEG + 0.12  # arch centre, shut
LIFT, SWING = 0.35, -24.0  # open: up, then round the long (left) leg (negative = the right side rises)
ROT_Y = (-90, 0, 0)  # lathe axis (+Z) -> +Y, through the gate


def build(tb, ts):
    h = DEPTH / 2
    prof = [(0.0, -h), (R - 0.22, -h), (R - 0.04, -h + 0.08), (R, -h + 0.24), (R, h - 0.24), (R - 0.04, h - 0.08),
            (R - 0.22, h), (0.0, h)]
    body = lathe("Body", prof, tc(0.7, tb), segs=28, pos=(0, 0, ZB), rot=ROT_Y)
    gradient(body, tc(0.58, tb), tc(0.86, tb))
    parts = [body]
    for s in (-1, 1):
        y = s * h
        rot = ROT_Y if s > 0 else (90, 0, 0)  # each ring's +Z points out of its own face
        ring = band(f"Dial{s}", 0.62, 0.9, -0.06, 0.08, tc(1.0, tb), tc(0.88, tb), segs=28, pos=(0, y, ZB), rot=rot)
        parts.append(ring)
        parts += keyhole(f"Key{s}", y, ZB + 0.12, 0.27, 0.24, 0.42, tc(0.16, tb))
        for k in range(6):
            a = math.radians(90 + 30 + k * 60)
            parts.append(blob(f"Bolt{s}{k}", 0.09, (0.76 * math.cos(a), y + s * 0.08, ZB + 0.76 * math.sin(a)),
                              tc(0.62, tb), subdiv=1, squash=(1, 0.6, 1), jitter=0))
    sh = [shackle_u(f"Shackle{s}", RC, BAR, ZC, s * SY, 1.05, 0.42, tc(0.78, ts), tc(1.0, ts)) for s in (-1, 1)]
    return parts, sh


def open_pose(sh):
    place(sh, dz=LIFT, rot_y=SWING, pivot=(-RC, TOP_AT_LEG))


assemble("obby_padlock_b", build, open_pose)
