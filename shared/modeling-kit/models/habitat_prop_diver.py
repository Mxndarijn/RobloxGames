# habitat_prop_diver: signature prop for Diver: an old brass diving helmet sitting on a sand mound (big front
# porthole with a grill, side portholes, a bolted collar), a rubber air hose snaking off to the right, a starfish and
# a few bubbles rising from the top valve. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

BRASS, BRASS_D, BRASS_HI = rgb(255, 196, 56), rgb(240, 152, 40), rgb(255, 230, 120)
GLASS, GLASS_HI = rgb(96, 196, 245), rgb(200, 242, 255)
SAND, SAND_HI = rgb(236, 200, 134), rgb(255, 230, 172)
HOSE, STAR, BUB = rgb(140, 164, 206), rgb(255, 120, 70), rgb(140, 218, 255)

parts = []
sand = blob("Sand", 0.6, (0.05, 0.05, 0), SAND, subdiv=2, squash=(1.45, 0.86, 0.24), jitter=0.05, seed=3)
gradient(sand, shade(SAND, 0.92), SAND_HI)
parts.append(floor(sand))

HX, HY, HZ, HR = -0.12, 0.02, 0.56, 0.36  # helmet dome centre / radius
prof = [(0.42, 0.06), (0.44, 0.12), (0.42, 0.2), (0.3, 0.24)]
prof += [(HR * math.cos(math.radians(a)), HZ + HR * math.sin(math.radians(a))) for a in (-38, -15, 10, 35, 58, 78)]
prof += [(0.0, HZ + HR)]
helm = lathe("Helm", prof, segs=16, pos=(HX, HY, 0))
paint(helm, lambda c, n: BRASS_D if c.z < 0.22 else (BRASS_HI if n.z > 0.75 else BRASS))
parts.append(helm)
for k in range(8):  # collar bolts
    a = k * math.tau / 8 + 0.2
    parts.append(blob(f"Bolt{k}", 0.04, (HX + math.cos(a) * 0.41, HY + math.sin(a) * 0.41, 0.2), BRASS_HI, subdiv=1, jitter=0))
# front porthole: thick brass ring, glass, cross grill
FZ = HZ - 0.02
parts.append(torus("Port", 0.19, 0.05, seg=16, seg2=5, rot=(90, 0, 0), pos=(HX, HY - HR + 0.02, FZ), color=BRASS_HI))
glass = cylinder("Glass", 0.17, 0.05, (HX, HY - HR + 0.08, FZ), GLASS, segs=14, rot=(90, 0, 0))
paint(glass, lambda c, n: GLASS_HI if c.x < HX - 0.04 and c.z > FZ + 0.04 else GLASS)
parts.append(glass)
parts.append(box("GrillV", (0.035, 0.05, 0.36), (HX, HY - HR, FZ), BRASS))
parts.append(box("GrillH", (0.36, 0.05, 0.035), (HX, HY - HR, FZ), BRASS))
for s in (-1, 1):  # side portholes
    parts.append(torus(f"SPort{s}", 0.1, 0.035, seg=12, seg2=4, rot=(0, 90, 0), pos=(HX + s * (HR - 0.02), HY + 0.02, HZ + 0.02), color=BRASS_HI))
    parts.append(cylinder(f"SGlass{s}", 0.09, 0.04, (HX + s * (HR - 0.06), HY + 0.02, HZ + 0.02), GLASS, segs=10, rot=(0, s * 90, 0)))
# top valve
parts.append(cylinder("Valve", 0.07, 0.1, (HX, HY, HZ + HR - 0.03), BRASS_D, segs=8))
parts.append(cylinder("ValveCap", 0.1, 0.04, (HX, HY, HZ + HR + 0.07), BRASS_HI, segs=8))
# air hose from the back-right of the helmet down onto the sand, curling forward
hp = []
for i in range(9):
    t = i / 8
    hp.append((HX + 0.3 + 0.55 * t, HY + 0.2 - 0.55 * t * t, 0.5 * (1 - t) ** 2 + 0.07 + 0.03 * math.sin(t * 9)))
parts.append(tube("Hose", hp, [0.06] * 9, HOSE, segs=6))
# starfish on the sand, front left
star = [((0.17 if k % 2 == 0 else 0.07) * math.cos(math.pi / 2 + k * math.pi / 5),
         (0.17 if k % 2 == 0 else 0.07) * math.sin(math.pi / 2 + k * math.pi / 5)) for k in range(10)]
sf = slab("Star", star, 0.05, color=STAR)
move(sf, (-0.62, -0.32, 0.07), (80, 0, 20))
parts.append(sf)
# bubbles from the valve
for i, (x, z, r) in enumerate(((0.02, 1.08, 0.06), (-0.06, 1.2, 0.045), (0.04, 1.31, 0.035))):
    parts.append(blob(f"Bub{i}", r, (HX + x, HY - 0.05, z), BUB, subdiv=2, jitter=0))
prop_finish("habitat_prop_diver", parts)
