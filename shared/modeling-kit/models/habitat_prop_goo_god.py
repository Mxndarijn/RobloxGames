# habitat_prop_goo_god: a small white-and-gold altar with two tiny golden slime statuettes and a glowing orb.
import math
from models._habitat_prop5 import *

WHITE, WHITE_LO = rgb(255, 252, 244), rgb(226, 220, 214)
GOLD, GOLD_LO, GOLD_HI = rgb(255, 204, 64), rgb(246, 168, 44), rgb(255, 238, 150)
EYE = rgb(90, 60, 40)
ORB = rgb(170, 255, 230)
parts = [
    gbox("Step", (1.5, 0.86, 0.14), (0, 0.04, 0.07), WHITE_LO, WHITE, bev=0.03),
    gbox("Body", (1.2, 0.62, 0.26), (0, 0.06, 0.27), WHITE_LO, WHITE, bev=0.03),
    gbox("Band", (1.23, 0.65, 0.06), (0, 0.06, 0.27), GOLD_LO, GOLD, bev=0.01),
    gbox("Top", (1.36, 0.74, 0.08), (0, 0.06, 0.44), GOLD, GOLD_HI, bev=0.025),
]
for k, x in enumerate((-0.45, -0.15, 0.15, 0.45)):   # gold studs on the step front
    parts.append(gbox(f"Stud{k}", (0.1, 0.04, 0.06), (x, -0.39, 0.07), GOLD, bev=0.01))


def slime(name, x, flip):
    out = [gradient(lathe(name, [(0, 0), (0.2, 0), (0.22, 0.06), (0.2, 0.17), (0.13, 0.27), (0.05, 0.31), (0, 0.32)], segs=12,
                          color_fn=lambda i, k, z: GOLD), GOLD_LO, GOLD_HI)]
    for sx in (-1, 1):
        out.append(blob(f"{name}Eye{sx}", 0.035, (sx * 0.065, -0.17, 0.17), EYE, subdiv=1, jitter=0, squash=(1, 0.6, 1.4)))
    out.append(blob(f"{name}Tuft", 0.05, (0.03 * flip, 0, 0.33), GOLD_HI, subdiv=1, jitter=0, squash=(1, 1, 1.4)))
    return [xf(o, (x, 0.02, 0.48), (0, 0, 14 * flip)) for o in out]


parts += slime("SlimeL", -0.42, 1) + slime("SlimeR", 0.42, -1)
parts.append(gcyl("OrbCup", 0.08, 0.1, (0, 0.08, 0.48), GOLD_LO, GOLD, segs=8, r_top=0.12))
parts.append(blob("Orb", 0.12, (0, 0.08, 0.68), ORB, subdiv=2, jitter=0))
ship("habitat_prop_goo_god", parts)
