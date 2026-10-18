# King Goo (Legendary): royal purple, gem crown, curly mustache, red ermine cape, smug sly face.
from models._slimepool import *

PURP, PURP_D, PURP_L = hexc("8a3cf0"), hexc("5a1fb0"), hexc("c9a0ff")
RED, RED_D = hexc("e8283c"), hexc("9c1028")
FUR, FUR_S = hexc("fffaf2"), hexc("1c1624")
RUBY, SAPH, EMER = hexc("ff2a4a"), hexc("2f7bff"), hexc("22d47a")


def shell(name, fn, nu, nv, thick, color):
    """closed thick sheet: fn(s, t) -> point (s, t in 0..1); offset along the sheet normal both ways."""
    bm = bmesh.new()
    P = [[Vector(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]

    def nrm(i, j):
        a = P[min(i + 1, nu)][j] - P[max(i - 1, 0)][j]
        b = P[i][min(j + 1, nv)] - P[i][max(j - 1, 0)]
        return a.cross(b).normalized()
    outer = [[bm.verts.new(P[i][j] + nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    inner = [[bm.verts.new(P[i][j] - nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1]))
            bm.faces.new((inner[i][j + 1], inner[i + 1][j + 1], inner[i + 1][j], inner[i][j]))
    for i in range(nu):
        for j in (0, nv):
            bm.faces.new((outer[i][j], inner[i][j], inner[i + 1][j], outer[i + 1][j]))
    for j in range(nv):
        for i in (0, nu):
            bm.faces.new((outer[i][j], outer[i][j + 1], inner[i][j + 1], inner[i][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, True)


def stroke(pts, widths):
    """closed outline polygon of a 2D polyline with per-point width (decal strokes)."""
    L, R = [], []
    n = len(pts)
    for i in range(n):
        a, c = Vector(pts[max(i - 1, 0)]), Vector(pts[min(i + 1, n - 1)])
        t = (c - a).normalized()
        nn = Vector((-t.y, t.x))
        p = Vector(pts[i])
        L.append(tuple(p + nn * widths[i] / 2)); R.append(tuple(p - nn * widths[i] / 2))
    return L + list(reversed(R))


def stache_pts(sd, v, S=1.3):
    pts, ws = [], []
    for k in range(12):  # sweep out and down
        t = k / 11
        pts.append((sd * (0.04 + 0.42 * t) * S, v - 0.1 * S * math.sin(t * math.pi * 0.85)))
        ws.append((0.08 + 0.13 * math.sin(min(t * 1.3, 1) * math.pi * 0.9)) * S)
    cx, cy, r = sd * 0.47 * S, v + 0.04 * S, 0.1 * S
    for k in range(1, 9):  # curl up and back in
        a = math.radians(-90 + k * 40)
        pts.append((cx + sd * math.cos(a) * r, cy + math.sin(a) * r))
        ws.append(max(0.035, 0.08 - k * 0.006) * S)
    return stroke(pts, ws)


def paint(a, z, p):
    c = mix(PURP_D, PURP, smoothstep(0.0, 1.3, z))
    c = mix(c, PURP_L, 0.45 * smoothstep(1.6, 2.7, z))
    f = smoothstep(0.8, 0.3, abs(a)) * smoothstep(1.4, 0.5, z)
    return mix(c, PURP_L, 0.35 * f)


b = Body([(0, 1.12), (0.14, 1.38), (0.5, 1.52), (1.1, 1.5), (1.8, 1.3), (2.4, 0.95), (2.78, 0.5), (2.9, 0)],
         paint=paint, sx=1.04, segs=36, sub=2)
parts = [b.obj]

# ---- crown: gold band sunk into the head, five pearl-tipped points, velvet cap, gems
CZ = 2.42
cr = b.radius(CZ) * 1.0
gold = zgrad(GOLD_D, GOLD_L, CZ - 0.1, CZ + 0.9)
parts.append(lathe("CrownBand", [(0, cr * 0.98), (0.12, cr * 1.04), (0.42, cr * 1.08), (0.5, cr * 1.04)], gold,
                   pos=(0, 0, CZ - 0.05), segs=24))
parts.append(torus("CrownRim", cr * 1.06, 0.06, (0, 0, CZ - 0.04), (0, 0, 1), GOLD, segs=24, rsegs=5))
parts.append(torus("CrownTop", cr * 1.08, 0.05, (0, 0, CZ + 0.44), (0, 0, 1), GOLD_L, segs=24, rsegs=5))
parts.append(ball("Velvet", 0.62, (0, 0, CZ + 0.45), zgrad(RED_D, RED, CZ + 0.3, CZ + 1.0), squash=(1, 1, 0.75)))
for k in range(5):
    a = math.radians(k * 72)
    d = Vector((math.sin(a), -math.cos(a), 0))
    base = Vector((0, 0, CZ + 0.4)) + d * cr * 1.05
    tip = base + d * 0.16 + Vector((0, 0, 0.62))
    parts.append(lathe(f"Spike{k}", [(0, 0.17), (0.35, 0.1), (0.62, 0)], along(GOLD, GOLD_L, base, tip),
                       pos=base, axis=(tip - base), segs=8))
    parts.append(ball(f"Pearl{k}", 0.1, tuple(tip + (tip - base).normalized() * 0.04), FUR, subdiv=1))
parts.append(ball("Orb", 0.13, (0, 0, CZ + 1.02), GOLD_L))
parts.append(lathe("Cross", [(0, 0.04), (0.28, 0.04)], GOLD, pos=(0, 0, CZ + 1.08), segs=6))
for k, (yaw, c) in enumerate(((0, RUBY), (72, SAPH), (-72, SAPH), (144, EMER), (-144, EMER))):
    a = math.radians(yaw)
    d = Vector((math.sin(a), -math.cos(a), 0))
    rr = 0.2 if yaw == 0 else 0.12
    parts.append(gem(f"Gem{k}", tuple(Vector((0, 0, CZ + 0.2)) + d * (cr * 1.08 + 0.02)), rr, c, axis=tuple(d), h=rr * 1.2, segs=6))

# ---- cape: red sheet hugging the back, flaring to the floor, wavy hem
A0, A1 = math.radians(95), math.radians(265)


def cape_pt(s, t):
    a = A0 + (A1 - A0) * s
    z = 2.1 - t * 2.06
    flare = 0.08 + 0.3 * t ** 1.6
    wave = 0.07 * math.sin(s * math.tau * 3.0) * t ** 2
    p = b.point(a, max(z, 0.04), extra=flare + wave)
    return (p.x, p.y, z)


def cape_col(p, n):
    t = (2.1 - p.z) / 2.06
    a = math.atan2(p.x, -p.y)
    fold = 0.5 + 0.5 * math.cos(abs(a) * 6.0)
    c = mix(RED, RED_D, 0.25 * fold + 0.35 * t)
    return c


parts.append(shell("Cape", cape_pt, 16, 6, 0.07, cape_col))
# ermine collar along the cape top + front edges
col_pts = [tuple(b.point(math.radians(a), 2.1, 0.16)) for a in range(80, 285, 15)]
parts.append(horn("Collar", col_pts, [0.17] * len(col_pts), FUR, FUR, segs=8))
for k, a in enumerate(range(95, 270, 30)):
    p = b.point(math.radians(a), 2.1, 0.33)
    parts.append(ball(f"Ermine{k}", 0.06, tuple(p), FUR_S, squash=(1, 1, 1.6), subdiv=1))
for sd, a in ((1, A0), (-1, A1)):
    edge = [tuple(Vector(cape_pt(0 if sd > 0 else 1, t / 6)) + Vector((0, 0, 0))) for t in range(7)]
    parts.append(horn(f"Trim{sd}", edge, [0.09] * 7, FUR, FUR, segs=6))
    for k in (1, 3, 5):
        q = Vector(edge[k])
        d = Vector((q.x, q.y, 0)).normalized()
        parts.append(ball(f"ErmE{sd}{k}", 0.035, tuple(q + d * 0.08), FUR_S, squash=(1, 1, 1.6), subdiv=1))

for sd in (-1, 1):
    p = b.point(math.radians(sd * 80), 2.1, 0.22)
    d = Vector((p.x, p.y, 0)).normalized()
    parts.append(lathe(f"Clasp{sd}", [(0, 0.17), (0.07, 0.17), (0.1, 0)], GOLD, pos=tuple(p), axis=tuple(d), segs=12))
    parts.append(gem(f"ClaspGem{sd}", tuple(p + d * 0.08), 0.09, RUBY, axis=tuple(d), h=0.1, segs=6))

# ---- smug face: sly gold-iris eyes, one raised brow, curly mustache, smirk
f = Face(b, eye_v=1.62, mouth_v=0.95, eye_u=0.56, s=1.12)
f.eyes("sly", w=0.54, h=0.7, iris=GOLD)
f.d("BrowL", rect(-0.56, 2.1, 0.4, 0.09, math.radians(10)), INK)
f.d("BrowR", arc(0.56, 1.97, 0.24, 45, 135, 0.09, n=8), INK)
f.mouth("smirk", w=0.9, v=0.66)
for sd in (-1, 1):
    f.d(f"Stache{sd}", stache_pts(sd, 1.0), hexc("5a321e"), off=0.04, th=0.04)
    f.d(f"StacheHi{sd}", stroke([(sd * (0.12 + 0.33 * t / 5), 1.02 - 0.07 * math.sin(t / 5 * 2.6)) for t in range(6)], [0.03] * 6),
        hexc("8a5a3c"), off=0.085, th=0.01)
f.cheeks(color=hexc("ff7fb8"), w=0.26, h=0.12)
parts += f.parts
if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_king", parts)
