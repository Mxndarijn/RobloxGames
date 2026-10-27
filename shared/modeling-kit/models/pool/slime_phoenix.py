# Phoenix (Mythic, Classic family): a fire-bird slime. Deep red foot -> orange -> bright yellow crown,
# a tall swept-back flame crest, two big raised wings of flame feathers with glowing tips, a fan of
# flame tail feathers behind, ember sparks orbiting, fierce proud eyes and a small gold beak.
from models._slimepool import *

RED, ORANGE, YELLOW, PALE = hexc("ec3a2a"), hexc("ff7a1a"), hexc("ffd23a"), hexc("fff6b0")
EMBER_R, EMBER = hexc("ff4a1a"), hexc("ffb020")
IRIS = hexc("ffb21e")


def paint(a, z, p):
    c = mix(RED, ORANGE, smoothstep(0.15, 1.5, z))
    c = mix(c, YELLOW, smoothstep(1.6, 2.9, z))
    # soft golden chest: an oval patch low on the front
    e = (math.degrees(a) / 48) ** 2 + ((z - 0.78) / 0.5) ** 2
    return mix(c, hexc("ffc83a"), 0.85 * (1 - smoothstep(0.7, 1.0, e)))


H = 3.0
b = Body([(0, 1.05), (0.12, 1.32), (0.5, 1.48), (1.1, 1.46), (1.8, 1.22), (2.45, 0.82), (2.85, 0.38), (H, 0)],
         paint=paint, segs=36, sub=2, gloss=0.7, lean=lambda z: 0.1 * max(0.0, (z - 2.2) / 0.8) ** 2)
parts = [b.obj]


def fire(c_root, c_mid, c_tip, a, d, power=1.0):
    """colour fn along a feather: root -> mid -> glowing tip."""
    a, d = Vector(a), Vector(d)

    def fn(p, n=None):
        t = min(1.0, max(0.0, (p - a).dot(d)))
        t = t ** power
        return mix(c_root, c_mid, t / 0.55) if t < 0.55 else mix(c_mid, c_tip, (t - 0.55) / 0.45)
    return fn


def flame_poly(L, w, n=7, curl=0.3):
    """flame-tongue feather: round body, pointed tip that curls to one side."""
    top, bot = [], []
    for k in range(n + 1):
        t = k / n
        half = w / 2 * math.sin(math.pi * min(1.0, 0.12 + 0.88 * t)) ** 0.8 * (1 - 0.35 * t)
        if k == n:
            half = 0.0
        c = curl * w * t * t
        top.append((t * L, c + half))
        bot.append((t * L, c - half))
    return top + list(reversed(bot[:-1]))


def feather(name, root, d, side, L, w, thick=0.12, curl=0.3, cols=(EMBER_R, ORANGE, PALE), bend=0.0):
    """flame feather slab; bend > 0 sweeps the tip upward (studs at the tip, quadratic)."""
    d = Vector(d).normalized()
    y = Vector(side).normalized()
    y = (y - d * y.dot(d)).normalized()
    col = fire(cols[0], cols[1], cols[2], root, d / L, power=1.0)
    o = puffy_slab(name, flame_poly(L, w, curl=curl), thick, tuple(root), tuple(d), tuple(y), col, rows=2)
    if bend:
        R = Vector(root)
        for v in o.data.vertices:
            t = max(0.0, (v.co - R).dot(d) / L)
            v.co.z += bend * t * t
    return o


# ---- wings: a fan of flame feathers off a raised arm on each side
def wing(sd):
    out = []
    root = b.point(math.radians(sd * 110), 1.65, -0.2)
    e_out = Vector((sd * 0.95, 0.3, 0)).normalized()
    e_up = Vector((0, 0.15, 1)).normalized()
    N = e_out.cross(e_up).normalized()

    def dirv(deg):
        th = math.radians(deg)
        return e_out * math.cos(th) + e_up * math.sin(th)
    arm = dirv(52)
    n = 6
    for i in range(n):
        t = i / (n - 1)
        o = root + arm * (0.15 + 1.05 * t) + N * (0.03 * i * sd)
        d = dirv(-62 + 100 * t)
        L = 0.95 + 0.85 * t ** 0.8
        out.append(feather(f"WingPrim{sd}{i}", o, d, d.cross(N) * sd, L, 0.68, curl=0.35))
    for i in range(3):
        t = i / 2
        o = root + arm * (0.1 + 0.85 * t) - N * (0.12 * sd)
        d = dirv(-40 + 85 * t)
        L = 0.6 + 0.3 * t
        out.append(feather(f"WingCov{sd}{i}", o, d, d.cross(N) * sd, L, 0.5, thick=0.14, curl=0.25,
                           cols=(RED, EMBER_R, ORANGE)))
    arm_pts = [tuple(root + arm * (1.2 * k / 4) + e_up * 0.06 * math.sin(k / 4 * math.pi) - N * 0.08 * sd) for k in range(5)]
    out.append(horn(f"WingArm{sd}", arm_pts, [0.22, 0.2, 0.17, 0.13, 0.09], RED, ORANGE, segs=8))
    return out


parts += wing(1) + wing(-1)

# ---- flame crest: round tapered tongues swept back over the crown
crest = [  # (x, lean back, height, radius, sway)
    (0.0, 0.6, 1.8, 0.27, 0.0),
    (-0.3, 0.5, 1.3, 0.22, -0.25),
    (0.3, 0.5, 1.3, 0.22, 0.25),
    (0.0, 0.85, 0.95, 0.19, 0.0),
    (-0.18, 0.15, 0.7, 0.16, -0.1),
    (0.18, 0.15, 0.7, 0.16, 0.1),
]
for k, (x, back, h, r, sway) in enumerate(crest):
    base = Vector((x, -0.15 + 0.25 * back, H - 0.35))
    pts = []
    for j in range(6):
        t = j / 5
        pts.append(tuple(base + Vector((sway * t * t + 0.06 * math.sin(t * 6 + k), back * t * t, h * t))))
    radii = [r * (1.05 - 0.15 * t) * (1 - t) ** 0.7 + 0.015 for t in (j / 5 for j in range(6))]
    parts.append(horn(f"Crest{k}", pts, radii, ORANGE, PALE, segs=8))

# ---- tail: a fan of long flame feathers behind, tilted up like a peacock
TR = Vector((0, 1.25, 0.8))
tx = Vector((1, 0, 0))
tb = Vector((0, 0.9, 0.42)).normalized()
for layer, (n, spread, L0, w, cols, lift) in enumerate(((5, 80, 2.6, 0.9, (EMBER_R, ORANGE, hexc("ffe680")), 0.0),
                                                       (4, 60, 1.6, 0.8, (RED, EMBER_R, YELLOW), -0.12))):
    for i in range(n):
        t = i / (n - 1) - 0.5
        ang = math.radians(t * spread)
        d = tb * math.cos(ang) + tx * math.sin(ang)
        L = L0 * (1 - 0.45 * abs(t) ** 1.2)
        side = tx * math.cos(ang) - tb * math.sin(ang)
        o = TR + d * 0.1 + Vector((0, lift, 0))
        parts.append(feather(f"Tail{layer}{i}", o, d, side, L, w, thick=0.12, curl=0.35 * (1 if t >= 0 else -1), cols=cols, bend=1.1 * L / L0))

# ---- ember sparks orbiting on a tilted ring: small 3D flame drops pointing up
for k in range(6):
    a = k * math.tau / 6 + 0.4
    R = 2.25 + 0.15 * math.sin(k * 1.7)
    p = Vector((math.cos(a) * R, math.sin(a) * R * 0.8, 1.5 + 0.55 * math.sin(a + 0.8)))
    s = 0.26 + 0.05 * math.cos(k * 2.1)
    parts.append(lathe(f"Ember{k}", [(0, 0), (s * 0.35, s * 0.85), (s * 0.9, s * 0.7), (s * 1.6, 0.35 * s), (s * 2.3, 0)],
                       zgrad(ORANGE, PALE, p.z - s * 0.4, p.z + s * 1.4), pos=tuple(p - Vector((0, 0, s * 0.6))), segs=6))

# ---- fierce proud face: slanted gold-iris eyes, sharp brows, small gold beak
f = Face(b, eye_v=1.62, eye_u=0.5, mouth_v=1.15)
f.eyes("angry", w=0.54, h=0.7, iris=IRIS)
for sd in (-1, 1):  # inner ends down (the library's "angry" brows are swapped)
    f.d(f"Brow{sd}", rect(sd * 0.52, 2.1, 0.42, 0.09, math.radians(18 * sd)), hexc("7a0c14"), off=0.02)
parts += f.parts
bp = b.point(0, 1.3, -0.1)
parts.append(lathe("Beak", [(0, 0.24), (0.16, 0.22), (0.34, 0.1), (0.48, 0)], zgrad(GOLD_D, GOLD_L, bp.z - 0.15, bp.z + 0.15),
                   pos=tuple(bp), axis=(0, -1, -0.45), segs=8, sx=1.15, sy=0.85, smooth=False))

ship("slime_phoenix", parts)
