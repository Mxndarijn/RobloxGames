# habitat_prop_drako: a big spotted dragon egg sitting in a twig nest.
import math, random
from models._habitat_prop3 import *

EGG, EGG_LO, EGG_HI = rgb(120, 214, 110), rgb(78, 168, 92), rgb(186, 240, 150)
SPOT = rgb(255, 160, 60)
TWIG, TWIG_LO = rgb(186, 132, 80), rgb(140, 96, 58)
R = random.Random(2)
parts = []
# nest: a squat ring of twig tubes wound round, plus a filled floor
parts.append(cylinder("NestFloor", 0.5, 0.12, (0, 0, 0), TWIG_LO, segs=10))
for j in range(5):
    z = 0.06 + 0.05 * (j % 3)
    rr = 0.52 + 0.04 * (j % 2)
    a0 = R.uniform(0, math.tau)
    pts = [(math.cos(a0 + t) * rr * 1.12, math.sin(a0 + t) * rr * 0.82, z + 0.05 * math.sin(3 * t + j)) for t in [k * math.tau / 9 for k in range(7)]]
    parts.append(tube(f"Twig{j}", pts, [0.08] * 7, TWIG if j % 2 else shade(TWIG, 1.1), segs=4))
# egg: lathe egg shape, narrower top
prof = []
for j in range(11):
    t = j / 10
    z = 0.1 + 1.12 * t
    r = 0.42 * math.sin(math.pi * t) ** 0.8 * (1 - 0.22 * t)
    prof.append((r if 0 < j < 10 else 0, z))
egg = lathe("Egg", prof, segs=12, color_fn=lambda i, k, z: mix(EGG_LO, EGG_HI, min(1, (z - 0.1) / 1.0)))
parts.append(egg)
# spots: flat orange discs pressed on the shell, facing out
def egg_r(z):
    t = (z - 0.1) / 1.12
    return 0.42 * math.sin(math.pi * t) ** 0.8 * (1 - 0.22 * t)

for i, (a, z, s) in enumerate([(-90, 0.6, 0.11), (-50, 0.88, 0.08), (-130, 0.4, 0.09), (-115, 0.95, 0.07), (-60, 0.35, 0.07),
                                (20, 0.6, 0.1), (150, 0.7, 0.1)]):
    r = egg_r(z)
    ar = math.radians(a)
    d = cylinder(f"Spot{i}", s, 0.04, (0, 0, -0.02), SPOT if i % 3 else rgb(255, 210, 80), segs=7)
    parts.append(xf(xf(d, (0, 0, 0), (0, 90, 0)), (math.cos(ar) * (r - 0.005), math.sin(ar) * (r - 0.005), z), (0, 0, a)))
ship("habitat_prop_drako", parts)
