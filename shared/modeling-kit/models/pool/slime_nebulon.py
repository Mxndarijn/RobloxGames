# Nebulon (Celestial): a living nebula. Deep blue -> violet body with swirling pink and cyan nebula
# clouds painted on it, a wispy cloud tail that streams off the back and curls up over the head,
# little nebula clouds drifting round it on a tilted path, a tiny ringed planet floating beside it,
# drifting stars, and big starry eyes.
from models._slimepool import *
import random

DEEP, BLUE, VIOLET = hexc("141a6e"), hexc("2a3ab8"), hexc("6a34d0")
PINK, PINK_L, CY, CY_L = hexc("ff4fc8"), hexc("ffb0ec"), hexc("33d8ff"), hexc("b8f6ff")
STAR, STAR_Y = hexc("ffffff"), hexc("fff2a0")
PLANET_D, PLANET, PLANET_L = hexc("ff8a3a"), hexc("ffc04a"), hexc("fff0b0")
PRING = hexc("9ff0ff")
INKN = hexc("0e0a30")


def paint(a, z, p):
    c = mix(DEEP, BLUE, smoothstep(0.0, 1.2, z))
    c = mix(c, VIOLET, smoothstep(1.3, 2.9, z))
    # swirling nebula: spiral bands twisted with height and warped by noise
    w = noise.noise(Vector((p.x * 1.2, p.y * 1.2, p.z * 1.2 + 2.0)))
    sw = math.sin(2 * a + 2.6 * z + 2.4 * w)
    sw2 = math.sin(2 * a - 2.2 * z + 1.8 * w + 1.7)
    ad = abs(math.degrees(a))
    face = smoothstep(60, 30, ad) * smoothstep(0.75, 1.05, z) * smoothstep(2.35, 2.05, z)  # keep the face calm
    k = 1 - 0.75 * face
    c = mix(c, PINK, 0.85 * k * smoothstep(0.35, 0.85, sw))
    c = mix(c, PINK_L, 0.5 * k * smoothstep(0.85, 0.98, sw))
    c = mix(c, CY, 0.75 * k * smoothstep(0.45, 0.9, sw2))
    c = mix(c, CY_L, 0.4 * k * smoothstep(0.9, 0.99, sw2))
    return c


b = Body([(0, 1.05), (0.14, 1.34), (0.55, 1.52), (1.2, 1.52), (1.85, 1.3), (2.4, 0.94), (2.8, 0.46), (3.0, 0)],
         paint=paint, segs=44, sub=3, gloss=0.85, shade=0.6)
parts = [b.obj]
H = b.H


def tail_col(t):
    if t < 0.4:
        return mix(VIOLET, PINK, t / 0.4)
    if t < 0.75:
        return mix(PINK, CY, (t - 0.4) / 0.35)
    return mix(CY, CY_L, (t - 0.75) / 0.25)


# ---- wispy cloud tail: streams off the lower back, sweeps up behind the head and curls forward
path = [(0.0, 1.1, 0.75), (0.2, 1.85, 0.85), (0.38, 2.55, 1.2), (0.38, 3.0, 1.85), (0.2, 3.1, 2.5), (-0.08, 2.85, 2.9),
        (-0.25, 2.5, 2.85)]
P = [Vector(q) for q in path]
dense = []
for i in range(len(P) - 1):
    p0, p1, p2, p3 = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
    for s in range(4):
        t = s / 4
        dense.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
dense.append(P[-1])
N = len(dense)
balls = []
for i, q in enumerate(dense):
    t = i / (N - 1)
    r = 0.38 * (1 - t) ** 0.9 + 0.08
    r *= 1 + 0.18 * math.sin(i * 1.9)  # puffy, cloudy edge
    balls.append((tuple(q), r))
# side puffs alternate left/right so the edge is lumpy like a cloud
for i in range(1, N - 3, 2):
    q = dense[i]
    t = i / (N - 1)
    tng = (dense[i + 1] - dense[i - 1]).normalized()
    side = tng.cross(Vector((0, 0, 1)))
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side.normalize()
    balls.append((tuple(q + side * (0.3 * (1 - t) + 0.08) * (1 if i % 4 == 1 else -1) + Vector((0, 0, 0.06))), 0.3 * (1 - t) + 0.08))
# wisps breaking off the tip
wisps = [((-0.3, 2.3, 2.58), 0.1), ((-0.25, 2.2, 2.3), 0.075), ((-0.15, 2.18, 2.05), 0.055)]


def tail_paint(p, n):
    best = min(range(N), key=lambda i: (dense[i] - p).length)
    c = tail_col(best / (N - 1))
    w = noise.noise(Vector((p.x * 2.5, p.y * 2.5, p.z * 2.5 + 9.0)))
    c = mix(c, BLUE, 0.45 * smoothstep(0.2, 0.55, w))
    return mix(c, WHITE, 0.25 * max(0.0, n.dot(Vector((-0.4, -0.6, 0.7)).normalized())))


parts.append(goo("Tail", balls, tail_paint, tris=1300, resolution=0.08))
for j, (q, r) in enumerate(wisps):
    parts.append(ball(f"Wisp{j}", r, q, mix(CY, CY_L, 0.4 + 0.2 * j), squash=(1.4, 1, 0.8), subdiv=2))

# ---- little nebula clouds drifting on a tilted path
OC = Vector((0, 0, 1.3))
tilt = math.radians(14)


def orbit(t):
    x, y = math.cos(t) * 2.25, math.sin(t) * 1.8
    return OC + Vector((x, y * math.cos(tilt), y * math.sin(tilt) - x * 0.1))


CL = [(215, 0.85, PINK, PINK_L), (-60, 0.7, CY, CY_L), (110, 0.75, VIOLET, PINK), (35, 0.6, PINK, PINK_L), (160, 0.6, CY, CY_L),
      (-125, 0.55, VIOLET, CY)]
for k, (t, s, c0, c1) in enumerate((math.radians(d), s_, c0, c1) for d, s_, c0, c1 in CL):
    C = orbit(t)
    tng = (orbit(t + 0.01) - orbit(t - 0.01)).normalized()
    cb = [(tuple(C), 0.34 * s, (1.2, 1, 0.75)), (tuple(C + tng * 0.36 * s + Vector((0, 0, -0.06))), 0.27 * s, (1.2, 1, 0.7)),
          (tuple(C - tng * 0.36 * s + Vector((0, 0, -0.08))), 0.24 * s, (1.2, 1, 0.7)), (tuple(C + tng * 0.14 * s + Vector((0, 0, 0.17 * s))), 0.25 * s),
          (tuple(C - tng * 0.18 * s + Vector((0, 0, 0.12 * s))), 0.21 * s), (tuple(C + tng * 0.62 * s + Vector((0, 0, -0.1))), 0.16 * s)]
    parts.append(goo(f"Cloud{k}", cb, lambda p, n, c0=c0, c1=c1: mix(c0, c1, 0.25 + 0.75 * max(0.0, n.z)), tris=200, resolution=0.08))

# ---- spiral galaxy halo floating over the head, tilted towards the face
GC = Vector((0, 0.25, H + 0.6))
gn = Vector((0, -0.6, 1)).normalized()
gq = gn.to_track_quat("Z", "Y")
for arm in range(2):
    outer, inner = [], []
    M = 22
    for k in range(M + 1):
        t = k / M
        th = arm * math.pi + t * 1.35 * math.pi
        r = 0.3 + 1.3 * t
        w = 0.62 * (1 - t) ** 0.8 + 0.05
        for lst, rr in ((outer, r + w * 0.5), (inner, r - w * 0.5)):
            lst.append((math.cos(th) * rr, math.sin(th) * rr))
    poly = outer + list(reversed(inner))
    parts.append(slab(f"GalaxyArm{arm}", poly, 0.07, GC + gn * (0.01 * arm), gq @ Vector((1, 0, 0)), gq @ Vector((0, 1, 0)),
                      lambda p, n: (lambda rr: mix(mix(PINK_L, PINK, smoothstep(0.3, 0.9, rr)), CY, smoothstep(0.9, 1.6, rr)))((p - GC).length),
                      smooth=False))
parts.append(ball("GalaxyCore", 0.36, GC + gn * 0.02, lambda p, n: mix(PINK_L, WHITE, 0.6), squash=(1, 1, 0.45),
                  rot=tuple(math.degrees(v) for v in gq.to_euler()), subdiv=2))

# ---- tiny ringed planet floating beside the head
PC = Vector((-1.95, -0.55, 3.05))
key = Vector((-0.4, -0.6, 0.7)).normalized()
parts.append(ball("Planet", 0.34, PC, lambda p, n: mix(PLANET_D, PLANET_L, smoothstep(-0.5, 0.9, n.dot(key))), subdiv=3))
parts.append(ball("PlanetBand", 0.345, PC, PLANET_D, squash=(1, 1, 0.22), subdiv=2))
parts.append(torus("PlanetRing", 0.58, 0.05, PC, (0.35, -0.4, 1), lambda p, n: mix(PRING, WHITE, 0.5 + 0.5 * n.z), segs=24, rsegs=4))

# ---- drifting stars (4-point sparkles and little 5-point stars)
for j, (pos, r, n_, c) in enumerate((((1.75, -0.6, 3.1), 0.24, 4, STAR_Y), ((2.35, -0.3, 2.2), 0.15, 5, STAR), ((-2.4, -0.2, 1.75), 0.16, 4, STAR),
                                     ((0.6, -1.0, 3.55), 0.13, 5, STAR_Y), ((2.0, -0.9, 0.55), 0.14, 4, STAR), ((-1.4, -0.9, 0.45), 0.12, 5, STAR_Y))):
    parts.append(puffy_slab(f"Spark{j}", star(0, 0, r, r * (0.3 if n_ == 4 else 0.45), n=n_), 0.07, pos, (1, 0, 0), (0, 0, 1), c, rows=2))

# ---- star specks on the body (off the face)
rng = random.Random(3)
k = 0
for i in range(40):
    yaw = rng.uniform(-180, 180)
    z = rng.uniform(0.35, 2.8)
    if abs(yaw) < 58 and 0.7 < z < 2.3:
        continue
    r = rng.uniform(0.045, 0.11)
    shape = star(0, 0, r, r * 0.32, n=4, rot=rng.uniform(0, 45)) if r > 0.08 else oval(0, 0, r * 0.8, r * 0.8, n=6)
    parts.append(decal(f"Speck{k}", shape, STAR if rng.random() < 0.7 else STAR_Y, frame_at(yaw, z), off=0.01, th=0.012, on=["Body"], step=0))
    k += 1

# ---- starry eyes, little :3 smile, cyan-pink cheeks
f = Face(b, eye_u=0.53, eye_v=1.6, mouth_v=1.17, s=1.15, ink=INKN, mouth_col=hexc("ff7ad8"))
for sd in (-1, 1):  # big dark eye with a glowing star inside and a sparkle
    u = sd * f.eu
    f.d(f"Eye{sd}", oval(u, f.ev, 0.62, 0.7, n=18), INKN, off=0.015)
    f.d(f"EyeC{sd}", star(u, f.ev - 0.02, 0.27, 0.12), hexc("fff4b8"), off=0.035, th=0.012)
    f.d(f"EyeRim{sd}", arc(u, f.ev, 0.29, 205, 335, 0.05, n=8, squash=1.12), CY, off=0.035, th=0.01)
    f.d(f"EyeHi{sd}", oval(u - 0.15, f.ev + 0.2, 0.12, 0.1, n=8), WHITE, off=0.05, th=0.012)
f.mouth("cat", w=1.15)
f.cheeks(color=hexc("ff6ad0"), w=0.3, h=0.14)
parts += f.parts

ship("slime_nebulon", parts)
