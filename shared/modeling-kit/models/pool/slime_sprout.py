# Sprout (Common): green-yellow seedling slime, two-leaf sprout on top, derpy googly eyes, one buck tooth.
from models._slimepool import *

LIME, LEMON, STEM = hexc("b4e03a"), hexc("fff27a"), hexc("3f9a36")
LEAF, LEAF_L = hexc("3fb83a"), hexc("8ff05a")


def paint(a, z, p):
    return mix(LIME, LEMON, smoothstep(0.3, 2.7, z))


b = Body([(0, 1.0), (0.12, 1.3), (0.5, 1.46), (1.1, 1.42), (1.75, 1.12), (2.35, 0.62), (2.72, 0.2), (2.82, 0)],
         paint=paint, sx=0.95)
parts = [b.obj]
top = (0.0, 0.0, 2.78)
tip = (0.08, 0.0, 3.45)
parts.append(horn("Stem", [top, (0.02, 0.0, 3.1), tip], [0.12, 0.1, 0.085], STEM, STEM))
leaf = [(0, 0)] + [(0.5 + 0.55 * math.cos(t), 0.42 * math.sin(t) * (1 - 0.35 * math.cos(t))) for t in [math.pi - k * math.tau / 18 for k in range(1, 18)]]
for sd in (-1, 1):
    X = Vector((sd, 0, 0.55)).normalized()
    parts.append(puffy_slab(f"Leaf{sd}", leaf, 0.14, tip, X, (0, math.cos(math.radians(40)), math.sin(math.radians(40))), along(LEAF, LEAF_L, tip, Vector(tip) + X * 1.05)))
f = Face(b, eye_u=0.5, eye_v=1.55, mouth_v=1.05).eyes("googly", w=0.62).cheeks(v=1.15, u=0.95)
mv = f.mv
f.d("Mouth", arc(0, mv + 0.08, 0.28, 208, 332, 0.085), MOUTH)
f.d("Tooth", rect(0.07, mv - 0.13, 0.15, 0.17), WHITE, off=0.04, th=0.02)
parts += f.parts
ship("slime_sprout", parts)
