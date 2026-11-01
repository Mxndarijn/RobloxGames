# habitat_prop_griffin: a big twig nest on a little white cloud, a shiny golden egg in it and two tawny griffin
# feathers tucked into the rim. Front faces -Y.
import math
import random
from lib import *
from models._habitat_prop4 import *

CLOUD, CLOUD_LO = rgb(252, 252, 255), rgb(196, 222, 255)
TWIG, TWIG_HI, TWIG_D = rgb(176, 122, 72), rgb(214, 164, 104), rgb(140, 96, 60)
EGG_LO, EGG, EGG_HI = rgb(250, 196, 64), rgb(255, 210, 70), rgb(255, 244, 170)
FEATH, FEATH_TIP = rgb(230, 150, 64), rgb(255, 236, 200)
parts = []
R = random.Random(7)
for k, (x, y, z, r) in enumerate(((0, 0.02, 0.16, 0.34), (-0.42, 0.0, 0.12, 0.26), (0.42, 0.04, 0.12, 0.27),
                                 (-0.7, 0.02, 0.08, 0.17), (0.72, 0.0, 0.08, 0.16), (-0.18, -0.16, 0.1, 0.22),
                                 (0.2, -0.17, 0.1, 0.22))):
    c = blob(f"Cloud{k}", r, (x, y, z), CLOUD, subdiv=2, squash=(1.25, 1.0, 0.75), jitter=0.04, seed=k)
    gradient(c, CLOUD_LO, CLOUD)
    parts.append(floor(c))
NZ = 0.3  # nest bottom
bowl = lathe("Bowl", [(0, NZ), (0.3, NZ), (0.42, NZ + 0.14), (0.4, NZ + 0.2), (0, NZ + 0.12)], segs=12, squash=(1, 0.82, 1))
paint(bowl, lambda c, n: TWIG_D if n.z > 0.5 and math.hypot(c.x, c.y) < 0.35 else TWIG)
parts.append(bowl)
for k in range(30):  # twigs round the rim, tangential, crossing
    a = k * math.tau / 30 + R.uniform(-0.1, 0.1)
    z = NZ + 0.06 + (k % 3) * 0.065 + R.uniform(-0.02, 0.02)
    rr = 0.42 + R.uniform(-0.02, 0.03) - (0.04 if k % 3 == 0 else 0)
    da, dz = 0.36 + R.uniform(-0.05, 0.08), R.uniform(-0.06, 0.06)
    p0 = (math.cos(a - da) * rr, math.sin(a - da) * rr * 0.82, z - dz)
    p1 = (math.cos(a + da) * (rr + 0.03), math.sin(a + da) * (rr + 0.03) * 0.82, z + dz)
    parts.append(tube(f"Twig{k}", [p0, p1], [0.032, 0.026], (TWIG_HI, TWIG, TWIG_D)[k % 3], segs=4))
# golden egg sitting in the nest
egg = lathe("Egg", [(0, 0), (0.12, 0.03), (0.19, 0.14), (0.19, 0.24), (0.15, 0.36), (0.08, 0.45), (0, 0.48)], segs=12,
            pos=(0.0, 0.0, NZ + 0.1))
paint(egg, lambda c, n: EGG_HI if (n.z > 0.2 and n.x < 0.1 and n.y < 0.2) else (EGG if c.z > NZ + 0.3 else EGG_LO))
parts.append(egg)
# two feathers tucked into the rim, leaning out
feather = [(0, 0), (0.06, 0.1), (0.075, 0.26), (0.06, 0.4), (0.02, 0.5), (-0.015, 0.44), (-0.05, 0.3), (-0.05, 0.12)]
for s, (x, lean) in ((-1, (-0.34, -48)), (1, (0.36, 44))):
    f = slab(f"Feather{s}", feather, 0.025, color=FEATH)
    tip = slab(f"Tip{s}", [(0.066, 0.34), (0.06, 0.4), (0.02, 0.5), (-0.015, 0.44), (-0.048, 0.34)], 0.04, color=FEATH_TIP)
    quill = slab(f"Quill{s}", [(-0.008, -0.04), (0.008, -0.04), (0.006, 0.34), (-0.006, 0.34)], 0.04, color=FEATH_TIP)
    for o in (f, tip, quill):
        move(o, (x, 0.06, NZ + 0.14), (0, lean, 0), (2.0, 1, 0.9))
        parts.append(o)
prop_finish("habitat_prop_griffin", parts)
