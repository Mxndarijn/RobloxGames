# Dragon King (hybrid, tier 6: drako + king + blaze): a regal dragon goo. Crimson body with a gold
# scaled belly, big curved horns with a gold crown sitting between them, a royal purple cape with an
# ermine collar, golden wings spread wide, a flame-tipped tail, and a smug fanged smirk puffing a
# little flame from the mouth corner.
from models._slimepool import *

CRIM, CRIM_D, CRIM_L = hexc("d0142c"), hexc("7a0a1e"), hexc("ff4a3c")
GOLD_B, GOLD_O = hexc("ffcf4a"), hexc("ff9a1a")
PURP, PURP_D, PURP_L = hexc("7a2ee0"), hexc("3e1290"), hexc("a870ff")
FUR, FUR_S = hexc("fffaf2"), hexc("1c1624")
RUBY, SAPH, EMER = hexc("ff2a4a"), hexc("2f7bff"), hexc("22d47a")
ORA, YEL, CREAM, FRED = hexc("ff7a1a"), hexc("ffd23a"), hexc("fff6c0"), hexc("ff3a12")


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


def body_paint(a, z, p):
    c = mix(CRIM_D, CRIM, smoothstep(0.0, 1.0, z))
    c = mix(c, CRIM_L, 0.45 * smoothstep(1.5, 2.9, z))
    belly = smoothstep(0.82, 0.62, abs(a)) * smoothstep(0.92, 0.72, z)
    return mix(c, GOLD_B, belly)


b = Body([(0, 1.14), (0.15, 1.45), (0.5, 1.6), (1.1, 1.54), (1.8, 1.24), (2.4, 0.8), (2.75, 0.32), (2.88, 0)],
         paint=body_paint, sx=1.05, sy=1.02, segs=36, sub=2)
parts = [b.obj]
H = b.H

# ---- gold belly scales (rows of arcs), small crimson back scales
for row, (z, us) in enumerate(((0.66, (-0.36, 0.0, 0.36)), (0.4, (-0.54, -0.18, 0.18, 0.54)))):
    for j, u in enumerate(us):
        parts.append(decal(f"Scale{row}{j}", arc(u, z, 0.17, 200, 340, 0.05, n=6), GOLD_O, off=0.015, on=["Body"]))

# ---- horns: big, swept back and out, cream -> gold
for sd in (-1, 1):
    root = b.point(math.radians(sd * 64), 2.0, -0.12)
    pts = [root, root + Vector((sd * 0.42, 0.05, 0.4)), root + Vector((sd * 0.68, 0.2, 0.9)),
           root + Vector((sd * 0.76, 0.42, 1.38)), root + Vector((sd * 0.86, 0.6, 1.72))]
    parts.append(horn(f"Horn{sd}", pts, [0.27, 0.21, 0.15, 0.09, 0.015], hexc("3a1a2c"), hexc("9a6a7e"), segs=8))
    for j in (1, 2):  # gold horn rings
        q = Vector(pts[j])
        parts.append(torus(f"HornRing{sd}{j}", [0.2, 0.14][j - 1] + 0.012, 0.035, tuple(q), tuple(Vector(pts[j + 1]) - Vector(pts[j - 1])),
                           GOLD, segs=10, rsegs=3))

# ---- gold crown between the horns: band, 5 points with pearls, gems, purple velvet
CZ = 2.38
cr = b.radius(CZ)
gold = zgrad(GOLD_D, GOLD_L, CZ - 0.1, CZ + 0.9)
parts.append(lathe("CrownBand", [(0, cr * 0.98), (0.12, cr * 1.04), (0.38, cr * 1.07), (0.44, cr * 1.03)], gold,
                   pos=(0, 0, CZ - 0.05), segs=20))
parts.append(torus("CrownRim", cr * 1.06, 0.055, (0, 0, CZ - 0.04), (0, 0, 1), GOLD, segs=20, rsegs=4))
parts.append(ball("Velvet", 0.5, (0, 0.02, CZ + 0.42), zgrad(PURP_D, PURP_L, CZ + 0.2, CZ + 0.9), squash=(1, 1, 0.8)))
for k in range(5):
    a = math.radians(k * 72)
    d = Vector((math.sin(a), -math.cos(a), 0))
    base = Vector((0, 0, CZ + 0.35)) + d * cr * 1.04
    tip = base + d * 0.14 + Vector((0, 0, 0.58 if k == 0 else 0.5))
    parts.append(lathe(f"CrownSpike{k}", [(0, 0.16), (0.32, 0.09), ((tip - base).length, 0)], along(GOLD, GOLD_L, base, tip),
                       pos=base, axis=(tip - base), segs=6))
    parts.append(ball(f"Pearl{k}", 0.09, tuple(tip + (tip - base).normalized() * 0.04), FUR, subdiv=1))
parts.append(ball("Orb", 0.12, (0, 0.02, CZ + 0.95), GOLD_L))
parts.append(lathe("Cross", [(0, 0.035), (0.26, 0.035)], GOLD, pos=(0, 0.02, CZ + 1.0), segs=6))
for k, (yaw, c) in enumerate(((0, RUBY), (72, SAPH), (-72, SAPH), (144, EMER), (-144, EMER))):
    a = math.radians(yaw)
    d = Vector((math.sin(a), -math.cos(a), 0))
    rr = 0.18 if yaw == 0 else 0.11
    parts.append(gem(f"Gem{k}", tuple(Vector((0, 0, CZ + 0.18)) + d * (cr * 1.07 + 0.02)), rr, c, axis=tuple(d), h=rr * 1.2, segs=6))

# ---- royal purple cape hugging the back, flaring to the floor, wavy hem, ermine collar
A0, A1 = math.radians(112), math.radians(248)
CT = 1.95


def cape_pt(s, t):
    a = A0 + (A1 - A0) * s
    z = CT - t * (CT - 0.04)
    flare = 0.08 + 0.34 * t ** 1.5
    wave = 0.08 * math.sin(s * math.tau * 3.0) * t ** 2
    p = b.point(a, max(z, 0.04), extra=flare + wave)
    return (p.x, p.y, z)


def cape_col(p, n):
    t = (CT - p.z) / CT
    a = math.atan2(p.x, -p.y)
    fold = 0.5 + 0.5 * math.cos(abs(a) * 6.0)
    c = mix(PURP, PURP_D, 0.3 * fold + 0.35 * t)
    return mix(c, GOLD, smoothstep(0.88, 0.97, t))  # gold hem


parts.append(shell("Cape", cape_pt, 14, 6, 0.07, cape_col))
col_pts = [tuple(b.point(math.radians(a), CT, 0.16)) for a in range(100, 265, 15)]
parts.append(horn("Collar", col_pts, [0.17] * len(col_pts), FUR, FUR, segs=7))
for k, a in enumerate(range(115, 260, 36)):
    p = b.point(math.radians(a), CT, 0.33)
    parts.append(ball(f"Ermine{k}", 0.06, tuple(p), FUR_S, squash=(1, 1, 1.6), subdiv=1))
for sd in (-1, 1):
    p = b.point(math.radians(sd * 98), CT, 0.22)
    d = Vector((p.x, p.y, 0)).normalized()
    parts.append(lathe(f"Clasp{sd}", [(0, 0.16), (0.07, 0.16), (0.1, 0)], GOLD, pos=tuple(p), axis=tuple(d), segs=10))
    parts.append(gem(f"ClaspGem{sd}", tuple(p + d * 0.08), 0.08, RUBY, axis=tuple(d), h=0.09, segs=6))

# ---- wings spread wide: gold-orange membrane, crimson finger bones (drako wing, scaled up)
for sd in (-1, 1):
    wing = [(0, 0.15), (0.6, 0.75), (1.2, 1.2), (1.85, 1.55), (2.25, 1.75), (2.0, 1.05), (1.82, 0.5), (1.5, 0.75),
            (1.18, 0.15), (0.88, 0.42), (0.55, -0.1), (0.25, 0.1), (0.05, -0.12)]
    O, X, Y = Vector((sd * 0.62, 1.05, 1.95)), Vector((sd * 1.0, 0.42, 0.12)).normalized(), Vector((0, -0.12, 1)).normalized()
    parts.append(puffy_slab(f"Wing{sd}", wing, 0.1, O, X, Y, along(GOLD_B, ORA, O + X * 0.3, O + X * 2.0 + Y * 0.6), rows=2))
    for j, (x, y) in enumerate(((2.25, 1.75), (1.82, 0.5), (1.18, 0.15), (0.55, -0.1))):
        if j == 0:
            pts = [O + X * x0 + Y * y0 for x0, y0 in ((0, 0.15), (0.6, 0.78), (1.2, 1.24), (1.85, 1.58), (2.27, 1.77))]
            rad = [0.12, 0.1, 0.08, 0.06, 0.03]
        else:
            pts = [O + X * 0.6 + Y * 0.78, O + X * x + Y * y]
            rad = [0.06, 0.03]
        parts.append(horn(f"WingBone{sd}{j}", [tuple(q - X.cross(Y) * 0.03 * sd) for q in pts], rad, CRIM, CRIM_D, segs=6))
    parts.append(lathe(f"WingClaw{sd}", [(0, 0.06), (0.22, 0)], FUR, pos=tuple(O + X * 2.25 + Y * 1.75), axis=tuple(X * 0.6 + Y), segs=5))


# ---- tail curling out from under the cape, flame tip (blaze)
tail = [(0.0, 1.2, 0.3), (0.25, 1.75, 0.25), (0.6, 2.1, 0.4), (0.85, 2.25, 0.75)]
parts.append(horn("Tail", tail, [0.3, 0.22, 0.14, 0.08], CRIM, CRIM_L, segs=8))


def flame_col(p, n, z0, z1):
    c = mix(YEL, ORA, smoothstep(z0, z0 + (z1 - z0) * 0.5, p.z))
    return mix(c, FRED, smoothstep(z0 + (z1 - z0) * 0.55, z1, p.z))


def tongue(base, top, r0, r1, sway=0.0, n=6):
    out = []
    for k in range(n):
        t = k / (n - 1)
        p = Vector(base).lerp(Vector(top), t)
        p.x += sway * math.sin(t * math.pi * 1.2)
        out.append(((p.x, p.y, p.z), r0 + (r1 - r0) * t ** 0.8, (1, 1, 1.25)))
    return out


tt = Vector(tail[-1])
balls = [((tt.x, tt.y, tt.z + 0.05), 0.24)]
balls += tongue((tt.x, tt.y, tt.z + 0.1), (tt.x + 0.05, tt.y + 0.05, tt.z + 0.85), 0.2, 0.05, sway=-0.1)
balls += tongue((tt.x - 0.12, tt.y, tt.z + 0.05), (tt.x - 0.3, tt.y, tt.z + 0.55), 0.14, 0.04, sway=0.08, n=5)
balls += tongue((tt.x + 0.12, tt.y, tt.z + 0.05), (tt.x + 0.32, tt.y + 0.05, tt.z + 0.6), 0.14, 0.04, sway=-0.08, n=5)
parts.append(goo("TailFlame", balls, lambda p, n: flame_col(p, n, tt.z - 0.1, tt.z + 0.9), tris=320, resolution=0.06))

# ---- smug face: sly gold-iris eyes, one raised brow, fanged smirk
f = Face(b, eye_v=1.6, mouth_v=1.0, eye_u=0.55, s=1.16)
f.eyes("sly", w=0.5, h=0.66, iris=GOLD)
f.d("BrowL", rect(-0.52, 2.02, 0.4, 0.09, math.radians(-12)), INK)
f.d("BrowR", arc(0.52, 1.9, 0.24, 45, 135, 0.09, n=8), INK)
mv = 0.98
f.d("Mouth", arc(0.06, mv + 0.18, 0.32, 218, 322, 0.08, n=10), MOUTH)
for sd, u in ((-1, -0.12), (1, 0.2)):
    f.d(f"Fang{sd}", [(u - 0.06, mv - 0.005 + (0.03 if sd > 0 else 0.0)), (u + 0.06, mv + 0.005 + (0.03 if sd > 0 else 0.0)),
                      (u + 0.005, mv - 0.13 + (0.03 if sd > 0 else 0.0))], WHITE, off=0.04, th=0.02)
for sd in (-1, 1):  # nostrils
    f.d(f"Nostril{sd}", oval(sd * 0.1, 1.24, 0.07, 0.045, n=8), CRIM_D, off=0.02, th=0.012)
f.cheeks(color=hexc("ff8a6a"), w=0.26, h=0.12)
parts += f.parts

# ---- flame breath puff curling up from the right mouth corner
mp = b.point(math.radians(24), 1.08, 0.16)
puff = [((mp.x, mp.y, mp.z), 0.18)]
puff += tongue((mp.x + 0.08, mp.y - 0.08, mp.z + 0.05), (mp.x + 0.5, mp.y - 0.25, mp.z + 0.75), 0.18, 0.05, sway=0.1, n=6)
puff += tongue((mp.x + 0.12, mp.y - 0.1, mp.z), (mp.x + 0.72, mp.y - 0.2, mp.z + 0.3), 0.14, 0.04, sway=-0.05, n=5)
parts.append(goo("Breath", puff, lambda p, n: flame_col(p, n, mp.z - 0.15, mp.z + 0.8), tris=300, resolution=0.05))
for k, (dx, dz, r) in enumerate(((0.85, 0.65, 0.07), (0.55, 1.0, 0.06))):
    parts.append(gem(f"Ember{k}", (mp.x + dx, mp.y - 0.12, mp.z + dz), r, YEL if k else ORA, segs=4))

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_dragon_king", parts)
