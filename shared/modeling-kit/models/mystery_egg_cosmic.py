# Mystery Egg, legendary tier: deep navy/purple galaxy shell (soft swirl in the vertex colours),
# two raised pink swirl ribbons spiralling up the egg, white/pink star studs and dots between them.
# Shell + ribbon + decal recipe in models/_mystery_egg.py (shared silhouette: 2.2 tall, 1.7 wide).
import math
from lib import *
from models._mystery_egg import *

NAVY = rgb(58, 56, 152)
PURPLE = rgb(112, 66, 192)
MAGENTA = rgb(178, 80, 214)
SWIRL_LO = rgb(236, 88, 188)
SWIRL_HI = rgb(255, 214, 242)  # glowing ridge of the comet trail
STAR_LO = rgb(232, 214, 255)
STAR_HI = rgb(255, 250, 255)
DOT = rgb(255, 150, 222)

Z0, Z1 = 0.4, 1.85        # swirl runs from Z0 to Z1
TURN = 0.85 * math.tau    # how far it winds over that height
TH0 = -math.pi / 2        # first ribbon starts at the front


def swirl_th(z, k):
    return TH0 + k * math.pi + TURN * (z - Z0) / (Z1 - Z0)


def shell_col(s, th, t):
    # dark navy below, purple above, with a soft magenta swirl following the ribbons
    base = mix(NAVY, PURPLE, min(1.0, s * 1.1) ** 2.2)
    z = s * H
    w = 0.5 + 0.5 * math.cos(2 * (th - swirl_th(z, 0)) + math.pi)  # 1 midway between ribbons
    return mix(base, MAGENTA, 0.75 * w ** 2 * math.sin(math.pi * min(1.0, max(0.0, s))))


parts = [shell("Shell", shell_col, per_vertex=True)]

NS = 16
for k in range(2):
    samples = []
    for j in range(NS):
        u = j / (NS - 1)
        z = Z0 + u * (Z1 - Z0)
        samples.append((swirl_th(z, k), z, 0.025 + 0.11 * math.sin(math.pi * u) ** 0.7))
    parts.append(ribbon("Swirl%d" % k, samples, closed=False, lift=0.07,
                        color_fn=lambda j, i, f: SWIRL_HI if i == 1 else SWIRL_LO))


def star_col(kind, k, f):
    return facet_shade(f, STAR_LO, STAR_HI) if kind == "top" else SWIRL_LO


# Stars and dots in the gaps between the two ribbons (a quarter turn off each).
for i, (z, k, big) in enumerate([(0.75, 0, True), (1.15, 1, True), (1.55, 0, True), (1.0, 0, False),
                                  (0.95, 1, False), (1.45, 1, False), (1.9, 0, False), (0.55, 1, False),
                                  (0.6, 1, True), (1.75, 1, True)]):
    th = swirl_th(z, k) + math.pi / 2 + (0.0 if big else 0.35)
    t = t_of_z(z)
    if big:
        parts.append(decal("Star%d" % i, t, th, star(0.24, inner=0.45), lift=0.03, lift_c=0.08, color_fn=star_col))
    else:
        parts.append(decal("Dot%d" % i, t, th, circle(0.12, n=5), lift=0.025, lift_c=0.03,
                           color=DOT if i % 2 else STAR_HI))

o = ship("mystery_egg_cosmic", parts)
