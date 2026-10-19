# pvp_fun_hat_launcher: Slime Hat Launcher (PvP fun item): a little party cannon, muzzle to -Y (front),
# pistol grip underneath, with a goo slime squeezing out of the muzzle wearing a red top hat (the "slime hat").
import math
from models._pvp_fun import *

GRIP = (0, 0.5, 0.45)
LIL_D = mix(LILAC, RED_D, 0.08)
GOO_D = mix(GOO, P["ranch_field_dark"], 0.2)
Y0 = 1.0  # barrel rear (y)


def barrel():
    prof = [(0.0, 0.0), (0.26, 0.0), (0.38, 0.08), (0.42, 0.22),
            (0.46, 0.24), (0.46, 0.38), (0.42, 0.4),      # rear band
            (0.42, 1.25), (0.46, 1.27), (0.46, 1.41), (0.42, 1.43),  # mid band
            (0.44, 1.8), (0.56, 1.9), (0.58, 2.08), (0.46, 2.1), (0.46, 1.95), (0.0, 1.95)]

    def col(i, k, c):
        z = Y0 - c.y
        if (0.22 < z < 0.4) or (1.25 < z < 1.43) or z > 1.86:
            return BUTTER
        return mix(LIL_D, mix(LILAC, WHITE, 0.15), 0.35 + 0.65 * min(1, max(0, (c.z - 0.6) / 0.9)))
    return lathe("Barrel", prof, col, segs=16, M=place((0, Y0, 1.05), (90, 0, 0)))


def grip():
    prof = [(0.0, 0.0), (0.2, 0.0), (0.22, 0.06), (0.2, 0.7), (0.0, 0.72)]
    return lathe("Grip", prof, lambda i, k, c: mix(WOOD_D, WOOD, min(1, c.z / 0.8)), segs=8, rx=0.8, ry=1.15,
                 M=place((0, 0.5, 0.0), (-12, 0, 0)))


EYE = rgb(92, 72, 112)  # deep plum, not black (THEME: no near-black)


def slime():
    """A goo slime squeezing out of the muzzle, wearing the hat it is about to fire."""
    body = ico("Slime", 0.42, lambda i, k, c: mix(GOO_D, GOO, min(1, max(0, (c.z - 0.75) / 0.6))), subdiv=2,
               M=place((0, -1.32, 1.08)), squash=(1.05, 1.0, 0.92))
    eyes = [ico("Eye%d" % s, 0.065, EYE, subdiv=1, M=place((s * 0.15, -1.7, 1.16)), squash=(1, 0.6, 1.3))
            for s in (-1, 1)]
    return [body] + eyes


def hat():
    # local z = hat up, sitting on the slime's head, tipped back a little
    M = place((0, -1.26, 1.42), (-14, 0, 0))
    crown = lathe("HatCrown", [(0.0, 0.0), (0.22, 0.0), (0.23, 0.1), (0.23, 0.17), (0.22, 0.19), (0.21, 0.44), (0.0, 0.46)],
                  lambda i, k, c: BUTTER if i in (2, 3) else (RED if i < 5 else mix(RED, PINK, 0.4)), segs=14, M=M)
    brim = lathe("HatBrim", [(0.0, -0.03), (0.38, -0.03), (0.4, 0.0), (0.38, 0.03), (0.0, 0.03)],
                 RED_D, segs=14, M=M)
    return [crown, brim]


ship("pvp_fun_hat_launcher", [barrel(), grip()] + slime() + hat(), GRIP)
