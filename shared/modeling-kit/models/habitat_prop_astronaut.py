# habitat_prop_astronaut: a little white-and-red rocket with a round blue porthole standing on a launch pad.
import math
from models._habitat_prop5 import *
from models._habitat_prop4 import lathe, torus, paint, move

WHITE, WHITE_LO = rgb(255, 255, 255), rgb(214, 222, 240)
RED, RED_HI = rgb(236, 62, 72), rgb(255, 120, 110)
BLUE, BLUE_HI = rgb(70, 170, 255), rgb(170, 225, 255)
PAD, PAD_HI = rgb(150, 162, 196), rgb(196, 206, 232)
YEL = rgb(255, 214, 70)
ORANGE = rgb(255, 150, 50)

parts = []
# launch pad: a low octagon plate with yellow hazard marks
pad = gcyl("Pad", 0.62, 0.1, (0, 0, 0), PAD, PAD_HI, segs=8)
parts.append(move(pad, scale=(1, 0.86, 1)))
for k in range(4):
    a = math.pi / 4 + k * math.pi / 2
    parts.append(gbox(f"Mark{k}", (0.16, 0.1, 0.03), (math.cos(a) * 0.4, math.sin(a) * 0.34, 0.1), YEL, bev=0,
                      rot=(0, 0, math.degrees(a))))
Z0 = 0.16
# body: white lathe with a red nose cone
body = lathe("Body", [(0.16, Z0), (0.23, Z0 + 0.12), (0.25, Z0 + 0.36), (0.24, Z0 + 0.6), (0.2, Z0 + 0.78)], segs=12)
paint(body, lambda c, n: WHITE if n.x - n.y * 0.3 > -0.5 else WHITE_LO)
parts.append(body)
nose = lathe("Nose", [(0.2, Z0 + 0.78), (0.17, Z0 + 0.9), (0.1, Z0 + 1.02), (0.0, Z0 + 1.12)], segs=12)
parts.append(gradient(nose, RED, RED_HI))
parts.append(torus("Band", 0.245, 0.025, seg=12, seg2=4, pos=(0, 0, Z0 + 0.2), color=RED))
# porthole facing the walkway
parts.append(torus("Rim", 0.1, 0.03, seg=12, seg2=4, rot=(90, 0, 0), pos=(0, -0.235, Z0 + 0.52), color=YEL))
parts.append(gcyl("Glass", 0.09, 0.05, (0, -0.2, Z0 + 0.52), BLUE, BLUE_HI, segs=12, rot=(90, 0, 0)))
# three red fins down to the pad
fin = [(0.0, 0.0), (0.24, -0.06), (0.26, 0.04), (0.0, 0.42)]
for k, a in enumerate((0, 120, 240)):
    f = slab(f"Fin{k}", [(0.2 + u, Z0 - 0.06 + v) for u, v in fin], 0.06, RED, hi=RED_HI)
    parts.append(move(f, rot=(0, 0, a)))
# nozzle + small flame puff under it
parts.append(gcyl("Nozzle", 0.1, 0.08, (0, 0, Z0 - 0.06), rgb(170, 176, 196), segs=10, r_top=0.14))
parts.append(blob("Flame", 0.09, (0, 0, 0.12), ORANGE, subdiv=1, jitter=0, squash=(1, 1, 0.6)))
ship("habitat_prop_astronaut", parts)
