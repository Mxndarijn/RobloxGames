# habitat_prop_siren: signature prop for Siren: a giant open clam on a small teal rock, ribbed coral-pink shell,
# pearly inside, a big glowing pearl in the middle with a few gold sparkles. Front faces -Y.
import math
from mathutils import Vector
from lib import *
from models._habitat_prop4 import *

SHELL, SHELL_D = rgb(255, 120, 168), rgb(236, 92, 146)
INNER, INNER_HI = rgb(236, 196, 255), rgb(255, 232, 246)
PEARL, PEARL_HI, PEARL_LO, SPARK = rgb(255, 246, 236), rgb(255, 255, 255), rgb(255, 214, 232), rgb(255, 222, 80)
ROCK, ROCK_HI = rgb(70, 196, 196), rgb(120, 226, 220)

R, LIFT, HY = 0.62, 0.1, 0.3  # shell radius, base lift, hinge y
hinge = Vector((0, HY, LIFT))


def shell_paint(is_inner):
    def fn(c, n):
        if is_inner(n):
            return INNER_HI if (c - hinge).length < R * 0.45 else INNER
        a = math.atan2(c.x, abs(c.y - HY) + abs(c.z - LIFT))
        return SHELL if int((a + 2) * 5) % 2 == 0 else SHELL_D
    return fn


parts = []
rock = blob("Rock", 0.42, (0, 0.05, 0.0), ROCK, subdiv=2, squash=(1.5, 1.15, 0.32), jitter=0.08, seed=4)
gradient(rock, shade(ROCK, 0.9), ROCK_HI)
parts.append(floor(rock))
low = scallop("Low", R, spread=150, ribs=7, cup=0.16, thick=0.05)
move(low, (0, HY, LIFT + 0.05), (0, 0, 180))
paint(low, shell_paint(lambda n: n.z > 0.35))
parts.append(low)
lid = scallop("Lid", R, spread=150, ribs=7, cup=0.16, thick=0.05)
move(lid, (0, HY, LIFT + 0.08), (70, 0, 0))
paint(lid, shell_paint(lambda n: n.y < -0.3))
parts.append(lid)
parts.append(blob("Hinge", 0.09, (0, HY + 0.02, LIFT + 0.07), SHELL_D, subdiv=1, jitter=0, squash=(1.6, 1, 1)))
# pearl
PZ = LIFT + 0.27
pearl = blob("Pearl", 0.17, (0, -0.02, PZ), PEARL, subdiv=2, jitter=0)
paint(pearl, lambda c, n: PEARL_HI if (n.z > 0.4 and n.x < 0.2) else (PEARL_LO if n.z < -0.2 else PEARL))
parts.append(pearl)
# sparkles (4-point stars) round the pearl
sp = [((0.09 if k % 2 == 0 else 0.025) * math.cos(k * math.pi / 4), (0.09 if k % 2 == 0 else 0.025) * math.sin(k * math.pi / 4)) for k in range(8)]
for i, (x, z, s) in enumerate(((-0.26, PZ + 0.22, 1.0), (0.24, PZ + 0.3, 0.8), (0.3, PZ + 0.05, 0.6))):
    st = slab(f"Spark{i}", [(u * s, v * s) for u, v in sp], 0.03, color=SPARK)
    move(st, (x, -0.12, z))
    parts.append(st)
prop_finish("habitat_prop_siren", parts)
