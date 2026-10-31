# habitat_prop_catfish: signature prop for Catfish: a round fish bowl (glassy aqua water, white rim, glass
# glint) with a little orange fish leaping out of the top in an arc, plus bubbles. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

WATER, WATER_HI, GLASS = rgb(110, 210, 240), rgb(170, 236, 252), rgb(236, 250, 255)
FISH, FISH_HI, FIN = rgb(255, 140, 40), rgb(255, 196, 80), rgb(255, 230, 200)
SAND, BASE = rgb(244, 214, 150), rgb(196, 138, 86)

parts = []
R = 0.47
# bowl: a sphere cut flat at the bottom and at the open top
prof = []
for i in range(9):
    a = math.radians(-62 + i * (62 + 52) / 8)
    prof.append((math.cos(a) * R, math.sin(a) * R))
prof = [(0, prof[0][1])] + prof + [(0, prof[-1][1] - 0.02)]
bz = -prof[0][1] + 0.1
bowl = lathe("Bowl", prof, segs=14, pos=(0, 0, bz))
paint(bowl, lambda c, n: WATER_HI if n.z > 0.9 else mix(WATER, WATER_HI, max(0, min(1, (c.z - 0.1) / 0.9)) * 0.5))
parts.append(bowl)
# sand and pebbles showing at the bottom-front
# parts.append(lathe("Sand", [(0, 0.1), (0.3, 0.1), (0.36, 0.2), (0, 0.24)], segs=12, pos=(0, -0.05, 0.02), color=SAND, squash=(1, 0.7, 1)))
top = bz + prof[-2][1]
parts.append(torus("Rim", math.cos(math.radians(52)) * R + 0.02, 0.055, seg=16, seg2=5, pos=(0, 0, top), color=GLASS))
# glass glint on the front-left
glint = ribbon("Glint", [(math.cos(a) * -R * 1.02 * math.sin(0.5), -math.cos(0.5) * math.cos(a) * R * 1.02, bz + math.sin(a) * R * 1.02)
                         for a in (math.radians(v) for v in (-10, 10, 30))], 0.07, 0.02, up=(0.55, 0.85, 0), color=GLASS)
parts.append(glint)
# little wooden foot ring
parts.append(cylinder("Foot", 0.3, 0.1, (0, 0, 0), BASE, segs=12, r_top=0.27))

# fish leaping out of the top, body along an arc in the XZ plane (faces front with its side)
fz = top + 0.13
body = blob("Fish", 0.2, (0.05, -0.02, fz), FISH, subdiv=2, squash=(1.35, 0.7, 0.95), jitter=0, rot=(0, 25, 0))
gradient(body, FISH, FISH_HI)
parts.append(body)
parts.append(slab("Tail", [(0, 0), (-0.22, 0.15), (-0.18, 0), (-0.22, -0.15)], 0.06, pos=(-0.2, -0.02, fz + 0.1), rot=(0, 25, 0), color=FISH))
parts.append(slab("Dorsal", [(-0.1, 0), (0.08, 0), (-0.06, 0.13)], 0.04, pos=(0.03, -0.02, fz + 0.15), rot=(0, 25, 0), color=FISH_HI))
for s in (-1, 1):
    parts.append(blob(f"EyeW{s}", 0.07, (0.2, -0.02 + s * 0.1, fz - 0.03), FIN, subdiv=1, jitter=0))
    parts.append(blob(f"Eye{s}", 0.04, (0.21, -0.02 + s * 0.155, fz - 0.03), rgb(30, 30, 40), subdiv=1, jitter=0))
# splash drops and bubbles
for i, (x, y, z, rr) in enumerate([(-0.18, -0.1, top + 0.08, 0.06), (0.3, -0.12, top + 0.05, 0.05), (-0.3, 0.05, top + 0.0, 0.045)]):
    parts.append(blob(f"Drop{i}", rr, (x, y, z), WATER_HI, subdiv=1, squash=(1, 1, 1.2), jitter=0))
for i, (x, z, rr) in enumerate([(0.2, bz + 0.05, 0.05), (0.12, bz + 0.25, 0.04), (0.26, bz - 0.15, 0.035)]):
    parts.append(blob(f"Bub{i}", rr, (x, -math.sqrt(max(0.01, R * R - x * x - (z - bz) ** 2)) - 0.01, z), GLASS, subdiv=1, jitter=0, squash=(1, 0.5, 1)))
prop_finish("habitat_prop_catfish", parts)
