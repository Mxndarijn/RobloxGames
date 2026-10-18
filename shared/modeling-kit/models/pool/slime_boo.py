# Boo (Secret): a floating ghost slime. Tall pale mint body that tapers into a curling wavy tail
# (no bottom: the tail tip is the lowest point), little raised arms going "boo!", a cheeky
# tongue-out face, and a tiny broken shackle chain on one wrist.
from models._slimepool import *

MINT, MINT_D, MINT_L = hexc("b2ffe0"), hexc("52d6ad"), hexc("f2fffa")
IRON, IRON_L = hexc("6f6a86"), hexc("b8b4d0")
GLOWC = hexc("b98aff")

Z0 = 0.95  # where the body tapers into the tail


def paint(a, z, p):
    c = mix(MINT_D, MINT, smoothstep(Z0, 2.1, z))
    return mix(c, MINT_L, 0.35 * smoothstep(2.8, 3.7, z))


# body: a tall dome that narrows down into the tail root, the lower part waves (ghostly ripples)
b = Body([(Z0, 0.55), (Z0 + 0.25, 0.92), (Z0 + 0.7, 1.32), (Z0 + 1.3, 1.45), (Z0 + 1.9, 1.32), (Z0 + 2.4, 0.95), (Z0 + 2.72, 0.42), (Z0 + 2.82, 0)],
         paint=paint, lean=lambda z: 0.32 * smoothstep(Z0 + 0.9, Z0, z),
         bump=lambda a, z: 0.06 * math.sin(a * 5 + z * 3.0) * smoothstep(Z0 + 1.3, Z0 + 0.3, z), segs=44)
parts = [b.obj]
H = b.H

# the tail: one goo stream from under the body curling forward to a point at the origin
path = [(0, 0.3, Z0 + 0.3), (0.2, 0.42, Z0 - 0.05), (0.5, 0.45, 0.6), (0.62, 0.22, 0.33), (0.45, -0.05, 0.15), (0.15, -0.1, 0.06), (-0.1, 0.0, 0.03)]
rads = [0.62, 0.5, 0.38, 0.28, 0.19, 0.12, 0.07]
balls = []
for (p0, r0), (p1, r1) in zip(zip(path, rads), zip(path[1:], rads[1:])):
    for k in range(3):
        t = k / 3
        balls.append(((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, p0[2] + (p1[2] - p0[2]) * t), r0 + (r1 - r0) * t))
balls.append((path[-1], rads[-1]))
parts.append(goo("Tail", balls, lambda p, n: mix(MINT_D, MINT, smoothstep(0.0, Z0 + 0.3, p.z)), tris=700, resolution=0.05))

# arms raised "boo!": soft nubs on the sides
for sd in (-1, 1):
    p0 = b.point(math.radians(sd * 88), Z0 + 1.15, -0.25)
    p1 = p0 + Vector((sd * 0.55, -0.12, 0.38))
    p2 = p1 + Vector((sd * 0.12, -0.08, 0.3))
    parts.append(goo(f"Arm{sd}", [(tuple(p0), 0.3), (tuple((p0 + p1) / 2), 0.26), (tuple(p1), 0.24), (tuple(p2), 0.22)],
                     lambda p, n: mix(MINT_D, MINT, 0.6), tris=260, resolution=0.05))
    if sd < 0:
        wrist = p1 + Vector((0, 0, -0.02))

# broken shackle on the right wrist (viewer's left) + three dangling links
parts.append(torus("Cuff", 0.3, 0.08, wrist, (0.8, 0.0, 0.6), IRON_L, segs=16, rsegs=6))
prev = wrist + Vector((-0.1, -0.05, -0.36))
for k in range(3):
    p = prev + Vector((-0.03 * k, 0, -0.22 * k))
    nrm = (1, 0, 0) if k % 2 == 0 else (0, 1, 0)
    parts.append(torus(f"Link{k}", 0.13, 0.045, p, nrm, IRON if k % 2 else IRON_L, segs=10, rsegs=4))
parts.append(ball("Weight", 0.21, prev + Vector((-0.08, 0, -0.85)), lambda p, n: mix(IRON, IRON_L, max(0, n.z)), subdiv=2))

# floating ghost-flame wisps around it
for k, (x, y, z, s) in enumerate([(-1.75, 0.2, 3.0, 0.2), (1.8, 0.1, 3.3, 0.16), (1.35, -0.6, 0.9, 0.15)]):
    parts.append(goo(f"Wisp{k}", [((x, y, z), s), ((x + 0.04, y, z + s * 1.3), s * 0.6), ((x + 0.1, y, z + s * 2.2), s * 0.3)],
                     lambda p, n, z0=z: mix(GLOWC, hexc("ffd9ff"), smoothstep(z0 - 0.1, z0 + 0.4, p.z)), tris=120, resolution=0.04))

f = Face(b, eye_u=0.5, eye_v=Z0 + 1.6, mouth_v=Z0 + 1.08)
for sd in (-1, 1):  # tall oval ghost eyes, one squinting cheekily
    if sd > 0:
        f.d("Eye1", arc(0.5, Z0 + 1.5, 0.2, 20, 160, 0.1), INK)
    else:
        f.d("Eye-1", oval(-0.5, Z0 + 1.6, 0.42, 0.64, n=18), INK, off=0.015)
        f.d("EyeHi-1", oval(-0.57, Z0 + 1.73, 0.15, 0.2, n=10), WHITE, off=0.05, th=0.012)
        f.d("EyeHi2-1", oval(-0.42, Z0 + 1.45, 0.07, 0.07, n=8), WHITE, off=0.05, th=0.012)
f.mouth("tongue", w=1.3)
f.cheeks(color=hexc("ffa6c9"))
parts += f.parts
ship("slime_boo", parts)
