# Siren (Mythic, Frost & Sea family): a singing mermaid slime. Aqua-teal goo with shimmering scales on
# the lower body, a fish tail sweeping out behind and curling up into a big coral fluke, frilly
# ear fins, a crown of coral-pink scallop shells with pearls, a tiny golden trident in one fin-hand,
# and a dreamy singing face with music notes floating round her.
from models._slimepool import *

AQUA_D, AQUA, AQUA_L = hexc("3ccad6"), hexc("5ce6e0"), hexc("b4fff4")
SCALE_D, SCALE_L = hexc("3c9ef0"), hexc("72e2f8")
CORAL_D, CORAL, CORAL_L = hexc("ff6f8a"), hexc("ff9aa8"), hexc("ffd4da")
FIN_D, FIN_L = hexc("ff7fa6"), hexc("c9a2ff")
PEARL, PEARL_L = hexc("f2e8ff"), hexc("ffffff")
TGOLD, TGOLD_L = hexc("ffd052"), hexc("fff0a0")
NOTE = hexc("ff9ad2")

H = 3.0
EV = 1.75


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


def scale_mask(u, v, s=0.5):
    """0..1 scale pattern on (u, v): staggered rows of downward arcs (rim of each scale = 1)."""
    row = math.floor(v / (s * 0.6))
    uu = u / s + 0.5 * (row % 2)
    fu = uu - math.floor(uu) - 0.5
    fv = v / (s * 0.6) - row
    d = math.hypot(fu, (fv - 1.0) * 0.9)
    return smoothstep(0.38, 0.5, d) * (1 - smoothstep(0.5, 0.6, d))


def scales_amount(a, z):
    """scales below a wavy line that dips down under the face."""
    front = max(0.0, math.cos(a))
    back = 0.5 - 0.5 * math.cos(a)
    line = 1.0 - 0.4 * front ** 2 + 0.55 * back ** 2 + 0.06 * math.sin(a * 6)
    return smoothstep(line + 0.08, line - 0.08, z)


def paint(a, z, p):
    c = mix(AQUA_D, AQUA, smoothstep(0.1, 1.5, z))
    c = mix(c, AQUA_L, 0.45 * smoothstep(1.8, 3.0, z))
    s = scales_amount(a, z)
    if s > 0:
        sc = mix(SCALE_L, SCALE_D, scale_mask(a * 1.55, z))
        c = mix(c, sc, s)
    return c


b = Body([(0, 1.12), (0.12, 1.42), (0.5, 1.58), (1.1, 1.52), (1.8, 1.28), (2.4, 0.9), (2.82, 0.42), (H, 0)],
         paint=paint, segs=40, sub=3, gloss=0.6)
parts = [b.obj]

# ---- fish tail: a scaly tube out of the lower back, sweeping up behind to a big coral fluke
tp = spline([(0.0, 1.1, 0.55), (-1.0, 1.45, 0.42), (-1.75, 0.75, 0.4), (-2.0, -0.15, 0.6), (-1.9, -0.7, 1.15), (-1.75, -0.85, 1.7)], 3)
n = len(tp) - 1
tr = [0.55 * (1 - 0.72 * k / n) + 0.04 for k in range(n + 1)]
L = [0.0]
for p, q in zip(tp, tp[1:]):
    L.append(L[-1] + (Vector(q) - Vector(p)).length)


def tail_col(p, nrm):
    best, bt = 1e9, 0.0
    for i in range(n):
        A, B = Vector(tp[i]), Vector(tp[i + 1])
        seg = B - A
        t = min(1, max(0, (p - A).dot(seg) / max(seg.length_squared, 1e-9)))
        d = (A + seg * t - p).length
        if d < best:
            best, bt = d, (L[i] + seg.length * t)
    c = mix(SCALE_L, SCALE_D, smoothstep(0.3, 0.5, abs((bt / 0.3) % 1 - 0.5)))
    return mix(c, CORAL, smoothstep(L[-1] * 0.75, L[-1], bt))


o = tube("Tail", tp, tr, None, segs=10, twist_free=True)
paint_fn(o, tail_col)
parts.append(keep(o, True))
tip = Vector(tp[-1])
fluke = [(0, -0.12), (0.3, -0.4), (0.7, -0.85), (1.15, -1.2), (1.05, -0.75), (0.85, -0.3), (0.82, 0.0), (0.85, 0.3), (1.05, 0.75),
         (1.15, 1.2), (0.7, 0.85), (0.3, 0.4), (0, 0.12)]
X, Y = axes((0.1, -0.25, 1.0), (1.0, -0.45, 0.0))
parts.append(puffy_slab("TailFin", fluke, 0.16, tuple(tip - X * 0.12), tuple(X), tuple(Y),
                        along(CORAL_D, FIN_L, tip, tip + X * 1.1), rows=3))

# ---- frilly ear fins: fans on the sides of the head, ribbed coral -> lilac
fan = [(0, -0.12), (0.45, -0.4), (0.82, -0.52), (0.72, -0.28), (0.98, -0.18), (0.82, 0.02), (1.02, 0.14), (0.82, 0.28),
       (0.94, 0.5), (0.62, 0.48), (0.66, 0.68), (0.3, 0.42), (0, 0.14)]
for sd in (-1, 1):
    a = math.radians(sd * 78)
    root = b.point(a, 2.05, -0.12)
    X, Y = axes((sd * 1.0, 0.25, 0.25), (0, -0.2, 1))
    parts.append(puffy_slab(f"Fin{sd}", fan, 0.12, tuple(root), tuple(X), tuple(Y),
                            along(FIN_D, FIN_L, root, root + X * 1.0), rows=2))

# ---- back frill: a small fin down the back of the head
frill = [(-0.5, 0), (0.55, 0), (0.42, 0.22), (0.5, 0.42), (0.22, 0.36), (0.18, 0.58), (-0.05, 0.42), (-0.2, 0.6), (-0.3, 0.3)]
fb = b.point(math.radians(180), 2.0, -0.12)
parts.append(puffy_slab("FinBack", frill, 0.12, tuple(fb), (0, 0.55, -0.85), (0, 0.85, 0.55),
                        along(FIN_D, FIN_L, fb, fb + Vector((0, 0.5, 0.4))), rows=2))

# ---- shell crown: three scallop shells on the head with pearls between
def scallop(name, centre, size, up, face):
    """scallop shell: a smooth fan with a softly lobed rim, 7 raised ribs and two hinge ears."""
    pts = []
    for k in range(29):
        t = math.radians(12 + 156 * k / 28)
        r = size * (1.0 + 0.05 * math.cos(k * math.pi / 2))
        pts.append((math.cos(t) * r, math.sin(t) * r * 0.95))
    pts += [(-size * 0.3, size * 0.04), (-size * 0.3, -size * 0.14), (size * 0.3, -size * 0.14), (size * 0.3, size * 0.04)]
    C = Vector(centre)
    Xv, Yv = axes(Vector((0, 0, 1)).cross(face), up)
    N = Xv.cross(Yv).normalized()
    N = N if N.dot(face) > 0 else -N
    th = 0.13 * size / 0.5
    out = [puffy_slab(name, pts, th, tuple(C), tuple(Xv), tuple(Yv),
                      lambda p, nrm: mix(CORAL_D, CORAL, smoothstep(0.0, size, (p - C).length)), rows=2)]
    for k in range(7):
        t = math.radians(24 + 132 * k / 6)
        d = Xv * math.cos(t) + Yv * math.sin(t) * 0.95
        a0 = C + d * size * 0.12 + N * th * 0.42
        a1 = C + d * size * 0.55 + N * th * 0.55
        a2 = C + d * size * 0.93 + N * th * 0.2
        out.append(horn(f"{name}Rib{k}", [tuple(a0), tuple(a1), tuple(a2)], [0.03 * size / 0.5, 0.05 * size / 0.5, 0.035 * size / 0.5],
                        CORAL_L, CORAL_L, segs=4, smooth=True))
    return out


for k, (yaw, z, sz, tilt) in enumerate(((0, 2.62, 0.8, 0.25), (-38, 2.48, 0.55, 0.25), (38, 2.48, 0.55, 0.25))):
    a = math.radians(yaw)
    base = b.point(a, z, -0.12)
    nrm = Vector((math.sin(a), -math.cos(a), 0))
    up = (Vector((0, 0, 1)) + nrm * tilt).normalized()
    parts += (scallop(f"Shell{k}", base + up * 0.02, sz, up, nrm))
for k, (yaw, z, r) in enumerate(((-17, 2.62, 0.13), (17, 2.62, 0.13), (-48, 2.4, 0.1), (48, 2.4, 0.1))):
    p = b.point(math.radians(yaw), z, 0.04)
    parts.append(ball(f"Pearl{k}", r, tuple(p), along(PEARL, PEARL_L, p - Vector((0, 0, r)), p + Vector((0, 0, r))), subdiv=2))

# ---- tiny golden trident held by a little fin-hand on the viewer's right
hand = b.point(math.radians(82), 1.2, 0.0)
tb, tt = hand + Vector((0.18, -0.1, -0.85)), hand + Vector((0.32, -0.25, 1.35))
parts.append(horn("Trident", [tuple(tb), tuple(tt)], [0.055, 0.055], TGOLD, TGOLD_L, segs=6, smooth=False))
ax = (tt - tb).normalized()
side = Vector((1, 0, 0)) - ax * ax.x
side.normalize()
parts.append(horn("TriBar", [tuple(tt - side * 0.24), tuple(tt + side * 0.24)], [0.055, 0.055], TGOLD, TGOLD, segs=6, smooth=False))
for k, s in enumerate((-1, 0, 1)):
    p0 = tt + side * 0.22 * s
    p1 = p0 + ax * (0.42 if s == 0 else 0.32) + side * 0.04 * s
    parts.append(horn(f"Prong{k}", [tuple(p0 - ax * 0.03), tuple(p1)], [0.05, 0.012], TGOLD, TGOLD_L, segs=6, smooth=False))
parts.append(gem("TriGem", tuple(tt - ax * 0.12), 0.09, CORAL, segs=6, axis=tuple(ax)))
parts.append(goo("Hand", [(tuple(b.point(math.radians(80), 1.25, -0.25)), 0.26), (tuple(hand + Vector((0.12, -0.1, 0.0))), 0.22)],
                 lambda p, nn: mix(AQUA, AQUA_L, 0.3), tris=200, resolution=0.05))

# ---- face: dreamy half-closed eyes with lashes, singing "o" mouth, coral cheeks
f = Face(b, eye_v=EV, eye_u=0.5, mouth_v=1.22)
f.eyes("sparkle", w=0.42, h=0.56, iris=hexc("ff7fb0"))
for sd in (-1, 1):
    u = sd * 0.5
    for k, (du, dv, rot) in enumerate(((0.24, 0.22, 40), (0.3, 0.1, 18))):
        f.d(f"Lash{sd}{k}", rect(u + sd * du, EV + dv, 0.17, 0.055, math.radians(rot * sd)), INK, off=0.02)
f.mouth("o", w=1.0)
f.cheeks(color=hexc("ff9ab8"), w=0.28, h=0.14)
parts += f.parts

# ---- floating music notes (she sings)
def note_poly(s):
    head = oval(0, 0, 0.34 * s, 0.26 * s, n=12, rot=math.radians(20))
    stem = [(0.13 * s, 0.05 * s), (0.13 * s, 0.75 * s), (0.42 * s, 0.6 * s), (0.42 * s, 0.48 * s), (0.2 * s, 0.6 * s), (0.2 * s, 0.05 * s)]
    return head, stem


for k, (x, y, z, s) in enumerate(((-1.55, 0.2, 3.25, 0.85), (2.0, 0.5, 3.0, 0.75), (1.6, 1.4, 1.9, 0.65))):
    p = Vector((x, y, z))
    face_d = Vector((-x * 0.3, -1.0, 0.0)).normalized()
    xa = Vector((0, 0, 1)).cross(face_d).normalized()
    ya = face_d.cross(xa).normalized()
    head, stem = note_poly(s)
    parts.append(slab(f"Note{k}", head, 0.07, tuple(p), tuple(xa), tuple(ya), lambda q, nn: NOTE))
    parts.append(slab(f"NoteS{k}", stem, 0.07, tuple(p), tuple(xa), tuple(ya), lambda q, nn: NOTE))

ship("slime_siren", parts)
