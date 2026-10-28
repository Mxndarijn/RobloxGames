# bat_skin_fish: Fish Bat skin (Exclusive Shop, contract §10): a floppy cartoon fish held by the tail, head up.
# The forked tail fin is the pommel, the narrow tail stem is the grip, the fat orange body is the barrel.
# The fish is flat in Y, so its side (big eyes, pouty pink lips at the top) faces the kit front and back,
# and from behind the player. Back fin on +X and belly fin on -X reach the same width (bbox centred).
# Frame = ranch_bat (models/_bat_skin.py): z 0..5.09, grip z = 1.2.
import math
from models._bat_skin import *

ORANGE = mix(BUTTER, RED, 0.36)
ORANGE_D = mix(ORANGE, RED, 0.2)
BELLY = mix(BUTTER, CREAM, 0.35)
FIN, FIN_LO = mix(RED, PINK, 0.45), mix(RED, PINK, 0.1)
EYE_W, PUPIL = WHITE, rgb(92, 72, 112)  # plum pupil (THEME: no near-black)
LIP = PINK
FLAT = 0.56  # body thickness (Y) / width (X)
TOP = 4.97  # body tip; the lips reach HEIGHT


def body_col(i, k, c):
    side = c.x / max(0.05, math.hypot(c.x, c.y / FLAT))  # +1 back (+X) .. -1 belly (-X)
    base = mix(BELLY, ORANGE, 0.5 + 0.5 * side) if side < 0 else mix(ORANGE, ORANGE_D, side * 0.6)
    t = min(1.0, max(0.0, (c.z - 1.6) / 3.2))
    base = mix(mix(base, ORANGE_D, 0.18), base, t)
    scale = (int(c.z * 4.2) + k) % 2 == 0 and 1.9 < c.z < 4.0
    return mix(base, ORANGE_D, 0.22) if scale else base


def body():
    prof = [(0.27, 1.75), (0.38, 2.05), (0.56, 2.5), (0.7, 3.0), (0.74, 3.45), (0.7, 3.9), (0.6, 4.3),
            (0.44, 4.65), (0.24, 4.88), (0.0, TOP)]
    return lathe("Body", prof, body_col, segs=16, smooth=True, ry=FLAT)


def stem():
    prof = [(0.0, 0.55), (0.25, 0.55), (0.27, 0.8), (0.27, 1.8), (0.3, 1.9), (0.0, 2.0)]
    return lathe("Stem", prof, lambda i, k, c: mix(ORANGE_D, ORANGE, 0.4) if (k + int(c.z * 5)) % 3 else ORANGE_D,
                 segs=10)


def fin_col(lo_z, hi_z):
    def col(i, k, c):
        return mix(FIN_LO, FIN, min(1, max(0, (c.z - lo_z) / (hi_z - lo_z))))
    return col


def fins():
    tail = slab("Tail", [(0.0, 0.32), (0.74, -0.02), (0.6, 0.42), (0.26, 0.82), (-0.26, 0.82), (-0.6, 0.42),
                         (-0.74, -0.02)], 0.22, fin_col(0.0, 0.8), bevel_w=0.05)
    back = slab("Back", [(0.5, 2.5), (0.95, 2.75), (1.0, 3.25), (0.88, 3.7), (0.62, 3.95)], 0.16,
                fin_col(2.5, 3.9), bevel_w=0.04)
    belly = slab("Belly", [(-0.62, 3.6), (-0.95, 3.3), (-1.0, 2.8), (-0.85, 2.4), (-0.5, 2.3)], 0.16,
                 fin_col(2.3, 3.6), bevel_w=0.04)
    out = [tail, back, belly]
    for s in (-1, 1):  # side (pectoral) fins, angled back
        out.append(ico("Pec%d" % s, 0.26, FIN, subdiv=1, M=place((-0.18, s * 0.34, 3.55), (0, -30, 0)),
                       squash=(0.5, 0.35, 1.0)))
    return out


def face():
    out = []
    for s in (-1, 1):
        y = s * 0.3
        out.append(ico("Eye%d" % s, 0.3, EYE_W, subdiv=1, M=place((0.12, y, 4.2)), squash=(1.0, 0.5, 1.05)))
        out.append(ico("Pupil%d" % s, 0.16, PUPIL, subdiv=1, M=place((0.17, y + s * 0.12, 4.22)),
                       squash=(1.0, 0.5, 1.1)))
        out.append(ico("Glint%d" % s, 0.055, EYE_W, subdiv=1, M=place((0.23, y + s * 0.19, 4.3))))
    lip_r = 0.2
    out.append(ico("Lips", lip_r, LIP, subdiv=1, M=place((0, 0, HEIGHT - lip_r * 0.7)), squash=(1.0, 0.75, 0.7)))
    return out


parts = [body(), stem()] + fins() + face()
ship_skin("bat_skin_fish", parts)
