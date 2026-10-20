# pvp_fun_fireworks: Goo Fireworks (PvP fun item): a handheld rocket launcher tube, muzzle to -Y (front),
# pistol grip underneath, with two coloured rockets (pink, goo) poking out of the muzzle side by side.
import math
from models._pvp_fun import *

GRIP = (0, 0.4, 0.45)
SKY_D = SKY
Y0 = 1.0


def tube():
    prof = [(0.0, 0.0), (0.4, 0.0), (0.5, 0.06), (0.5, 0.2), (0.44, 0.24),  # rear flare
            (0.44, 1.86), (0.52, 1.9), (0.52, 2.06), (0.46, 2.08), (0.46, 1.96), (0.0, 1.96)]

    def col(i, k, c):
        z = Y0 - c.y
        if z < 0.22 or z > 1.88:
            return RED
        a = (math.atan2(c.z - 1.05, c.x) / math.tau) % 1.0
        if int(a * 6 + z * 1.5) % 3 == 0:
            return BUTTER
        return mix(SKY_D, mix(SKY, WHITE, 0.3), min(1, max(0, (c.z - 0.6) / 0.9)))
    return lathe("Tube", prof, col, segs=16, M=place((0, Y0, 1.05), (90, 0, 0)))


def rocket(x, body_col, tip_col):
    # local z along the flight direction (-Y); base hidden in the tube
    prof = [(0.0, 0.0), (0.18, 0.0), (0.18, 0.62), (0.18, 0.72), (0.18, 0.82), (0.21, 0.84), (0.21, 0.92),
            (0.2, 1.0), (0.17, 1.08), (0.11, 1.15), (0.0, 1.18)]

    def col(i, k, c):
        if i in (3,):
            return WHITE
        if i in (5, 6):
            return BUTTER
        return body_col if i <= 4 else tip_col
    return lathe("Rocket", prof, col, segs=10, M=place((x, -0.5, 1.05), (90, 0, 0)))


def fuse():
    pts = [(0, 0.98, 1.05), (0.0, 1.12, 1.08), (0.08, 1.22, 1.2), (0.0, 1.3, 1.32)]
    f = sweep("Fuse", pts, [0.05] * len(pts), mix(WOOD, CREAM, 0.3), segs=5)
    spark = ico("Spark", 0.09, BUTTER, subdiv=1, M=place((0.0, 1.32, 1.36)), smooth=False, spikes=1.9)
    return [f, spark]


def sight():
    return box_part("Sight", (0.12, 0.3, 0.16), RED, M=place((0, -0.7, 1.55)), bevel_w=0.03)


def grip():
    prof = [(0.0, 0.0), (0.2, 0.0), (0.22, 0.06), (0.2, 0.7), (0.0, 0.72)]
    return lathe("Grip", prof, lambda i, k, c: mix(WOOD_D, WOOD, min(1, c.z / 0.8)), segs=8, rx=0.8, ry=1.15,
                 M=place((0, 0.4, 0.0), (-12, 0, 0)))


ship("pvp_fun_fireworks", [tube(), grip(), sight(), rocket(-0.2, PINK, RED), rocket(0.2, GOO, LILAC)] + fuse(), GRIP)
