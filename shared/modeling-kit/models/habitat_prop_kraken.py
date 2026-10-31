# habitat_prop_kraken: signature prop for Kraken: a ship's wheel standing upright on a short wooden stub, with a
# little purple tentacle curling up the stub. Front faces -Y (the wheel face).
import math
from lib import *
from models._habitat_prop4 import *

WOOD, WOOD_D, WOOD_L = rgb(184, 116, 66), rgb(140, 86, 52), rgb(222, 164, 102)
BRASS = rgb(255, 200, 70)
TENT, TENT_HI, SUCK = rgb(176, 96, 214), rgb(214, 140, 240), rgb(255, 196, 230)

parts = []
# base plate + stub post
base = cylinder("Base", 0.42, 0.1, (0, 0, 0), WOOD_D, segs=10, r_top=0.38)
parts.append(base)
stub = cylinder("Stub", 0.13, 0.62, (0, 0.04, 0.1), WOOD, segs=8, r_top=0.11)
gradient(stub, WOOD_D, WOOD)
parts.append(stub)

# the wheel in the XZ plane
cz, R = 0.78, 0.38
rim = torus("Rim", R, 0.055, seg=18, seg2=6, rot=(90, 0, 0), pos=(0, -0.12, cz), color=WOOD_L)
parts.append(rim)
parts.append(torus("Inner", R * 0.45, 0.03, seg=12, seg2=4, rot=(90, 0, 0), pos=(0, -0.12, cz), color=WOOD))
hub = cylinder("Hub", 0.1, 0.16, rot=(90, 0, 0), segs=10, color=WOOD_D)
move(hub, (0, -0.04, cz))
parts.append(hub)
parts.append(cylinder("Cap", 0.06, 0.04, rot=(90, 0, 0), pos=(0, -0.2, cz), segs=8, color=BRASS))
for k in range(8):
    a = k * math.tau / 8 + math.pi / 8
    c, s = math.cos(a), math.sin(a)
    parts.append(tube(f"Spoke{k}", [(c * 0.08, -0.12, cz + s * 0.08), (c * R, -0.12, cz + s * R)], [0.03, 0.03], WOOD, segs=4))
    parts.append(tube(f"Handle{k}", [(c * (R + 0.04), -0.12, cz + s * (R + 0.04)), (c * (R + 0.12), -0.12, cz + s * (R + 0.12)),
                                    (c * (R + 0.19), -0.12, cz + s * (R + 0.19))], [0.04, 0.05, 0.035], WOOD_L, segs=4))

# a little tentacle rising out of the base at the front left, curling outward like a question mark
pts = [(-0.18, -0.2, 0.04), (-0.22, -0.24, 0.16), (-0.27, -0.27, 0.28), (-0.36, -0.29, 0.38), (-0.47, -0.29, 0.4),
       (-0.53, -0.28, 0.33), (-0.5, -0.26, 0.26), (-0.44, -0.25, 0.26)]
rr = [0.085, 0.075, 0.064, 0.054, 0.044, 0.034, 0.025, 0.018]
tent = tube("Tentacle", pts, rr, TENT, segs=7, twist_free=True)
gradient(tent, TENT, TENT_HI)
parts.append(tent)
for i in (1, 2, 3, 4):  # suckers on the inner (lower/right) side, facing front
    x, y, z = pts[i]
    parts.append(blob(f"Suck{i}", rr[i] * 0.42, (x + 0.02, y - rr[i] * 0.85, z - rr[i] * 0.3), SUCK, subdiv=1, jitter=0, squash=(1, 0.5, 1)))
prop_finish("habitat_prop_kraken", parts)
