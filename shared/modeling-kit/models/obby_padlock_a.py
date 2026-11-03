# obby_padlock_a (option A): a chunky classic padlock for the Key Run gates (steal-a-slime obby).
# A soft rounded-box body through the gate with a lighter rounded cap band on top where the shackle goes in, two
# rivets and a big keyhole on each face; a round-bar U shackle on each face with one long and one short leg. Open =
# the shackle pops straight up 0.65 (as today), so the short leg comes out of the cap and the gap reads as open.
# Old size 2.2 x 3.0 x 1.7; pieces: body (value-only, tinted SHUT_BODY / GOLD) and shackle (STEEL / GOLD).
# See models/_obby_padlock_parts.py for the pieces / preview switch.
from lib import *
from models._obby_padlock_parts import *

W, H = 2.2, 1.8
RC, BAR = 0.7, 0.17
ZC = H + 0.35  # arch centre, shut (old MARK.shackleShut over the body top)
LIFT = 0.65  # old shackleOpen - shackleShut


def build(tb, ts):
    body = [rbox("Body", (W, DEPTH, H), (0, 0, H / 2), tc(0.62, tb), tc(0.80, tb), bev=0.3)]
    body.append(rbox("Cap", (W + 0.08, DEPTH + 0.08, 0.36), (0, 0, H - 0.26), tc(0.95, tb), tc(1.0, tb), bev=0.12))
    for s in (-1, 1):
        y = s * DEPTH / 2
        body += keyhole(f"Key{s}", y, 0.74, 0.3, 0.26, 0.46, tc(0.16, tb))
        for x in (-0.72, 0.72):
            body.append(blob(f"Rivet{s}{x}", 0.11, (x, y, 1.12), tc(1.0, tb), subdiv=1, squash=(1, 0.5, 1), jitter=0))
    sh = [shackle_u(f"Shackle{s}", RC, BAR, ZC, s * FACE_Y, 1.3, 0.55, tc(0.78, ts), tc(1.0, ts)) for s in (-1, 1)]
    return body, sh


def open_pose(sh):
    place(sh, dz=LIFT)


assemble("obby_padlock_a", build, open_pose)
