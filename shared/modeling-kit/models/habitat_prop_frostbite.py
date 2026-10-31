# habitat_prop_frostbite: a little snowman: two snowballs, coal eyes and buttons, carrot nose, stick arms, red scarf
# and a small top hat.
import math
from models._habitat_prop3 import *

COAL = rgb(64, 64, 80)
CARROT = rgb(255, 136, 40)
SCARF, SCARF_LO = rgb(240, 60, 70), rgb(196, 40, 60)
STICK = rgb(140, 92, 56)
parts = []


def ball(name, r, z):
    o = blob(name, r, (0, 0, z), SNOW, subdiv=2, jitter=0.02, seed=len(name))
    return grad(o, SNOW_LO, SNOW)


parts.append(floor(ball("Low", 0.4, 0.34)))
parts.append(ball("Head", 0.27, 0.9))
# scarf: a ring round the neck plus a hanging tail on the front-left
parts.append(lathe("Scarf", [(0, 0.66), (0.24, 0.66), (0.27, 0.71), (0.24, 0.77), (0, 0.77)], segs=12,
                   color_fn=lambda i, k, z: SCARF if k % 3 else rgb(255, 240, 240)))
tail = box("Tail", (0.11, 0.05, 0.28), (-0.12, -0.25, 0.58), SCARF_LO, rot=(10, 0, -8))
parts.append(tail)
# face
for i, x in enumerate((-0.09, 0.09)):
    parts.append(blob(f"Eye{i}", 0.04, (x, -0.235, 0.97), COAL, subdiv=1, jitter=0))
parts.append(xf(cone("Nose", 0.05, 0.22, (0, 0, 0), CARROT, segs=6), (0, -0.24, 0.9), (90, 0, 0)))
for i, a in enumerate((-35, -15, 15, 35)):
    r = math.radians(a)
    parts.append(blob(f"Smile{i}", 0.022, (math.sin(r) * 0.12, -0.25 + abs(math.sin(r)) * 0.03, 0.83 - math.cos(r) * 0.0 + abs(a) * 0.0008), COAL,
                      subdiv=1, jitter=0))
# buttons
for i, z in enumerate((0.5, 0.36, 0.22)):
    y = -math.sqrt(max(0.4 ** 2 - (z - 0.34) ** 2, 0)) + 0.005
    parts.append(blob(f"Btn{i}", 0.045, (0, y, z), COAL, subdiv=1, jitter=0))
# stick arms with a twig finger each
for s in (-1, 1):
    parts.append(tube(f"Arm{s}", [(s * 0.3, 0, 0.52), (s * 0.55, -0.02, 0.68), (s * 0.7, -0.02, 0.84)], (0.035, 0.03, 0.022), STICK, segs=4))
    parts.append(tube(f"Twig{s}", [(s * 0.58, -0.02, 0.7), (s * 0.7, -0.02, 0.68)], (0.02, 0.015), STICK, segs=4))
# top hat
parts.append(cylinder("Brim", 0.23, 0.04, (0, 0, 1.12), COAL, segs=12))
parts.append(cylinder("Crown", 0.16, 0.24, (0, 0, 1.15), COAL, segs=12))
parts.append(cylinder("Band", 0.165, 0.05, (0, 0, 1.17), SCARF, segs=12))
for o in parts[-3:]:
    xf(o, (0, 0, 0), (-8, 0, 0))
ship("habitat_prop_frostbite", parts)
