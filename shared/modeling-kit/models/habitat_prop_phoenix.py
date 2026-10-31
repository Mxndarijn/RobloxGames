# habitat_prop_phoenix: a twig nest heaped with glowing embers, one big red-orange phoenix feather standing in it.
import math, random
from models._habitat_prop3 import *

TWIG, TWIG_LO = rgb(170, 112, 70), rgb(126, 82, 54)
EMB = [rgb(255, 120, 40), rgb(255, 176, 50), rgb(255, 226, 96), rgb(255, 84, 50)]
FEA, FEA_LO, FEA_TIP = rgb(250, 62, 52), rgb(206, 40, 52), rgb(255, 196, 60)
R = random.Random(6)
parts = []
parts.append(cylinder("NestFloor", 0.55, 0.12, (0, 0, 0), TWIG_LO, segs=10))
for j in range(5):
    z = 0.06 + 0.05 * (j % 3)
    rr = 0.56 + 0.04 * (j % 2)
    a0 = R.uniform(0, math.tau)
    pts = [(math.cos(a0 + t) * rr * 1.2, math.sin(a0 + t) * rr * 0.8, z + 0.05 * math.sin(3 * t + j)) for t in [k * math.tau / 9 for k in range(7)]]
    parts.append(tube(f"Twig{j}", pts, [0.08] * 7, TWIG if j % 2 else shade(TWIG, 1.12), segs=4))
# embers: a heap of chunky glowing nuggets inside the ring
for i in range(13):
    a = R.uniform(0, math.tau)
    r = R.uniform(0, 0.42)
    x, y = math.cos(a) * r * 1.15, math.sin(a) * r * 0.85
    z = 0.16 + (0.42 - r) * 0.35
    parts.append(blob(f"Emb{i}", R.uniform(0.1, 0.15), (x, y, z), EMB[i % 4], subdiv=1, jitter=0.15, seed=i))
# feathers: flat vane outline with a quill, the tip bent over; a big red one and a smaller orange one
def feather(name, k, hi, lo, tip, pos, rot, bend):
    pts = []
    for j in range(9):
        t = j / 8
        w = 0.27 * k * math.sin(math.pi * min(1, t * 1.1)) ** 0.7 + 0.02
        pts.append((w * (1.0 if j % 2 else 0.84), (0.12 + 0.95 * t) * k))
    outline = [(0, 0.08 * k)] + pts + [(0.02, 1.12 * k), (-0.04, 1.1 * k)] + [(-x * (0.9 if j % 2 else 1.0), z) for j, (x, z) in enumerate(reversed(pts))]
    vane = prism(name, outline, -0.03, 0.03, hi)
    paint_faces(vane, lambda p, n: tip if p.z > 0.85 * k else mix(lo, hi, (p.z - 0.1) / (0.75 * k)))
    quill = prism(name + "Q", [(-0.025, -0.05), (0.025, -0.05), (0.012, 1.0 * k), (-0.012, 1.0 * k)], -0.045, 0.045, rgb(255, 236, 190))
    out = []
    for o in (vane, quill):
        for v in o.data.vertices:  # curl the tip sideways
            v.co.x += bend * (v.co.z / k) ** 2
        xf(o, pos, rot)
        out.append(o)
    return out


parts += feather("Red", 1.0, FEA, FEA_LO, FEA_TIP, (0.12, 0.1, 0.12), (-12, 18, 0), 0.16)
parts += feather("Ora", 0.68, rgb(255, 150, 40), rgb(240, 96, 40), rgb(255, 226, 90), (-0.2, 0.12, 0.14), (-14, -26, 0), -0.12)
ship("habitat_prop_phoenix", parts)
