# Honey Toad (Rare hybrid: froggo + bumble + flan). A squat golden toad in bumble-bee stripes, glossy
# amber honey glazed over its head and running down in drips (flan's sauce), eyes up on froggo bumps,
# tiny glassy bee wings on its back, and a long tongue licking honey off its lips.
from models._slimepool import *
from mathutils import Euler

Y, Y_D, Y_L = hexc("ffd42a"), hexc("eb9a12"), hexc("fff07a")
K = hexc("3a2216")
BELLY, BELLY_D = hexc("fff6c8"), hexc("ffe08a")
HON, HON_D, HON_L = hexc("ff9a12"), hexc("c85808"), hexc("ffe08a")
IRIS = hexc("ff8a1a")
WING, WING_TIP, WING_RIM = hexc("f4fcff"), hexc("a8e2ff"), hexc("5aa8e0")


def paint(a, z, p):
    c = mix(Y_D, Y, smoothstep(0.0, 0.8, z))
    c = mix(c, Y_L, 0.25 * smoothstep(1.3, 2.2, z))
    f = smoothstep(1.05, 0.6, abs(a)) * smoothstep(1.5, 1.1, z)
    return mix(c, mix(BELLY_D, BELLY, smoothstep(0.1, 1.0, z)), f)


def stripes(a, z):
    # bee bands round the sides and back only: the belly and face stay clean
    if abs(a) < math.radians(62):
        return None
    for z0, z1 in ((0.38, 0.62), (0.92, 1.18), (1.48, 1.72)):
        w = 0.06 * math.cos(a * 2)  # gentle wave
        if z0 + w <= z <= z1 + w:
            return K
    return None


def ddecal(name, poly, color, frame=FRONT, off=0.02, th=0.025, on=None, rings=4):
    """decal() with a subdivided cap (from slime_froggo.py) so wide decals hug tight curves."""
    poly = list(poly)
    cu = sum(p[0] for p in poly) / len(poly)
    cv = sum(p[1] for p in poly) / len(poly)
    bm = bmesh.new()

    def proj(u, v, extra):
        o = frame.O + frame.U * u + frame.V * v + frame.D * 12
        hit = cast(o, -frame.D, on)
        if hit is None:
            raise ValueError(f"ddecal {name}: ({u:.2f}, {v:.2f}) misses")
        loc, n, _ = hit
        if n.dot(frame.D) < 0:
            n = -n
        n = (n * 0.6 + frame.D * 0.4).normalized()
        return bm.verts.new(loc + n * extra)

    layers = []
    for extra in (off, off + th):
        rl = []
        for r in range(rings):
            f = 1 - r / rings
            rl.append([proj(cu + (u - cu) * f, cv + (v - cv) * f, extra) for u, v in poly])
        layers.append((rl, proj(cu, cv, extra)))
    k = len(poly)
    for li, (rl, c) in enumerate(layers):
        flip = li == 0
        for a, b2 in zip(rl, rl[1:]):
            for i in range(k):
                j = (i + 1) % k
                q = (a[i], a[j], b2[j], b2[i])
                bm.faces.new(tuple(reversed(q)) if flip else q)
        for i in range(k):
            tri = (rl[-1][i], rl[-1][(i + 1) % k], c)
            bm.faces.new(tuple(reversed(tri)) if flip else tri)
    back, front = layers[0][0][0], layers[1][0][0]
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((back[i], back[j], front[j], front[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, color)
    return keep(o, False)


b = Body([(0, 1.18), (0.12, 1.46), (0.45, 1.6), (1.05, 1.53), (1.65, 1.27), (2.07, 0.82), (2.34, 0.3), (2.42, 0)],
         paint=paint, sectors=stripes, segs=32, sub=2, sx=1.1, sy=0.95, gloss=0.5)
parts = [b.obj]


# ---- honey glaze: closed shell over the crown, lower edge snapped per column into drips (flan recipe)
def adiff(a, c):
    return math.atan2(math.sin(a - c), math.cos(a - c))


DRIPS = [(math.radians(d), depth, w) for d, depth, w in
         ((0, 0.3, 0.12), (62, 0.55, 0.15), (-66, 0.8, 0.16), (110, 0.95, 0.16), (-118, 0.6, 0.15), (155, 0.75, 0.16), (-160, 1.0, 0.16))]


def drip(a):
    d, wt = 0.0, 0.0
    for c, depth, w in DRIPS:
        x = adiff(a, c) / w
        k = math.exp(-x * x * 1.6) if abs(x) < 3 else 0.0
        d = max(d, depth * k ** 0.35 if k > 0.02 else 0.0)
        wt = max(wt, k)
    return d, wt


prof = list(reversed(b.prof))
L = [0.0]
for (z0, r0), (z1, r1) in zip(prof, prof[1:]):
    L.append(L[-1] + math.hypot(z1 - z0, r1 - r0))


def at_len(l):
    for i in range(len(prof) - 1):
        if L[i + 1] >= l or i == len(prof) - 2:
            t = min(1, max(0, (l - L[i]) / max(L[i + 1] - L[i], 1e-9)))
            (z0, r0), (z1, r1) = prof[i], prof[i + 1]
            dz, dr = z1 - z0, r1 - r0
            n = math.hypot(dz, dr) or 1
            return z0 + dz * t, r0 + dr * t, (-dz / n, dr / n)
    return prof[-1][0], prof[-1][1], (1, 0)


def len_at_z(zt):
    for i in range(len(prof) - 1):
        (z0, _), (z1, _) = prof[i], prof[i + 1]
        if z1 <= zt <= z0 and z0 > z1:
            return L[i] + (L[i + 1] - L[i]) * (z0 - zt) / (z0 - z1)
    return L[-1]


def honey(cols=40, rows=4, base_z=1.92):
    L_SIDE = len_at_z(base_z + 0.15)
    bm = bmesh.new()
    outer, inner_bot, inner_top = [], [], []
    for i in range(cols):
        a = i * math.tau / cols
        dd, wt = drip(a)
        lend = len_at_z(base_z + 0.04 * math.sin(a * 5 + 0.7) - dd)
        top_rows = [l for l in L if 0 < l < L_SIDE - 0.02]
        ls = top_rows + [L_SIDE + (lend - L_SIDE) * (j / rows) for j in range(rows + 1)]
        col = []
        for l in ls:
            s = max(0.0, (l - L_SIDE) / max(lend - L_SIDE, 1e-6))
            z, r, (nr, nz) = at_len(l)
            e = 0.05 + 0.13 * wt * smoothstep(0.6, 1.0, s) * (1 if dd > 0.2 else 0)
            col.append(bm.verts.new((math.sin(a) * (r + nr * e) * b.sx, -math.cos(a) * (r + nr * e) * b.sy, z + nz * e)))
        outer.append(col)
        z, r, _ = at_len(lend)
        inner_bot.append(bm.verts.new((math.sin(a) * (r - 0.03) * b.sx, -math.cos(a) * (r - 0.03) * b.sy, z)))
        inner_top.append(bm.verts.new((math.sin(a) * 0.5, -math.cos(a) * 0.5, b.H - 0.2)))
    ctop = bm.verts.new((0, 0, b.H + 0.05))
    cin = bm.verts.new((0, 0, b.H - 0.2))
    for i in range(cols):
        j = (i + 1) % cols
        bm.faces.new((ctop, outer[i][0], outer[j][0]))
        for k in range(len(outer[i]) - 1):
            bm.faces.new((outer[i][k], outer[i][k + 1], outer[j][k + 1], outer[j][k]))
        bm.faces.new((outer[i][-1], inner_bot[i], inner_bot[j], outer[j][-1]))
        bm.faces.new((inner_bot[i], inner_top[i], inner_top[j], inner_bot[j]))
        bm.faces.new((inner_top[i], cin, inner_top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm("Honey", bm)

    def col(p, n):
        c = mix(HON_D, HON, smoothstep(0.9, b.H, p.z))
        d = (p - Vector((0, 0, 1.4))).normalized()
        h = max(0.0, d.dot(Vector((-0.45, -0.6, 0.66)).normalized()))
        c = mix(c, mix(HON, HON_L, 0.5), 0.5 * smoothstep(0.5, 0.95, h))
        return mix(c, WHITE, 0.85 * smoothstep(0.93, 0.985, h))
    paint_fn(o, col)
    return keep(o, True)


parts.append(honey())


# a chunk of honeycomb stuck in the glaze on top: three hex cells, each top inset into a dark cell
def honeycomb(name, centre, R=0.2, h=0.16, rot=(0.0, 0.0, 0.0)):
    bm = bmesh.new()
    cells = []
    for cx, cy in ((0, 0), (R * 1.5, R * 0.866), (R * 1.5, -R * 0.866)):
        bot = [bm.verts.new((cx + math.cos(k * math.pi / 3) * R, cy + math.sin(k * math.pi / 3) * R, 0)) for k in range(6)]
        top = [bm.verts.new((v.co.x, v.co.y, h)) for v in bot]
        bm.faces.new(list(reversed(bot)))
        cells.append(bm.faces.new(top))
        for k in range(6):
            j = (k + 1) % 6
            bm.faces.new((bot[k], bot[j], top[j], top[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.inset_individual(bm, faces=cells, thickness=0.04, depth=-0.06)
    col = bm.loops.layers.color.new("Col")
    cs = set(cells)
    for f in bm.faces:
        for lp in f.loops:
            lp[col] = HON_D if f in cs else (HON_L if f.normal.z > 0.5 else mix(HON, HON_L, 0.4))
    bmesh.ops.triangulate(bm, faces=bm.faces)
    M = Matrix.Translation(centre) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Translation((-R * 0.75, 0, 0))
    bm.transform(M)
    return keep(obj_from_bm(name, bm), False)


parts.append(honeycomb("Comb", (0.0, 0.42, b.H + 0.02), R=0.27, h=0.22, rot=(0.55, 0.0, 0.25)))

# ---- eye bumps + big eyes (froggo), amber irises
EZ, EU = 2.1, 0.72
for sd in (-1, 1):
    nm = f"Bump{'L' if sd < 0 else 'R'}"
    sphere = [(-0.56 * math.cos(k * math.pi / 9), 0.56 * math.sin(k * math.pi / 9)) for k in range(10)]
    bump = lathe(nm, sphere, along(Y, Y_L, (0, 0, EZ - 0.4), (0, 0, EZ + 0.5)), pos=(sd * EU, -0.28, EZ), axis=(0, -1, 0.35), segs=14)
    register(bump)
    parts.append(bump)
    u, v = sd * EU, EZ + 0.02
    parts.append(ddecal(f"EyeW{sd}", oval(u, v, 0.8, 0.8, n=14), WHITE, off=0.01, th=0.02, on=[nm], rings=2))
    parts.append(ddecal(f"Eye{sd}", oval(u + sd * 0.02, v - 0.03, 0.6, 0.62, n=14), INK, off=0.035, th=0.012, on=[nm], rings=2))
    parts.append(ddecal(f"Iris{sd}", oval(u + sd * 0.02, v - 0.05, 0.42, 0.44, n=12), IRIS, off=0.045, th=0.01, on=[nm], rings=1))
    parts.append(ddecal(f"Pupil{sd}", oval(u + sd * 0.02, v - 0.06, 0.2, 0.22, n=10), INK, off=0.052, th=0.008, on=[nm], rings=1))
    parts.append(ddecal(f"EyeHi{sd}", oval(u - 0.08, v + 0.1, 0.2, 0.17, n=8), WHITE, off=0.062, th=0.008, on=[nm], rings=1))
    # heavy happy lid line: a contented, greedy look
    parts.append(ddecal(f"Lid{sd}", arc(u, v - 0.12, 0.4, 35, 145, 0.07, n=8), K, off=0.07, th=0.01, on=[nm], rings=1))

# ---- haunches and front feet with toes (froggo), honey-dark
for sd in (-1, 1):
    parts.append(ball(f"Haunch{sd}", 0.6, (sd * 1.42, 0.35, 0.5), along(Y_D, Y, (0, 0, 0.0), (0, 0, 1.1)), squash=(0.75, 1.25, 0.85), rot=(0, 0, sd * 0.3)))
    fx = sd * 0.85
    parts.append(ball(f"Foot{sd}", 0.36, (fx, -1.18, 0.12), Y_D, squash=(1.2, 1.0, 0.42)))
    for k, dx in enumerate((-0.26, 0.0, 0.26)):
        parts.append(ball(f"Toe{sd}{k}", 0.12, (fx + dx, -1.5 + abs(dx) * 0.4, 0.1), Y, squash=(1, 1, 0.75), subdiv=1))


# ---- tiny glassy bee wings on the back (bumble)
def axes(x, y):
    x = Vector(x).normalized()
    y = Vector(y)
    return x, (y - x * y.dot(x)).normalized()


def wing_poly(Lw, W, n=7):
    pts = [(0.0, 0.0)]
    for k in range(1, n):
        t = math.pi * k / n
        pts.append((Lw * (0.5 - 0.5 * math.cos(t)) ** 0.8, W / 2 * math.sin(t) ** 1.2))
    pts.append((Lw, 0.0))
    for k in range(n - 1, 0, -1):
        t = math.pi * k / n
        pts.append((Lw * (0.5 - 0.5 * math.cos(t)) ** 0.8, -W / 2 * math.sin(t) ** 1.2 * 0.8))
    return pts


for sd in (-1, 1):
    for nm, Lw, W, root, xd, up in (("WingU", 1.0, 0.62, (sd * 0.35, 0.95, 1.95), (sd * 0.8, 0.55, 0.7), (0, -0.25, 1)),
                                     ("WingL", 0.7, 0.42, (sd * 0.4, 1.0, 1.75), (sd * 0.95, 0.6, 0.05), (0, -0.2, 1))):
        X, Yax = axes(xd, up)
        O = Vector(root)
        parts.append(puffy_slab(f"{nm}{sd}", wing_poly(Lw, W), 0.07, O, X, Yax, along(WING, WING_TIP, O, O + X * Lw, 1.3), rows=2))
        rim = [(x * 1.0 + (x - Lw * 0.5) * 0.06, y * 1.1) for x, y in wing_poly(Lw, W)]
        parts.append(slab(f"{nm}Rim{sd}", rim, 0.02, O, X, Yax, WING_RIM))

# ---- face: huge smile, tongue curling up to lick the honey off its lip
f = Face(b, eye_v=EZ, mouth_v=1.05)
MV = 1.16
f.d("Mouth", arc(0, MV + 0.62, 0.95, 222, 318, 0.085, n=12), MOUTH)
tongue = []
for k in range(13):  # curled tongue: from the right mouth corner up over the lip
    t = k / 12
    ang = math.radians(-70 + 200 * t)
    tongue.append((0.55 + math.cos(ang) * 0.25, MV + 0.07 + math.sin(ang) * 0.3))
tongue = [(0.52, MV - 0.08)] + tongue
f.d("Tongue", tongue, TONGUE, off=0.035, th=0.015)
f.d("TongueLine", rect(0.6, MV + 0.08, 0.035, 0.28, math.radians(-15)), shade(TONGUE, 0.72), off=0.055, th=0.008)
f.cheeks(u=0.98, v=1.32, w=0.36, h=0.18, color=hexc("ff8a6a"))
f.d("Nostril-1", oval(-0.13, 1.6, 0.07, 0.05, n=6), Y_D)
f.d("Nostril1", oval(0.13, 1.6, 0.07, 0.05, n=6), Y_D)
parts += f.parts
ship("slime_honey_toad", parts)
