# Monarch (Secret, Garden): a royal butterfly slime. Glowing violet goo with two pairs of huge
# monarch wings on its back: deep plum veins and border, glowing orange cells that shimmer to gold
# at the edges, white dots along the border. Glow-tipped antennae, sparkle eyes, and little
# golden butterflies and glow motes floating round it.
from models._slimepool import *

VIO_D, VIO, VIO_L = hexc("9a6cf2"), hexc("a878ff"), hexc("e6c4ff")
VEIN = hexc("60408e")  # "black" of the wings: deep plum, dark but not pure black
ORG_D, ORG, ORG_L = hexc("ff6c1c"), hexc("ff8a1a"), hexc("ffc83a")
DOT = hexc("fff8ec")
GLOW, GLOW_L = hexc("ffe27a"), hexc("fffbd8")
INKV = hexc("3a2050")
# wing undersides face away from the sun in game: brighter so they stay orange in the shade
BORG_D, BORG, BORG_L = hexc("ff9418"), hexc("ffac20"), hexc("ffd040")
BVEIN = hexc("7450a8")


def paint(a, z, p):
    c = mix(VIO_D, VIO, smoothstep(0.0, 1.4, z))
    c = mix(c, VIO_L, 0.6 * smoothstep(1.8, 3.0, z))
    # soft shimmer band (lighter, pinker) across the middle
    n = noise.noise(Vector((p.x * 1.6, p.y * 1.6, p.z * 1.6 + 2.0)))
    return mix(c, hexc("ffb8f0"), 0.25 * smoothstep(0.15, 0.5, n))


b = Body([(0, 1.05), (0.14, 1.36), (0.5, 1.52), (1.15, 1.5), (1.8, 1.28), (2.4, 0.92), (2.78, 0.46), (2.95, 0)],
         paint=paint, segs=32, sub=2, gloss=0.8)
parts = [b.obj]
H = b.H


# ---- wing geometry in 2D (u out, v up, root at 0, 0)
def ray_hit(poly, a):
    """distance from the root along angle a (radians) to the far polygon outline."""
    d = Vector((math.cos(a), math.sin(a)))
    best = None
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        e = Vector((x1 - x0, y1 - y0))
        den = d.x * e.y - d.y * e.x
        if abs(den) < 1e-9:
            continue
        t = (x0 * e.y - y0 * e.x) / den
        s = (x0 * d.y - y0 * d.x) / den
        if t > 1e-6 and -1e-6 <= s <= 1 + 1e-6:
            best = t if best is None else max(best, t)
    return best or 0.0


def cell(a0, a1, r0, r1fn, gap):
    """vein-bounded cell between rays a0 < a1, from radius r0 out to r1fn(a); edges offset by gap/2."""
    pts = []
    n0 = Vector((-math.sin(a0), math.cos(a0)))  # into the sector from ray a0
    n1 = Vector((math.sin(a1), -math.cos(a1)))  # into the sector from ray a1
    d0, d1 = Vector((math.cos(a0), math.sin(a0))), Vector((math.cos(a1), math.sin(a1)))
    pts.append(d0 * r0 + n0 * gap / 2)
    k = 4
    for i in range(k + 1):
        a = a0 + (a1 - a0) * i / k
        r = r1fn(a)
        da = gap / 2 / max(r, 0.1)
        aa = min(max(a, a0 + da), a1 - da)
        pts.append(Vector((math.cos(aa), math.sin(aa))) * r)
    pts.append(d1 * r0 + n1 * gap / 2)
    if r0 > 0.05:  # inner edge follows an arc
        for i in range(k - 1, 0, -1):
            a = a0 + (a1 - a0) * i / k
            pts.append(Vector((math.cos(a), math.sin(a))) * (r0 + 0.0))
    return [tuple(p) for p in pts]


FORE = [(0, 0.05), (0.4, 0.75), (1.15, 1.5), (1.95, 1.98), (2.5, 2.08), (2.78, 1.86), (2.68, 1.25), (2.25, 0.58), (1.5, 0.08), (0.6, -0.12)]
HIND = [(0, -0.05), (0.6, 0.02), (1.4, -0.05), (2.0, -0.35), (2.18, -0.9), (1.9, -1.45), (1.25, -1.8), (0.6, -1.72), (0.18, -1.05)]
BORDER = 0.3
GAP = 0.085


def wing(tag, poly, angles, split, origin, X, Y, scale, turn=0.0):
    """one wing: thin plum base + thicker orange cells (they cover both faces) + white border dots."""
    S = scale
    ct, st = math.cos(math.radians(turn)), math.sin(math.radians(turn))
    P = [((x * ct - y * st) * S, (x * st + y * ct) * S) for x, y in poly]
    angles = [a + turn for a in angles]
    X, Y = Vector(X).normalized(), Vector(Y).normalized()
    O = Vector(origin)
    Nn = X.cross(Y).normalized()

    def w2(u, v):
        return O + X * u + Y * v

    def cell_col(p, n):
        q = p - O
        u, v = q.dot(X), q.dot(Y)
        a = math.atan2(v, u)
        rr = math.hypot(u, v) / max(ray_hit(P, a), 1e-3)
        lo, mid, hi = (BORG_D, BORG, BORG_L) if n.y > 0 else (ORG_D, ORG, ORG_L)  # +y = the back side
        c = mix(lo, mid, smoothstep(0.2, 0.6, rr))
        return mix(c, hi, smoothstep(0.78, 1.0, rr))

    out = [slab(f"Wing{tag}", P, 0.06, O, X, Y, lambda p, n: BVEIN if n.y > 0 else VEIN, smooth=False)]
    edge = lambda a: ray_hit(P, a) - BORDER * S
    for i in range(len(angles) - 1):
        a0, a1 = math.radians(angles[i]), math.radians(angles[i + 1])
        rs = split * S
        out.append(slab(f"WingC{tag}o{i}", cell(a0, a1, rs + GAP / 2, edge, GAP), 0.11, O, X, Y, cell_col, smooth=False))
        if i % 2 == 0 and i + 2 < len(angles):  # inner cells span two vein sectors
            a2 = math.radians(angles[i + 2])
            out.append(slab(f"WingC{tag}i{i}", cell(a0, a2, 0.22 * S, lambda a: rs - GAP / 2, GAP), 0.11, O, X, Y, cell_col, smooth=False))
        elif i % 2 == 0:
            out.append(slab(f"WingC{tag}i{i}", cell(a0, a1, 0.22 * S, lambda a: rs - GAP / 2, GAP), 0.11, O, X, Y, cell_col, smooth=False))
    # white dots along the border, alternating big/small
    amin, amax = math.radians(angles[0]), math.radians(angles[-1])
    k = 0
    a = amin + 0.05
    while a < amax - 0.03:
        r = ray_hit(P, a) - BORDER * S * 0.5
        big = k % 2 == 0
        c2 = (math.cos(a) * r, math.sin(a) * r)
        out.append(slab(f"WingDot{tag}{k}", oval(c2[0], c2[1], 0.13 if big else 0.08, 0.13 if big else 0.08, n=6), 0.11, O, X, Y, DOT, smooth=False))
        a += (0.2 if big else 0.16) / max(r, 0.5) * 1.6
        k += 1
    return out


SC = 1.22
for sd in (-1, 1):
    root = Vector((sd * 0.3, 0.85, 2.15))
    X = Vector((sd * math.cos(math.radians(10)), math.sin(math.radians(10)), 0.0))
    Yf = Vector((0, -0.12, 1))  # leaning a touch forward: the wing backs face up into the sky light
    # mirror the 2D u axis for the left side by flipping X; the poly stays the same
    parts += wing(f"F{sd}", FORE, [-8, 12, 30, 48, 66, 84], 1.0, root + Vector((0, 0, 0.05)), X, Yf, SC, turn=10)
    parts += wing(f"H{sd}", HIND, [-82, -62, -42, -22, -4], 0.85, root + Vector((0, 0.04, -0.05)), X, Yf, SC * 0.95)
    # antennae with glowing tips
    a0 = Vector((sd * 0.28, -0.1, H - 0.08))
    pts = [a0, a0 + Vector((sd * 0.1, -0.05, 0.45)), a0 + Vector((sd * 0.32, -0.15, 0.85)), a0 + Vector((sd * 0.5, -0.1, 1.1))]
    parts.append(horn(f"Ant{sd}", [tuple(p) for p in pts], [0.065, 0.055, 0.045, 0.04], VEIN, hexc("7a54b0"), segs=6))
    parts.append(ball(f"AntB{sd}", 0.17, tuple(pts[-1] + Vector((sd * 0.04, 0, 0.06))), along(ORG, GLOW_L, pts[-1] - Vector((0, 0, 0.15)), pts[-1] + Vector((0, 0, 0.2)))))


# ---- the back: glowing gold chrysalis spots and white dots down the back of the goo
parts += spots(b, [(180, 1.55, 0.36), (180, 1.05, 0.3), (180, 0.6, 0.24), (148, 1.3, 0.26), (-148, 1.3, 0.26),
                   (152, 0.75, 0.2), (-152, 0.75, 0.2)], hexc("ffcf3a"), n=10)
dots = spots(b, [(165, 1.85, 0.12), (-165, 1.85, 0.12), (165, 0.85, 0.11), (-165, 0.85, 0.11), (128, 0.95, 0.12), (-128, 0.95, 0.12),
                 (130, 1.7, 0.13), (-130, 1.7, 0.13), (180, 0.3, 0.12)], DOT, n=6)
for o in dots:
    o.name = "Dot" + o.name
parts += dots

# ---- floating: three little golden butterflies and glow motes
def mini(name, pos, yaw, s):
    P = Vector(pos)
    a = math.radians(yaw)
    fwd = Vector((math.sin(a), -math.cos(a), 0))
    side = Vector((math.cos(a), math.sin(a), 0))
    out = [ball(f"{name}B", 0.06 * s, tuple(P), VEIN, squash=(1, 1, 2.2), subdiv=1)]
    for sd in (-1, 1):
        for j, (poly, lift) in enumerate((([(0, 0), (0.25, 0.35), (0.55, 0.38), (0.6, 0.12), (0.3, -0.02)], 0.25),
                                          ([(0, 0), (0.3, -0.05), (0.45, -0.25), (0.25, -0.38), (0.05, -0.2)], 0.15))):
            Xw = (side * sd + Vector((0, 0, lift))).normalized()
            out.append(slab(f"{name}W{sd}{j}", [(x * s, y * s) for x, y in poly], 0.04, P, Xw, Vector((0, 0, 1)) - Xw * Xw.z,
                            lambda p, n, P=P: mix(ORG, GLOW, smoothstep(0.05 * s, 0.5 * s, (p - P).length)), smooth=False))
    return out


parts += mini("Fly0", (-2.3, -0.9, 3.6), -30, 1.0)
parts += mini("Fly1", (2.45, -0.6, 1.0), 25, 0.85)
parts += mini("Fly2", (-1.9, -1.3, 0.75), -15, 0.75)
for k, (x, y, z, r) in enumerate(((1.95, -1.1, 3.3, 0.1), (-2.6, -0.5, 2.3, 0.08), (2.6, -0.3, 2.1, 0.07), (-1.2, -1.6, 3.9, 0.07), (1.1, -1.5, 0.35, 0.08))):
    parts.append(ball(f"Mote{k}", r, (x, y, z), GLOW, subdiv=1))

# ---- face: big sparkle eyes with golden irises, small smile, blush
f = Face(b, eye_u=0.5, eye_v=1.6, mouth_v=1.12, ink=INKV, mouth_col=hexc("6a2050"))
f.eyes("sparkle", w=0.44, h=0.56, iris=hexc("ffb02a"))
f.mouth("cat", w=1.0)
f.cheeks(color=hexc("ff8ac8"))
parts += f.parts
ship("slime_monarch", parts)
