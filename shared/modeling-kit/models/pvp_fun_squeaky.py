# pvp_fun_squeaky: Squeaky Hammer, a big soft toy hammer (PvP fun item), held upright like ranch_bat.
# Yellow plastic handle with a red pommel knob, red squishy head with yellow bellows ends.
# Long axis Z, pommel bottom on z=0. Grip: middle of the handle, z = 1.0.
import math
from models._pvp_fun import *

GRIP = (0, 0, 1.0)
YEL, YEL_D = BUTTER, mix(BUTTER, WOOD, 0.15)
RED_LO = mix(RED_D, RED, 0.7)


def handle():
    prof = [(0.0, 0.0), (0.26, 0.0), (0.34, 0.1), (0.35, 0.28), (0.26, 0.42),  # red pommel knob
            (0.23, 0.5), (0.23, 1.9), (0.3, 2.0), (0.0, 2.05)]

    def col(i, k, c):
        if c.z < 0.45:
            return mix(RED_LO, RED, c.z / 0.45)
        return mix(YEL_D, YEL, min(1, (c.z - 0.45) / 1.6))
    return lathe("Handle", prof, col, segs=12)


def head():
    # profile along the head axis (local z = world x), bellows ends
    prof = [(0.0, -1.0), (0.4, -1.0), (0.52, -0.95), (0.58, -0.86), (0.5, -0.79), (0.6, -0.71), (0.54, -0.64),
            (0.64, -0.57), (0.7, -0.44), (0.72, 0.0), (0.7, 0.44), (0.64, 0.57),
            (0.54, 0.64), (0.6, 0.71), (0.5, 0.79), (0.58, 0.86), (0.52, 0.95), (0.4, 1.0), (0.0, 1.0)]

    def col(i, k, c):
        top = (c.z - 1.9) / 1.35
        if abs(c.x) > 0.58:
            return mix(YEL_D, YEL, 0.35 + 0.65 * top)
        return mix(RED_LO, RED, 0.3 + 0.7 * top)
    return lathe("Head", prof, col, segs=16, M=place((0, 0, 2.55), (0, 90, 0)))


ship("pvp_fun_squeaky", [handle(), head()], GRIP)
