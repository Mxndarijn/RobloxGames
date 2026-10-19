# pvp_fun_bubbles: Bubble Wand (PvP fun item), held upright: a lilac soap bottle as the handle,
# the wand stick rising out of its butter cap into a pink ring with a soap film and a bubble.
import math
from models._pvp_fun import *

GRIP = (0, 0, 0.55)
LIL_D = mix(LILAC, RED_D, 0.08)
FILM = mix(SKY, WHITE, 0.55)


def bottle():
    prof = [(0.0, 0.0), (0.34, 0.0), (0.4, 0.06), (0.42, 0.2), (0.42, 0.34), (0.43, 0.36), (0.43, 0.74),
            (0.42, 0.76), (0.42, 0.88), (0.36, 1.0), (0.22, 1.08), (0.26, 1.1), (0.26, 1.34), (0.0, 1.36)]

    def col(i, k, c):
        if c.z > 1.07:
            return BUTTER
        if 0.35 < c.z < 0.75:
            return CREAM if k % 4 else PINK
        return mix(LIL_D, LILAC, min(1, c.z / 0.9))
    return lathe("Bottle", prof, col, segs=16)


def wand():
    stick = lathe("Stick", [(0.0, 1.3), (0.07, 1.3), (0.07, 2.36), (0.0, 2.38)], PINK, segs=8)
    ring = torus("Ring", 0.44, 0.08, lambda i, k, c: PINK if k % 2 else mix(PINK, BUTTER, 0.5), segs=20, rsegs=6,
                 M=place((0, 0, 2.82), (90, 0, 0)))
    film = ico("Film", 0.42, FILM, subdiv=2, M=place((0, 0, 2.82)), squash=(1, 0.08, 1))
    bubble = ico("Bubble", 0.26, mix(SKY, WHITE, 0.35), subdiv=2, M=place((0.5, -0.05, 3.26)))
    bub2 = ico("Bubble2", 0.15, mix(LILAC, WHITE, 0.4), subdiv=1, M=place((0.14, 0.0, 3.36)))
    return [stick, ring, film, bubble, bub2]


ship("pvp_fun_bubbles", [bottle()] + wand(), GRIP)
