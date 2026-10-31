# habitat_prop_gaia: a small leafy stand (wooden plinth heaped with leaves) and a flower crown floating above it.
import math
from lib import *
from models._habitat_prop2 import *

LEAFS = [rgb(110, 196, 84), rgb(88, 176, 80), rgb(140, 214, 96)]
LILAC = rgb(200, 160, 240)
R = __import__("random").Random(7)

# plinth: short tapered wooden stump-stand
parts = [lathe("Plinth", [(0.36, 0.0), (0.36, 0.06), (0.28, 0.1), (0.24, 0.32), (0.3, 0.36), (0.3, 0.4), (0.0, 0.4)], segs=10,
               col=lambda c, i, k: WOOD_D if c.z < 0.08 else (WOOD if c.z < 0.34 else shade(WOOD, 1.1)))]
# leaf heap on top
for j in range(6):
    a = j * math.tau / 6 + 0.4
    parts.append(blob(f"Heap{j}", 0.15, (math.cos(a) * 0.17, math.sin(a) * 0.17, 0.44), LEAFS[j % 3], subdiv=1,
                      squash=(1.3, 1.0, 0.6), jitter=0.1, seed=j, rot=(0, 0, math.degrees(a))))
parts.append(blob("HeapTop", 0.16, (0, 0, 0.52), LEAFS[2], subdiv=1, squash=(1.2, 1.2, 0.7), jitter=0.1, seed=9))
# leaves at the foot
for j in range(4):
    a = j * math.tau / 4 + 0.8
    parts.append(blob(f"Foot{j}", 0.12, (math.cos(a) * 0.4, math.sin(a) * 0.36, 0.04), LEAFS[(j + 1) % 3], subdiv=1,
                      squash=(1.4, 0.8, 0.35), jitter=0, rot=(0, 0, math.degrees(a))))
# crown: a ring of leaves with flowers, tilted toward the front, floating above the heap
CZ, CR = 0.98, 0.42
tilt = (16, 0, 0)  # leans its front down a little so it reads from the walkway
crown = []
N = 12
for j in range(N):
    a = j * math.tau / N
    crown.append(blob(f"CLeaf{j}", 0.12, (math.cos(a) * CR, math.sin(a) * CR, 0), LEAFS[j % 3], subdiv=1,
                      squash=(1.5, 0.75, 0.6), jitter=0, rot=(20 * (-1) ** j, 0, math.degrees(a) + 90)))
cols = [PINK, rgb(255, 230, 90), LILAC, WHITE, PINK]
for j in range(5):
    a = j * math.tau / 5 - math.pi / 2  # one flower right at the front
    crown += flower(f"CF{j}", 0.13, (math.cos(a) * (CR + 0.06), math.sin(a) * (CR + 0.06), 0.06), cols[j],
                    rot=(55, 0, math.degrees(a) + 90),  # faces outward and up
                    centre=rgb(255, 170, 40) if cols[j] == rgb(255, 230, 90) else YELLOW)
for o in crown:
    move(o, (0, 0, CZ), tilt)
parts += crown
# sparkle beads between heap and crown (the magic)
for j, (x, y, z) in enumerate([(0.16, -0.1, 0.72), (-0.14, 0.05, 0.8), (0.02, -0.18, 0.86)]):
    parts.append(blob(f"Spark{j}", 0.04, (x, y, z), rgb(255, 250, 190), subdiv=1, jitter=0))
ship("habitat_prop_gaia", parts)
