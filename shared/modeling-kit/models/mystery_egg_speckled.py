# Mystery Egg, common tier: warm cream shell with brown-orange speckle spots.
# Shell + spot recipe in models/_mystery_egg.py (shared silhouette: 2.2 tall, 1.7 wide).
import math
from lib import *
from models._mystery_egg import *

SHELL_LO = rgb(226, 196, 148)
SHELL_HI = rgb(250, 234, 200)
SPOT_LO = rgb(176, 96, 50)
SPOT_HI = rgb(212, 124, 62)


def shell_col(s, th, t):
    return mix(SHELL_LO, SHELL_HI, min(1.0, s * 1.15))


parts = [shell("Shell", shell_col)]

# Golden-angle scatter of spots over the middle of the egg, bigger round the waist.
r = rng(7)
n = 18
for i in range(n):
    f = (i + 0.5) / n
    z = 0.3 + f * (H - 0.48)
    th = i * 2.39996 + 0.3
    t = t_of_z(z)
    # big / small alternation so it reads as speckles, not a giraffe pattern; smaller near the tip
    big = (i % 3 != 1)
    rad = (0.11 + 0.11 * math.sin(math.pi * min(f, 0.85))) * (1.0 if big else 0.6) + r.random() * 0.04
    c = mix(SPOT_LO, SPOT_HI, f)
    parts.append(decal("Spot%02d" % i, t, th, circle(rad, n=8, wobble=0.18, seed=i, sx=1.15, sy=0.9),
                       lift=0.015, lift_c=0.03, color=c, spin=r.random() * 3.0))

o = ship("mystery_egg_speckled", parts)
