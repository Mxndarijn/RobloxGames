# habitat_prop_constellation: an armillary star globe: a purple starry orb inside three gold rings on a gold stand.
import math
from models._habitat_prop5 import *
from models._habitat_prop4 import lathe, torus, paint, move

GOLD, GOLD_LO, GOLD_HI = rgb(255, 200, 70), rgb(244, 166, 44), rgb(255, 236, 150)
ORB, ORB_HI = rgb(150, 110, 245), rgb(200, 160, 255)
PINK = rgb(255, 150, 220)
STAR = rgb(255, 246, 190)

parts = []
base = lathe("Base", [(0.34, 0), (0.34, 0.06), (0.26, 0.1), (0.1, 0.16), (0.06, 0.3), (0.09, 0.36), (0.04, 0.4)], segs=12)
parts.append(gradient(base, GOLD_LO, GOLD))
C = (0, 0, 0.8)
orb = blob("Orb", 0.27, C, ORB, subdiv=2, jitter=0)
paint(orb, lambda c, n: ORB_HI if n.z - n.y * 0.4 > 0.3 else (PINK if n.z < -0.55 else ORB))
parts.append(orb)
R = 0.44
parts.append(torus("Meridian", R, 0.03, seg=20, seg2=4, rot=(90, 0, 0), pos=C, color=GOLD))
parts.append(torus("Equator", R, 0.03, seg=20, seg2=4, pos=C, color=GOLD_HI))
parts.append(move(torus("Ecliptic", R * 0.98, 0.026, seg=20, seg2=4, color=GOLD), rot=(28, 0, 0), pos=C))
parts.append(gradient(rod("Axis", (0, 0, 0.36), (0, 0, C[2] + R + 0.08), 0.025, GOLD_LO, segs=5), GOLD_LO, GOLD))
parts.append(blob("Finial", 0.05, (0, 0, C[2] + R + 0.1), GOLD_HI, subdiv=1, jitter=0))
# little star map on the orb's front: three stars
for k, (x, z) in enumerate([(-0.11, 0.86), (0.02, 0.94), (0.12, 0.78)]):
    y = -math.sqrt(max(0.27 ** 2 - x * x - (z - C[2]) ** 2, 0)) - 0.01
    parts.append(slab(f"S{k}", star_pts(4, 0.055, 0.02, cx=x, cz=z), 0.03, STAR, (0, y, 0)))
ship("habitat_prop_constellation", parts)
