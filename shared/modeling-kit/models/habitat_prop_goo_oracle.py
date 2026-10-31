# habitat_prop_goo_oracle: a glowing crystal ball on a little gold-and-purple claw stand.
import math
from models._habitat_prop3 import *

VIO, VIO_LO = rgb(150, 88, 220), rgb(104, 58, 176)
BALL_LO, BALL_HI = rgb(110, 200, 255), rgb(226, 246, 255)
parts = []
# stand: round purple base, gold collar, short neck, cup
base = lathe("Base", [(0, 0), (0.5, 0.0), (0.52, 0.08), (0.44, 0.18), (0.3, 0.24), (0.14, 0.3), (0, 0.3)], segs=12,
             color_fn=lambda i, k, z: GOLD if i == 1 else (VIO_LO if i == 0 else VIO))
parts.append(base)
parts.append(lathe("Neck", [(0, 0.28), (0.12, 0.28), (0.09, 0.42), (0.2, 0.5), (0.28, 0.56), (0, 0.56)], segs=10,
                   color_fn=lambda i, k, z: GOLD_LO if i < 2 else GOLD))
# three gold claws curling up round the ball
for i in range(3):
    a = math.tau * i / 3 + math.pi / 2
    pts = [(math.cos(a) * r, math.sin(a) * r, z) for r, z in ((0.22, 0.5), (0.36, 0.64), (0.38, 0.8), (0.3, 0.9))]
    parts.append(tube(f"Claw{i}", pts, (0.06, 0.055, 0.045, 0.03), GOLD, segs=5))
# the ball: smooth-ish sphere, light swirl band, big catchlight
prof = [(0.4 * math.sin(math.pi * j / 9), 0.92 - 0.4 * math.cos(math.pi * j / 9)) for j in range(10)]
prof[0], prof[-1] = (0, prof[0][1]), (0, prof[-1][1])
SW = rgb(214, 160, 255)
def ball_col(i, k, z):
    t = (z - 0.52) / 0.8
    c = mix(rgb(186, 120, 255), BALL_LO, min(1, t * 2.2)) if t < 0.45 else mix(BALL_LO, BALL_HI, min(1, (t - 0.45) * 2.2))
    return shade(c, 1.08) if (k + i) % 5 == 0 and 2 <= i <= 6 else c  # faint sparkle facets


ball = lathe("Ball", prof, segs=16, phase=0.2, color_fn=ball_col)
parts.append(ball)
parts.append(blob("Shine", 0.07, (-0.17, -0.31, 1.12), rgb(255, 255, 255), subdiv=1, jitter=0, squash=(1, 0.5, 1)))
# little gem studs on the base front
for i, a in enumerate((-90, -30, -150)):
    r = math.radians(a)
    parts.append(blob(f"Stud{i}", 0.05, (math.cos(r) * 0.42, math.sin(r) * 0.42, 0.14), rgb(255, 120, 200), subdiv=1, jitter=0))
ship("habitat_prop_goo_oracle", parts)
