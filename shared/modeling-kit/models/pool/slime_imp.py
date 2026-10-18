# Imp (Epic): little devil. Crimson, black curved horns, bat wings, arrow-tip tail, sly eyes, double fangs grin.
from models._slimepool import *

CRIM, CRIM_D, CRIM_L = hexc("d81e3a"), hexc("8c0f26"), hexc("ff5a6e")
HORN_D, HORN_L = hexc("1c1420"), hexc("4a3a52")
WING, WING_D = hexc("b0102a"), hexc("2a0c18")


def body_paint(a, z, p):
    return mix(CRIM_D, CRIM, smoothstep(0.0, 1.0, z)) if z < 1.0 else mix(CRIM, CRIM_L, smoothstep(1.4, 2.9, z) * 0.5)


b = Body([(0, 1.0), (0.15, 1.3), (0.5, 1.45), (1.1, 1.4), (1.8, 1.12), (2.4, 0.7), (2.85, 0.25), (3.05, 0)],
         paint=body_paint, lean=lambda z: 0.2 * max(0.0, (z - 2.2) / 0.85) ** 2)
parts = [b.obj]

for sd in (-1, 1):
    root = b.point(math.radians(sd * 38), 2.3, -0.1)
    pts = [root, root + Vector((sd * 0.28, -0.02, 0.32)), root + Vector((sd * 0.45, 0.0, 0.7)),
           root + Vector((sd * 0.38, 0.05, 1.02)), root + Vector((sd * 0.18, 0.06, 1.18))]
    parts.append(horn(f"Horn{sd}", pts, [0.24, 0.19, 0.13, 0.07, 0.015], HORN_L, HORN_D, segs=10))
    # bat wing: scalloped bottom edge
    wing = [(0, 0), (0.6, 0.5), (1.2, 0.95), (1.85, 1.3), (1.75, 0.55), (1.4, 0.05), (1.1, 0.4), (0.8, -0.2),
            (0.5, 0.12), (0.2, -0.35)]
    O, X, Y = Vector((sd * 0.7, 0.95, 1.6)), Vector((sd * 0.85, 0.5, 0.15)).normalized(), Vector((0, -0.1, 1)).normalized()
    parts.append(slab(f"Wing{sd}", wing, 0.08, O, X, Y, along(WING_D, WING, O, O + X * 1.8 + Y * 1.0, power=0.8)))
    for j, (x, y) in enumerate(((1.85, 1.3), (1.4, 0.05), (0.8, -0.2))):  # finger bones
        parts.append(horn(f"WingBone{sd}{j}", [O + X * 0.05, O + X * x * 0.55 + Y * y * 0.6 + X.cross(Y) * 0.0, O + X * x + Y * y],
                          [0.08, 0.055, 0.03], HORN_D, HORN_D, segs=6))

# tail with an arrow tip, curling out the back
tail = [(0, 1.35, 0.4), (0.15, 1.85, 0.35), (0.4, 2.2, 0.6), (0.55, 2.3, 1.0), (0.45, 2.15, 1.35)]
parts.append(horn("Tail", tail, [0.17, 0.13, 0.1, 0.085, 0.07], CRIM_D, CRIM, segs=8))
tip = Vector(tail[-1])
parts.append(slab("Arrow", [(0, 0.4), (0.3, -0.05), (0.08, 0.0), (0.0, -0.12), (-0.08, 0.0), (-0.3, -0.05)], 0.1,
                  tip + Vector((0, 0, -0.05)), (1, 0.4, 0), (-0.15, 0.3, 1), HORN_D))

f = Face(b, eye_v=1.52, mouth_v=1.0, s=1.12)
f.eyes("sly", w=0.46, h=0.6, iris=hexc("ffcf3a")).brows("angry", lift=-0.04)
mv = f.mv  # evil crescent grin, corners up, two fangs hanging from the top lip
W = 0.48
top = [(u, mv + 0.16 * (u / W) ** 2) for u in [W * (k / 8 - 1) * 1 for k in range(17)]]
top = [(W * (k / 8 - 1), mv + 0.16 * (k / 8 - 1) ** 2) for k in range(17)]
bot = [(W * (k / 8 - 1), mv + 0.16 * (k / 8 - 1) ** 2 - 0.24 * (1 - (k / 8 - 1) ** 2)) for k in range(15, 0, -1)]
f.d("Mouth", top + bot, MOUTH)
for sd in (-1, 1):
    f.d(f"Fang{sd}", [(sd * 0.1, mv + 0.005), (sd * 0.25, mv + 0.04), (sd * 0.17, mv - 0.15)], WHITE, off=0.04, th=0.012)
f.d("Tongue", oval(0, mv - 0.16, 0.2, 0.07), TONGUE, off=0.04, th=0.012)
parts += f.parts
ship("slime_imp", parts)
