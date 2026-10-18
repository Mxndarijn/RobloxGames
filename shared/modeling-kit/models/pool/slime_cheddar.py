# Cheddar (Common): boxy jelly-cube slime in cheese yellow with darker holes, smug wink grin.
from models._slimepool import *

CHEESE, CHEESE_L, HOLE, HOLE_D = hexc("ffc93a"), hexc("ffe98a"), hexc("e8a020"), hexc("c97d12")
N = 5.0


def bump(a, z):
    return (abs(math.cos(a)) ** N + abs(math.sin(a)) ** N) ** (-1 / N) - 1


def paint(a, z, p):
    return mix(CHEESE, CHEESE_L, smoothstep(1.4, 2.5, z))


b = Body([(0, 1.22), (0.1, 1.38), (0.35, 1.42), (1.5, 1.4), (2.0, 1.34), (2.3, 1.18), (2.45, 0.85), (2.52, 0.4), (2.54, 0)],
         paint=paint, bump=bump, segs=44, sub=2, gloss=0.35)
parts = [b.obj]
holes = [(60, 0.75, 0.34), (95, 1.6, 0.26), (120, 0.9, 0.2), (170, 1.5, 0.38), (205, 0.7, 0.24), (235, 1.65, 0.3),
         (275, 1.0, 0.36), (300, 1.75, 0.18), (-38, 0.55, 0.22), (32, 1.95, 0.16)]
for k, (yaw, z, w) in enumerate(holes):
    fr = frame_at(yaw, z)
    parts.append(decal(f"Hole{k}", oval(0, 0, w, w * 0.9, n=10), HOLE, fr, off=0.012, th=0.02, on=["Body"]))
    parts.append(decal(f"HoleD{k}", oval(w * 0.08, -w * 0.06, w * 0.7, w * 0.6, n=8), HOLE_D, fr, off=0.03, th=0.012, on=["Body"]))
for k, (x, y, w) in enumerate(((0.55, 0.3, 0.36), (-0.6, 0.5, 0.24), (-0.1, -0.5, 0.2))):
    parts.append(decal(f"TopHole{k}", oval(x, y, w, w * 0.85, n=12), HOLE, TOP, off=0.012, th=0.02, on=["Body"]))
    parts.append(decal(f"TopHoleD{k}", oval(x + w * 0.08, y + w * 0.06, w * 0.7, w * 0.6, n=10), HOLE_D, TOP, off=0.03, th=0.012, on=["Body"]))
f = Face(b, eye_u=0.5, eye_v=1.5, mouth_v=1.0).eyes("wink").mouth("smirk", w=1.35).cheeks()
f.d("Brow", arc(-0.5, 1.82, 0.2, 50, 130, 0.07, n=6), INK)
parts += f.parts
ship("slime_cheddar", parts)
