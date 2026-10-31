# habitat_prop_klawdius: signature prop for Klawdius: a bucket-moulded sand castle (tall keep, two side towers,
# crenellated walls, dark door) on a sand mound with a red pennant on top and a pink shell. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

SAND, SAND_HI, SAND_D = rgb(240, 204, 132), rgb(252, 228, 168), rgb(214, 170, 104)
DOOR, FLAG, POLE, SHELL = rgb(150, 100, 64), rgb(240, 64, 60), rgb(250, 246, 238), rgb(255, 160, 190)

parts = []
mound = blob("Mound", 0.9, (0, 0.02, 0.0), SAND_D, subdiv=2, squash=(1.0, 0.54, 0.14), jitter=0.04, seed=3)
parts.append(floor(mound))


def tower(n, x, y, r, h, z0=0.05, crenels=6):
    out = []
    t = cylinder(f"T{n}", r, h, (x, y, z0), SAND, segs=10, r_top=r * 0.86, jitter=0.03, seed=n)
    gradient(t, SAND_D, SAND_HI)
    out.append(t)
    rt = r * 0.86
    for k in range(crenels):
        a = k * math.tau / crenels
        out.append(box(f"C{n}_{k}", (rt * 0.5, rt * 0.4, 0.1), (x + math.cos(a) * rt * 0.82, y + math.sin(a) * rt * 0.82, z0 + h + 0.05),
                       SAND_HI, rot=(0, 0, math.degrees(a) + 90)))
    return out


parts += tower(1, 0, 0.05, 0.3, 0.72)
for s in (-1, 1):
    parts += tower(2 + (s > 0), s * 0.55, 0.02, 0.2, 0.46, crenels=5)
    wall = box(f"Wall{s}", (0.36, 0.2, 0.3), (s * 0.28, 0.02, 0.2), SAND)
    gradient(wall, SAND_D, SAND)
    parts.append(wall)
    for k in range(2):
        parts.append(box(f"WC{s}{k}", (0.09, 0.2, 0.08), (s * (0.2 + k * 0.14), 0.02, 0.39), SAND_HI))
    # window slits on the side towers
    parts.append(box(f"Slit{s}", (0.05, 0.04, 0.12), (s * 0.55, -0.17, 0.35), DOOR))
# arched door in the keep
door = slab("Door", [(-0.1, 0), (0.1, 0), (0.1, 0.16)] + [(math.cos(a) * 0.1, 0.16 + math.sin(a) * 0.1)
                                                    for a in (math.radians(v) for v in (30, 60, 90, 120, 150))] + [(-0.1, 0.16)],
            0.05, pos=(0, -0.25, 0.05), color=DOOR)
parts.append(door)
parts.append(box("Win", (0.07, 0.04, 0.1), (0, -0.25, 0.55), DOOR))
# flag on the keep
parts.append(cylinder("Pole", 0.022, 0.4, (0, 0.05, 0.82), POLE, segs=5))
parts.append(slab("Flag", [(0, 0), (0.32, -0.06), (0, -0.14)], 0.03, pos=(0.01, 0.05, 1.2), color=FLAG))
parts.append(blob("Knob", 0.04, (0, 0.05, 1.23), rgb(255, 210, 70), subdiv=1, jitter=0))
# a pink shell stuck on the mound in front
sh = scallop("Shell", 0.16, spread=140, ribs=5, cup=0.03, thick=0.03, nu=3, rib_h=0.02,
             color_fn=lambda p, u: SHELL if p else shade(SHELL, 1.08))
move(sh, (0.42, -0.36, 0.05), (-20, 0, 200))
parts.append(sh)
prop_finish("habitat_prop_klawdius", parts)
