# Mystery Egg, epic tier: rich gold shell (darker below, bright above), raised waist band with
# diamond studs, and star studs round the upper shell.
# Shell + band + decal recipe in models/_mystery_egg.py (shared silhouette: 2.2 tall, 1.7 wide).
import math
from mathutils import Vector
from lib import *
from models._mystery_egg import *

GOLD_LO = rgb(192, 120, 32)
GOLD_MID = rgb(240, 186, 58)
GOLD_HI = rgb(255, 226, 112)
BAND_LO = rgb(178, 118, 28)
BAND_HI = rgb(228, 174, 56)
STUD_LO = rgb(250, 214, 110)
STUD_HI = rgb(255, 246, 196)


SHINE = rgb(255, 248, 212)
L = Vector((-0.5, -0.75, 0.45)).normalized()  # fake specular toward the front-left-top


def shell_col(s, th, t):
    s = min(1.0, s * 1.1)
    c = mix(GOLD_LO, GOLD_MID, s / 0.5) if s < 0.5 else mix(GOLD_MID, GOLD_HI, (s - 0.5) / 0.5)
    d = normal(t, th).dot(L)
    return mix(c, SHINE, max(0.0, (d - 0.72) / 0.28) ** 1.5 * 0.85)


parts = [shell("Shell", shell_col, per_vertex=True)]

ZC, HW, N = 0.98, 0.13, 30
parts.append(ribbon("Band", [(j * math.tau / N, ZC, HW) for j in range(N)], lift=0.08,
                    section=((-1, 0.05), (-0.5, 1.0), (0.5, 1.0), (1, 0.05)),
                    color_fn=lambda j, i, f: facet_shade(f, BAND_LO, BAND_HI)))


def stud_col(kind, k, f):
    return facet_shade(f, STUD_LO, STUD_HI) if kind == "top" else BAND_LO


# Diamond studs on the band.
ND = 6
for g in range(ND):
    th = (g + 0.5) * math.tau / ND
    parts.append(decal("Dia%d" % g, t_of_z(ZC), th, diamond(0.12, 0.16), lift=0.09, lift_c=0.13,
                       color_fn=stud_col))
# Star studs on the upper shell, offset from the diamonds.
NS = 5
for g in range(NS):
    th = g * math.tau / NS - math.pi / 2
    parts.append(decal("Star%d" % g, t_of_z(1.6), th, star(0.26, inner=0.48), lift=0.03, lift_c=0.09,
                       color_fn=stud_col))

o = ship("mystery_egg_golden", parts)
