# bat_skin_lollipop: Lollipop Bat skin (Exclusive Shop, contract §10): a giant swirly lollipop on a stick.
# Cream candy stick with a round pommel bead and a pink ribbon grip, a butter bow under the candy, and a fat
# round swirl disc (pink / cream / lilac / butter spiral, LESSONS habitat_candy_patch) facing front and back.
# Frame = ranch_bat (models/_bat_skin.py): z 0..5.09, grip z = 1.2.
import math
from models._bat_skin import *

STICK, STICK_LO = mix(CREAM, WOOD, 0.12), mix(CREAM, WOOD, 0.35)
PINK_LO = mix(PINK, RED, 0.35)
CANDY = [mix(PINK, RED, 0.25), CREAM, mix(LILAC, PINK, 0.15), BUTTER]
DISC_R, DISC_T = 1.05, 0.46  # swirl radius, thickness (Y)
DISC_Z = HEIGHT - DISC_R


def stick():
    prof = [(0.0, 0.0), (0.26, 0.0), (0.36, 0.12), (0.38, 0.3), (0.3, 0.52),  # pommel bead
            (0.27, 0.62), (0.27, 0.8), (0.29, 0.86), (0.29, 1.74), (0.27, 1.8),  # ribbon grip
            (0.22, 1.86), (0.22, DISC_Z), (0.0, DISC_Z + 0.1)]

    def col(i, k, c):
        if 0.82 < c.z < 1.78:
            return PINK if (k + int(c.z * 6)) % 4 < 2 else PINK_LO  # spiral ribbon wrap
        if c.z < 0.6:
            return mix(PINK_LO, PINK, c.z / 0.6)
        return mix(STICK_LO, STICK, min(1, (c.z - 1.8) / 1.5))
    return lathe("Stick", prof, col, segs=8)


def disc():
    # lens profile along local z (the disc's thickness axis), turned to face -Y
    h = DISC_T / 2
    face = [(0.16, 0.8), (0.32, 0.84), (0.48, 0.89), (0.64, 0.94), (0.8, 1.0), (0.94, 0.85)]
    back = [(r, h * f) for r, f in reversed(face)]
    prof = [(0.0, -h * 0.78)] + [(r, -h * f) for r, f in face] + [(DISC_R, 0.0)] + back + [(0.0, h * 0.78)]
    segs = 22

    def col(i, k, c):
        r = math.hypot(c.x, c.z - DISC_Z)
        a = math.atan2(c.z - DISC_Z, c.x * (1 if c.y < 0 else -1))
        band = int((a / math.tau * 4 + r * 4.2) % 4)  # 4-arm spiral, mirrored on the back so it swirls the same way
        base = CANDY[band]
        return mix(base, CREAM, 0.25) if r > DISC_R * 0.93 else base
    return lathe("Candy", prof, col, segs=segs, smooth=True, phase=math.pi / 2, M=place((0, 0, DISC_Z), (90, 0, 0)))


def bow():
    knot = ico("Knot", 0.2, BUTTER, subdiv=1, M=place((0, 0, DISC_Z - DISC_R + 0.05)), squash=(1.0, 0.8, 0.9))
    loops = []
    for s in (-1, 1):
        z = DISC_Z - DISC_R + 0.08
        loops.append(ico("Loop%d" % s, 0.3, lambda i, k, c: mix(BUTTER, WOOD, 0.2) if c.z < z - 0.05 else BUTTER,
                         subdiv=1, M=place((s * 0.38, 0, z), (0, s * 25, 0)), squash=(1.3, 0.45, 0.75)))
    return [knot] + loops


parts = [stick(), disc()] + bow()
ship_skin("bat_skin_lollipop", parts)
