# pvp_fun_bounce_pad: Bounce Pad (PvP fun item): a mini trampoline, carried like a frisbee and
# placed on the ground, so it is modelled lying flat on z=0, 3 studs across.
# Butter base plate on the ground, 8 fat coil springs, a padded pink/butter rim and a goo bed with up-chevrons.
import math
from models._pvp_fun import *

R = 1.48
ZT = 0.74  # rim height
GRIP = (R - 0.18, 0, ZT)  # centre of the rim tube on +X, held like a frisbee
BASE = mix(WOOD, BUTTER, 0.35)


def base():
    prof = [(0.0, 0.0), (R - 0.12, 0.0), (R - 0.04, 0.05), (R - 0.04, 0.12), (R - 0.12, 0.17), (0.0, 0.17)]
    return lathe("Base", prof, lambda i, k, c: mix(BASE, WOOD_D, 0.3) if c.z < 0.1 else BASE, segs=24, smooth=False)


def springs():
    out = []
    for j in range(8):
        a = j * math.tau / 8 + math.tau / 16
        prof = [(0.0, 0.14)]
        n = 6
        for s in range(n + 1):
            prof.append((0.17 if s % 2 else 0.11, 0.16 + s * (ZT - 0.3) / n))
        prof.append((0.0, ZT - 0.1))
        out.append(lathe("Spring%d" % j, prof, lambda i, k, c: mix(METAL, WHITE, 0.25 if i % 2 else 0.0), segs=6,
                         smooth=False, M=place(((R - 0.3) * math.cos(a), (R - 0.3) * math.sin(a), 0))))
    return out


def rim():
    return torus("Rim", R - 0.18, 0.2, lambda i, k, c: PINK if (k // 2) % 2 else BUTTER, segs=24, rsegs=6,
                 M=place((0, 0, ZT)))


def bed():
    prof = [(0.0, ZT - 0.16), (R - 0.3, ZT - 0.16), (R - 0.3, ZT - 0.02), (0.0, ZT - 0.04)]
    return lathe("Bed", prof, lambda i, k, c: mix(GOO, P["ranch_field_dark"], 0.3) if c.z < ZT - 0.1 else GOO,
                 segs=24, smooth=False)


def chevrons():
    out = []
    for j, y in enumerate((0.32, -0.12)):
        for s in (-1, 1):
            out.append(box_part("Chev%d%d" % (j, s), (0.62, 0.2, 0.06), BUTTER,
                                M=place((s * 0.2, y - 0.2, ZT - 0.02), (0, 0, s * 42)), bevel_w=0.025))
    return out


ship("pvp_fun_bounce_pad", [base(), rim(), bed()] + springs() + chevrons(), GRIP)
