# habitat_prop_seraph: signature prop for Seraph: a small golden harp (pillar, slanted soundbox, curved neck,
# cream strings) on a round cloud-white plinth, with a little white wing on the pillar top. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

GOLD, GOLD_LO, GOLD_HI = rgb(255, 200, 64), rgb(246, 170, 40), rgb(255, 232, 140)
STRING, PLINTH, PLINTH_D, WING = rgb(255, 250, 230), rgb(250, 246, 240), rgb(214, 214, 232), rgb(255, 255, 255)

parts = []
pl = cylinder("Plinth", 0.4, 0.12, (0.02, 0, 0), PLINTH, segs=12, r_top=0.36)
gradient(pl, PLINTH_D, PLINTH)
parts.append(pl)
parts.append(torus("PlRim", 0.37, 0.03, seg=12, seg2=4, pos=(0.02, 0, 0.12), color=GOLD))

X0, Z0 = -0.3, 0.14  # pillar foot
col = cylinder("Pillar", 0.055, 1.02, (X0, 0, Z0), GOLD, segs=6)
gradient(col, GOLD_LO, GOLD_HI)
parts.append(col)
parts.append(cylinder("PillarFoot", 0.1, 0.08, (X0, 0, Z0), GOLD_LO, segs=6))
# soundbox: thick tapered bar from the foot to the upper right
sb0, sb1 = (X0 + 0.06, Z0 + 0.04), (0.42, 0.98)
parts.append(tube("Soundbox", [(sb0[0], 0, sb0[1]), (sb1[0], 0, sb1[1])], [0.1, 0.055], GOLD, segs=6))
# neck: S-curve from the pillar top to the soundbox top
neck = [(X0, 1.18), (-0.14, 1.12), (0.04, 1.2), (0.24, 1.22), (0.42, 1.04)]
parts.append(tube("Neck", [(x, 0, z) for x, z in neck], [0.06, 0.05, 0.05, 0.05, 0.055], GOLD_HI, segs=6))
parts.append(blob("Scroll", 0.08, (X0, 0, 1.2), GOLD_HI, subdiv=1, jitter=0))


def neck_z(x):
    for (xa, za), (xb, zb) in zip(neck, neck[1:]):
        if xa <= x <= xb:
            return za + (zb - za) * (x - xa) / (xb - xa)
    return neck[-1][1]


for k in range(6):  # strings from the soundbox up to the neck
    x = -0.18 + k * 0.1
    zb = sb0[1] + (sb1[1] - sb0[1]) * (x - sb0[0]) / (sb1[0] - sb0[0])
    parts.append(cylinder(f"Str{k}", 0.014, neck_z(x) - zb - 0.06, (x, 0, zb + 0.03), STRING, segs=4))
# a small wing on the pillar top: three white feathers fanning back and up
for k, (ang, ln) in enumerate([(30, 0.3), (55, 0.26), (80, 0.2)]):
    a = math.radians(ang)
    parts.append(blob(f"Feather{k}", ln / 2, (X0 - math.cos(a) * ln * 0.5 - 0.02, 0.02, 1.0 + math.sin(a) * ln * 0.5 - 0.06), WING,
                      subdiv=1, jitter=0, squash=(1, 0.3, 0.38), rot=(0, ang, 0)))
prop_finish("habitat_prop_seraph", parts)
