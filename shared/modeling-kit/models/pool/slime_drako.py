# Drako (Epic): baby dragon. Teal, gold scaled belly, back spikes, two horns, small wings, angry-cute eyes, fang.
from models._slimepool import *

TEAL, TEAL_D, TEAL_L = hexc("1fc4a8"), hexc("0e7f78"), hexc("6af0cc")
GOLD_B = hexc("ffcf4a")


def body_paint(a, z, p):
    c = mix(TEAL_D, TEAL, smoothstep(0.0, 1.0, z))
    c = mix(c, TEAL_L, 0.35 * smoothstep(1.5, 2.9, z))
    belly = smoothstep(0.95, 0.75, abs(a)) * smoothstep(1.25, 1.0, z)
    return mix(c, GOLD_B, belly)


b = Body([(0, 1.12), (0.15, 1.42), (0.5, 1.56), (1.1, 1.5), (1.8, 1.2), (2.4, 0.76), (2.75, 0.3), (2.88, 0)],
         paint=body_paint, sy=1.05)
parts = [b.obj]


def normal(a, z):
    dr = (b.radius(z + 0.02) - b.radius(z - 0.02)) / 0.04
    h = Vector((math.sin(a) * b.sx, -math.cos(a) * b.sy, 0)).normalized()
    return (h - Vector((0, 0, dr))).normalized()


# back spikes: crest down the back
for k, z in enumerate((2.75, 2.45, 2.05, 1.6, 1.15, 0.7)):
    a = math.pi
    p = b.point(a, z, -0.05) if z < 2.7 else Vector((0, 0.3, 2.78))
    n = normal(a, z) if z < 2.7 else Vector((0, 0.5, 1)).normalized()
    L = [0.55, 0.62, 0.6, 0.52, 0.42, 0.3][k]
    parts.append(lathe(f"Spike{k}", [(0, 0.22), (L, 0)], along(GOLD_B, hexc("ff9a2a"), p, p + n * L), pos=p, axis=n,
                       segs=6, smooth=False, sx=0.45))
# belly scale arcs
for row, z in enumerate((0.95, 0.68, 0.41)):
    for j in range(-2 + (row % 2), 3, 2) if row % 2 else range(-2, 3, 2):
        pass
for row, (z, us) in enumerate(((0.95, (-0.36, 0.0, 0.36)), (0.66, (-0.54, -0.18, 0.18, 0.54)), (0.37, (-0.36, 0.0, 0.36)))):
    for j, u in enumerate(us):
        parts.append(decal(f"Scale{row}{j}", arc(u, z, 0.17, 200, 340, 0.05, n=8), hexc("e89a1a"), off=0.015, on=["Body"]))

for sd in (-1, 1):
    root = b.point(math.radians(sd * 30), 2.4, -0.1)
    pts = [root, root + Vector((sd * 0.14, 0.12, 0.4)), root + Vector((sd * 0.22, 0.36, 0.75))]
    parts.append(horn(f"Horn{sd}", pts, [0.19, 0.13, 0.02], hexc("fff3d0"), hexc("ffc040"), segs=8))
    wing = [(0, 0.15), (0.5, 0.6), (1.0, 0.95), (1.5, 1.2), (1.35, 0.72), (1.18, 0.35), (0.98, 0.52), (0.78, 0.1),
            (0.56, 0.28), (0.32, -0.15), (0.05, -0.15)]
    O, X, Y = Vector((sd * 0.75, 0.85, 1.7)), Vector((sd * 1.0, 0.5, 0.25)).normalized(), Vector((0, -0.1, 1)).normalized()
    parts.append(puffy_slab(f"Wing{sd}", wing, 0.1, O, X, Y, along(hexc("ffe08a"), GOLD_B, O, O + X * 1.5 + Y * 1.2), rows=2))
    parts.append(horn(f"WingBone{sd}", [O + X * x + Y * y for x, y in ((0, 0.15), (0.5, 0.62), (1.0, 0.97), (1.52, 1.22))],
                      [0.1, 0.08, 0.06, 0.03], TEAL_D, TEAL, segs=6))
# stubby tail
tail = [(0, 1.3, 0.35), (0, 1.75, 0.3), (0.15, 2.1, 0.4), (0.3, 2.3, 0.6)]
parts.append(horn("Tail", tail, [0.32, 0.22, 0.13, 0.03], TEAL, TEAL_D, segs=8))

f = Face(b, eye_v=1.6, mouth_v=1.15)
f.eyes("angry", w=0.5, h=0.66, iris=hexc("ffb020")).mouth("fang", w=1.2).cheeks(color=hexc("ff9a8a"))
parts += f.parts
ship("slime_drako", parts)
