# Willow Wisp (Mythic, Garden family): a glowing forest-spirit slime. Soft green-teal goo that glows
# lighter towards a wispy flame-like top (three curling wisp tongues), drooping willow-leaf strands
# hanging from the crown down its sides (Ribbon*), a little lantern held out in a goo hand, a calm
# glowing-eyed face, and fireflies floating round it.
from models._slimepool import *

TEAL_D, TEAL, TEAL_L = hexc("5cd8bc"), hexc("84f2d0"), hexc("dcfff4")
FLAME, FLAME_L = hexc("b4ffd4"), hexc("fcffa8")
LEAF_D, LEAF, LEAF_L = hexc("7ed45e"), hexc("a0e862"), hexc("dcfc90")
WOOD, WOOD_L = hexc("c48a52"), hexc("e2b07a")
LAMP, LAMP_L = hexc("ffd85a"), hexc("fffbd8")
EYE_D, EYE_G = hexc("1e5a5a"), hexc("eaffa0")

H = 2.9
EV = 1.62


def axes(x, y):
    x = Vector(x).normalized()
    y = Vector(y)
    y = (y - x * y.dot(x)).normalized()
    return x, y


def spline(ctrl, n=4):
    P = [Vector(c) for c in ctrl]
    P = [P[0]] + P + [P[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return [tuple(q) for q in out]


def paint(a, z, p):
    c = mix(TEAL_D, TEAL, smoothstep(0.05, 1.3, z))
    c = mix(c, TEAL_L, 0.4 * smoothstep(1.7, 2.9, z))
    # soft inner-glow swirl bands
    w = 0.5 + 0.5 * math.sin(a * 2 + z * 2.6 + 0.8 * noise.noise(Vector((math.cos(a), math.sin(a), z * 0.6))))
    return mix(c, TEAL_L, 0.18 * w * smoothstep(0.5, 1.6, z))


b = Body([(0, 1.1), (0.12, 1.4), (0.5, 1.56), (1.1, 1.5), (1.75, 1.24), (2.3, 0.86), (2.72, 0.4), (H, 0)],
         paint=paint, segs=40, sub=3, gloss=0.7)
parts = [b.obj]

# ---- wispy flame top: three curling tongues of glowing goo
def flame_col(p, n):
    return mix(mix(TEAL, FLAME, smoothstep(H - 0.45, H - 0.1, p.z)), FLAME_L, smoothstep(H + 0.1, H + 1.0, p.z))


tongues = [
    [((0.0, 0.05, H - 0.3), 0.6), ((0.08, 0.05, H + 0.1), 0.4), ((0.26, 0.0, H + 0.45), 0.26), ((0.2, -0.05, H + 0.78), 0.16),
     ((-0.05, -0.05, H + 1.0), 0.1), ((-0.22, -0.05, H + 1.08), 0.06)],
    [((-0.42, 0.1, H - 0.38), 0.4), ((-0.62, 0.1, H - 0.05), 0.26), ((-0.8, 0.05, H + 0.22), 0.16), ((-0.78, 0.0, H + 0.45), 0.09), ((-0.64, 0.0, H + 0.56), 0.05)],
    [((0.44, 0.15, H - 0.4), 0.38), ((0.66, 0.15, H - 0.1), 0.24), ((0.82, 0.1, H + 0.15), 0.15), ((0.8, 0.05, H + 0.36), 0.08), ((0.68, 0.05, H + 0.45), 0.05)],
]
balls = []
for t in tongues:
    for (p0, r0), (p1, r1) in zip(t, t[1:]):
        for k in range(2):
            s = k / 2
            balls.append((tuple(Vector(p0).lerp(Vector(p1), s)), r0 + (r1 - r0) * s))
    balls.append(t[-1])
parts.append(goo("Flame", balls, flame_col, tris=460, resolution=0.04))

# ---- willow strands: thin drooping stems from the crown, narrow leaves along them (one Ribbon part each)
leaf = [(0, 0), (0.12, 0.05), (0.28, 0.045), (0.4, 0), (0.28, -0.045), (0.12, -0.05)]


def strand(k, yaw, z0, z1, sway):
    a = math.radians(yaw)
    nrm = Vector((math.sin(a), -math.cos(a), 0))
    ctrl = []
    for i in range(5):
        t = i / 4
        z = z0 + (z1 - z0) * t
        aa = a + math.radians(sway) * t
        ctrl.append(b.point(aa, z, 0.08 + 0.16 * t * t))
    pts = spline(ctrl, 2)
    rads = [0.04 - 0.02 * i / (len(pts) - 1) for i in range(len(pts))]
    objs = [horn(f"Ribbon{k}", pts, rads, LEAF_D, LEAF, segs=4, smooth=True)]
    for j in range(1, len(pts)):
        p = Vector(pts[j])
        prev = Vector(pts[j - 1])
        down = (p - prev).normalized()
        side = 1 if j % 2 else -1
        tang = down.cross(nrm).normalized() * side
        X = (down * 0.75 + tang * 0.65).normalized()
        Y = nrm.cross(X).normalized()
        sc = 1.0 + 0.25 * math.sin(j * 1.7 + k)
        poly = [(x * sc, y * sc) for x, y in leaf]
        c0 = mix(LEAF, LEAF_L, j / len(pts))
        objs.append(keep(slab(f"RLeaf{k}_{j}", poly, 0.03, tuple(p), tuple(X), tuple(Y),
                              along(c0, LEAF_L, p, p + X * 0.38)), True))
    return join(f"Ribbon{k}", objs)


for k, (yaw, z0, z1, sway) in enumerate(((62, 2.55, 0.75, 12), (100, 2.62, 0.95, 8), (140, 2.7, 0.65, -6),
                                        (-62, 2.55, 0.8, -12), (-100, 2.62, 0.9, -8), (-140, 2.7, 0.7, 6),
                                        (180, 2.75, 0.85, 0))):
    parts.append(strand(k, yaw, z0, z1, sway))

# ---- little lantern held out on the viewer's right, hanging from a goo hand
hand = b.point(math.radians(80), 1.25, 0.05)
parts.append(goo("Hand", [(tuple(b.point(math.radians(78), 1.3, -0.25)), 0.26), (tuple(hand + Vector((0.12, -0.12, 0.05))), 0.2)],
                 lambda p, n: mix(TEAL, TEAL_L, 0.35), tris=200, resolution=0.05))
grip = hand + Vector((0.22, -0.16, 0.02))
LC = grip + Vector((0.0, 0.0, -0.72))  # lantern centre
parts.append(torus("LampHandle", 0.13, 0.03, tuple(grip + Vector((0, 0, -0.1))), (0, 1, 0), WOOD, segs=12, rsegs=4))
parts.append(lathe("LampCap", [(0, 0.3), (0.07, 0.3), (0.19, 0.15), (0.24, 0.06), (0.26, 0)], along(WOOD, WOOD_L, LC, LC + Vector((0, 0, 0.5))),
                   pos=tuple(LC + Vector((0, 0, 0.26))), segs=8, smooth=False))
parts.append(lathe("LampBase", [(0, 0), (0.0, 0.31), (0.08, 0.31), (0.09, 0)], WOOD, pos=tuple(LC + Vector((0, 0, -0.37))), segs=8, smooth=False))
parts.append(ball("LampGlow", 0.27, tuple(LC - Vector((0, 0, 0.04))), lambda p, n: mix(LAMP, LAMP_L, smoothstep(-0.3, 0.6, -n.y * 0.6 + n.z * 0.4)),
                  squash=(1, 1, 1.15), subdiv=2))
for k in range(4):
    ang = k * math.tau / 4 + math.pi / 4
    off = Vector((math.cos(ang) * 0.27, math.sin(ang) * 0.27, 0))
    parts.append(horn(f"LampBar{k}", [tuple(LC + off + Vector((0, 0, -0.3))), tuple(LC + off + Vector((0, 0, 0.27)))], [0.035, 0.035],
                      WOOD, WOOD, segs=4, smooth=False))

# ---- face: deep teal eyes with a warm glow inside, tiny content :3 mouth
f = Face(b, eye_v=EV, eye_u=0.5, mouth_v=1.22)
for sd in (-1, 1):
    u = sd * 0.5
    f.d(f"Eye{sd}", oval(u, EV, 0.44, 0.58, n=18), EYE_D, off=0.015)
    f.d(f"Iris{sd}", oval(u, EV - 0.06, 0.3, 0.36, n=16), lambda p, n, u=u: mix(hexc("8ff0a8"), EYE_G, smoothstep(EV - 0.24, EV + 0.05, p.z)),
        off=0.03, th=0.012)
    f.d(f"EyeHi{sd}", oval(u - 0.08, EV + 0.13, 0.14, 0.12, n=10), WHITE, off=0.05, th=0.012)
f.mouth("cat", w=1.1)
f.cheeks(color=hexc("ffb2c8"), w=0.26, h=0.13)
parts += f.parts

# ---- fireflies: little glowing orbs floating round it
for k, (x, y, z, r) in enumerate(((-1.95, -0.3, 2.4, 0.11), (-1.6, 0.6, 3.3, 0.09), (1.75, 0.5, 3.1, 0.1), (-2.05, 0.0, 1.2, 0.08))):
    parts.append(ball(f"Firefly{k}", r * 1.4, (x, y, z), lambda p, n: mix(hexc("ffee50"), LAMP_L, 0.3 + 0.4 * max(0.0, -n.y)), subdiv=2))

ship("slime_willow_wisp", parts)
