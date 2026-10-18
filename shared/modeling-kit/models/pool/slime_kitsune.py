# Kitsune (Secret): nine-tailed spirit fox slime. A white fox slime with red shrine-fox markings
# (forehead flame, eyeliner flicks, hikimayu brow dots, cheek stripes), tall red-tipped fox ears,
# a red-and-white fox mask tilted on its head, two blue fox-fire wisps floating beside it and the
# showpiece: NINE big flowing tails fanned out behind it like a peacock, each ending in a blue
# spirit flame. Tails are Tail1..Tail9 so the rig wags each with its own phase.
from models._slimepool import *

FUR, FUR_SH, FUR_W = hexc("fffbf6"), hexc("efe2f0"), hexc("fff3e6")
TAIL_R = hexc("cfd0f4")
RED, RED_D = hexc("ff2a3c"), hexc("c0102a")
SP_D, SP, SP_L, SP_W = hexc("1d3cff"), hexc("1e9bff"), hexc("62e6ff"), hexc("e6fdff")
GOLD_I = hexc("ffbf2a")


# ---- local helper: big decals that follow the curve (copied from slime_moo.py grid_decal)
def _inside(pt, poly):
    x, y = pt
    c = False
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            c = not c
    return c


def grid_decal(name, poly, color, frame=FRONT, off=0.008, th=0.012, on=None, step=0.08, cell=0.12):
    from mathutils.geometry import delaunay_2d_cdt
    poly = densify(poly, step)
    n = len(poly)
    us, vs = [p[0] for p in poly], [p[1] for p in poly]
    inner = []
    u = min(us) + cell / 2
    while u < max(us):
        v = min(vs) + cell / 2
        while v < max(vs):
            if _inside((u, v), poly) and min((u - a) ** 2 + (v - b) ** 2 for a, b in poly) > (cell * 0.45) ** 2:
                inner.append((u, v))
            v += cell
        u += cell
    pts = [Vector(p) for p in poly + inner]
    V2, _, F, *_ = delaunay_2d_cdt(pts, [(i, (i + 1) % n) for i in range(n)], [list(range(n))], 1, 1e-6)
    F = [f for f in F if _inside(tuple(sum((V2[i] for i in f), Vector((0, 0))) / len(f)), poly)]
    bm = bmesh.new()
    top, bot = {}, {}
    for f in F:
        for i in f:
            if i in top:
                continue
            uu, vv = V2[i]
            hit = cast(frame.O + frame.U * uu + frame.V * vv + frame.D * 12, -frame.D, on)
            if hit is None:
                raise ValueError(f"grid_decal {name}: ({uu:.2f}, {vv:.2f}) misses every surface")
            loc, nn, _ = hit
            if nn.dot(frame.D) < 0:
                nn = -nn
            nn = (nn * 0.6 + frame.D * 0.4).normalized()
            bot[i] = bm.verts.new(loc + nn * off)
            top[i] = bm.verts.new(loc + nn * (off + th))
    ecount = {}
    for f in F:
        bm.faces.new([top[i] for i in f])
        bm.faces.new([bot[i] for i in reversed(f)])
        for a, b_ in zip(f, f[1:] + f[:1]):
            ecount[(a, b_)] = ecount.get((a, b_), 0) + 1
    for (a, b_) in ecount:
        if (b_, a) not in ecount:
            bm.faces.new((bot[a], bot[b_], top[b_], top[a]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, False)


def cat3(pts, n):
    """Catmull-Rom through 3D points, n samples per segment."""
    P = [Vector(p) for p in pts]
    P = [P[0]] + P + [P[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return out


def sweep_tail(name, path, radius, colfn, segs=10, flat=0.7, up=Vector((0, 1, 0))):
    """closed tapered sweep: elliptic rings (wide in the fan plane, `flat` x as thick), both ends
    close to a point. radius(t) per ring, colfn(t, ang, p) per vertex."""
    n = len(path)
    L = [0.0]
    for p, q in zip(path, path[1:]):
        L.append(L[-1] + (q - p).length)
    bm = bmesh.new()
    rings, meta = [], {}
    for i in range(1, n - 1):
        T = (path[i + 1] - path[i - 1]).normalized()
        A = T.cross(up)
        if A.length < 1e-4:
            A = Vector((1, 0, 0))
        A.normalize()
        B = A.cross(T).normalized()
        t = L[i] / L[-1]
        r = radius(t)
        ring = []
        for k in range(segs):
            a = k * math.tau / segs
            v = bm.verts.new(path[i] + A * math.cos(a) * r + B * math.sin(a) * r * flat)
            meta[v] = (t, a)
            ring.append(v)
        rings.append(ring)
    for a, b_ in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b_[(k + 1) % segs], b_[k]))
    v0, v1 = bm.verts.new(path[0]), bm.verts.new(path[-1])
    meta[v0], meta[v1] = (0.0, 0.0), (1.0, 0.0)
    for k in range(segs):
        bm.faces.new((rings[0][(k + 1) % segs], rings[0][k], v0))
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % segs], v1))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            t, a = meta[lp.vert]
            lp[col] = colfn(t, a, lp.vert.co)
    return keep(obj_from_bm(name, bm), True)


def body_paint(a, z, p):
    c = mix(FUR_SH, FUR, smoothstep(0.1, 1.2, z))
    f = smoothstep(0.9, 0.3, abs(a)) * smoothstep(1.5, 0.6, z)
    return mix(c, FUR_W, 0.5 * f)


def fluff(a, z):
    # fur tufts on the cheeks: a zig-zag ruff low on the sides
    ad = abs(math.degrees(a))
    side = smoothstep(40, 70, ad) * smoothstep(125, 95, ad)
    zz = smoothstep(0.55, 0.9, z) * smoothstep(1.6, 1.2, z)
    return 0.07 * side * zz * (0.5 + 0.5 * math.cos((z - 0.9) * math.tau / 0.28))


b = Body([(0, 1.12), (0.14, 1.42), (0.5, 1.58), (1.1, 1.55), (1.75, 1.3), (2.35, 0.86), (2.75, 0.4), (2.92, 0)],
         paint=body_paint, bump=fluff, segs=34, sub=2, sy=0.96, gloss=0.5)
parts = [b.obj]
H = b.H

# ---------------------------------------------------------------- nine tails (the showpiece)
ROOT = Vector((0, 0.8, 1.3))
ANGLES = [-68, -51, -34, -17, 0, 17, 34, 51, 68]


def tail_col(t, a, p, base=FUR):
    # white fur -> blue spirit-flame tip with a flickering (tongued) boundary
    tb = 0.76 + 0.035 * math.sin(a * 3)
    c = mix(TAIL_R, base, smoothstep(0.25, 0.7, t))
    c = mix(c, SP_L, smoothstep(tb, tb + 0.1, t))
    c = mix(c, SP, smoothstep(tb + 0.12, tb + 0.24, t))
    c = mix(c, SP_D, smoothstep(0.88, 1.0, t))
    return c


def tail_radius(t, big=1.0):
    return 0.13 + 0.5 * big * math.sin(math.pi * min(1.0, t ** 1.3)) ** 0.8


for k, th in enumerate(ANGLES):
    back = k % 2 == 0  # 5 back-layer tails, 4 front-layer tails between them
    Lt = (3.55 if back else 3.15) * (1 - 0.06 * abs(th) / 72)
    side = 0 if th == 0 else (1 if th > 0 else -1)
    r = math.radians(th)
    D = Vector((math.sin(r), 0, math.cos(r)))
    Pp = Vector((math.cos(r), 0, -math.sin(r))) * (side if side else 1)
    yb = 0.3 if back else -0.05
    ctrl = []
    for t in (0.0, 0.25, 0.5, 0.75, 1.0):
        off = Lt * (-0.04 * math.sin(math.pi * t) + 0.09 * t ** 2.5) * (1 if side else 0.4)
        y = yb + Lt * (0.24 * t - 0.07 * t * t)
        ctrl.append(ROOT + D * (Lt * t) + Pp * off + Vector((0, y, 0)))
    path = cat3(ctrl, 4)
    parts.append(sweep_tail(f"Tail{k + 1}", path, lambda t, big=(1.0 if back else 0.85): tail_radius(t, big), (tail_col if back else (lambda t, a, p: tail_col(t, a, p, hexc("fff1e2")))), segs=9, flat=0.68))
    # spirit-flame wisp leaving the tip, curling further outward
    tip = path[-1]
    tdir = (path[-1] - path[-3]).normalized()
    fp = [tip - tdir * 0.3, tip + tdir * 0.05, tip + tdir * 0.3 + Pp * 0.05, tip + tdir * 0.58 - Pp * 0.03]
    parts.append(horn(f"Flame{k + 1}", fp, [0.22, 0.2, 0.1, 0.01], SP, SP_W, segs=7))

# ---------------------------------------------------------------- fox ears (red tips + red inner)
for sd in (-1, 1):
    base = b.point(math.radians(sd * 30), 2.48, -0.12)
    X = Vector((sd * 0.38, -0.05, 1.0)).normalized()
    Yl = Vector((1, 0, 0))
    Yl = (Yl - X * Yl.dot(X)).normalized()
    ear = [(0, -0.4), (0.4, -0.36), (0.82, -0.18), (1.12, 0), (0.82, 0.18), (0.4, 0.36), (0, 0.4)]
    tipc = base + X * 1.1
    parts.append(puffy_slab(f"Ear{sd}", ear, 0.24, base, X, Yl,
                            lambda p, n, base=base, X=X: mix(FUR, RED, smoothstep(0.72, 0.86, (p - base).dot(X))), rows=2))
    N = X.cross(Yl).normalized()
    if N.y > 0:
        N = -N
    inner = [(0.12, -0.24), (0.45, -0.21), (0.82, -0.08), (0.95, 0), (0.82, 0.08), (0.45, 0.21), (0.12, 0.24)]
    parts.append(slab(f"EarIn{sd}", inner, 0.04, base + N * 0.13, X, Yl, hexc("ff7a8c")))

# ---------------------------------------------------------------- fox mask tilted on the head (-X side)
ma = math.radians(-74)
mc = b.point(ma, 2.0, 0.14)
nrm = (Vector((math.sin(ma), -math.cos(ma), 0)) * 0.75 + Vector((0, -0.35, 0.4))).normalized()
MX = Vector((0, 0, 1))
MX = (MX - nrm * MX.dot(nrm)).normalized()
roll = math.radians(-28)
MY = nrm.cross(MX).normalized()
MX, MY = (MX * math.cos(roll) + MY * math.sin(roll)), (MY * math.cos(roll) - MX * math.sin(roll))
# mask outline in (x up, y lateral): two ear points, cheeks, snout down
MS = 1.3
mask = [(x * MS, y * MS) for x, y in [(0.62, -0.42), (0.3, -0.36), (0.05, -0.42), (-0.25, -0.3), (-0.48, -0.12), (-0.58, 0), (-0.48, 0.12),
        (-0.25, 0.3), (0.05, 0.42), (0.3, 0.36), (0.62, 0.42), (0.42, 0.18), (0.4, 0), (0.42, -0.18)]]
mo = puffy_slab("Mask", mask, 0.16, mc, MX, MY, lambda p, n: mix(hexc("fffdf8"), RED, smoothstep(0.5, 0.62, (p - mc).dot(MX) / MS)), rows=2)
parts.append(mo)
register(mo, "Mask")
_mn = MX.cross(MY).normalized()
_mn = _mn if _mn.dot(nrm) > 0 else -_mn
parts.append(slab("MaskRim", [(x * 1.1 - 0.03, y * 1.12) for x, y in mask], 0.06, mc - _mn * 0.06, MX, MY, RED))
# markings on the mask, projected from outside along its normal
mN = MX.cross(MY).normalized()
if mN.dot(nrm) < 0:
    mN = -mN
mf = Frame(mc, MY, MX, mN)
_S = MS


def ms(poly):
    return [(x * _S, y * _S) for x, y in poly]
for sd in (-1, 1):
    parts.append(decal(f"MaskEye{sd}", ms(arc(sd * 0.17, 0.02, 0.1, 200, 340, 0.05, n=6)), RED, mf, off=0.005, th=0.015, on=["Mask"]))
    parts.append(decal(f"MaskEar{sd}", ms([(sd * 0.36, 0.5), (sd * 0.22, 0.32), (sd * 0.36, 0.28)]), RED, mf, off=0.005, th=0.015, on=["Mask"]))
    parts.append(decal(f"MaskCheek{sd}", ms(rect(sd * 0.2, -0.2, 0.14, 0.035, math.radians(sd * 15))), RED, mf, off=0.005, th=0.015, on=["Mask"]))
parts.append(decal("MaskBrow", ms([(0, 0.3), (0.06, 0.16), (0, 0.1), (-0.06, 0.16)]), RED, mf, off=0.005, th=0.015, on=["Mask"]))
parts.append(decal("MaskNose", ms(oval(0, -0.47, 0.1, 0.07, n=8)), INK, mf, off=0.005, th=0.015, on=["Mask"]))
# red cord over the head to the mask
parts.append(horn("Cord", [mc + mN * 0.02 + MY * 0.3 + MX * 0.1, b.point(math.radians(-20), 2.75, 0.03), b.point(math.radians(40), 2.6, 0.03)],
                  [0.035, 0.035, 0.035], RED_D, RED, segs=5))

# ---------------------------------------------------------------- fox-fire wisps floating beside it
def wisp(nm, base, lean):
    ctrl = [base, base + Vector((0, 0, 0.3)), base + Vector((lean * 0.1, 0, 0.62)), base + Vector((lean * 0.32, 0, 0.9)),
            base + Vector((lean * 0.55, 0, 1.0)), base + Vector((lean * 0.7, 0, 0.9))]
    path = cat3(ctrl, 3)
    key = Vector((-0.45, -1.0, 0.3)).normalized()
    core = base + Vector((0, 0, 0.3))
    o = sweep_tail(nm, path, lambda t: 0.36 * math.sin(math.pi * min(1.0, t ** 0.55)) ** 0.7 * (1 - 0.6 * t) + 0.015,
                   lambda t, a, p: SP, segs=10, flat=1.0)
    paint_fn(o, lambda p, n: mix(mix(SP_W, SP, smoothstep(0.15, 0.55, (p - core).length)), SP_D, smoothstep(0.6, 1.0, (p - core).length))
             if n.dot(key) > -2 else SP)
    return o


parts.append(wisp("Wisp1", Vector((-2.15, -0.55, 1.15)), -1))
parts.append(wisp("Wisp2", Vector((2.1, -0.35, 1.7)), 1))
# little embers drifting off the wisps
for k, (pos, r) in enumerate((((-2.55, -0.6, 2.35), 0.07), ((-1.75, -0.7, 2.05), 0.05), ((2.65, -0.4, 2.9), 0.07), ((1.8, -0.5, 2.75), 0.05))):
    parts.append(ball(f"Ember{k}", r, pos, SP_L, subdiv=1))

# ---------------------------------------------------------------- face + red shrine-fox markings
EV, MV = 1.5, 1.08
f = Face(b, eye_u=0.5, eye_v=EV, mouth_v=MV)
f.eyes("sly", w=0.5, h=0.62, iris=GOLD_I)
for sd in (-1, 1):
    u = sd * 0.5
    # red eyeliner flick from the outer corner, up and out
    f.d(f"Liner{sd}", [(u + sd * 0.16, EV + 0.02), (u + sd * 0.44, EV + 0.22), (u + sd * 0.3, EV - 0.06)], RED, off=0.014)
    # hikimayu brow dot
    f.d(f"BrowDot{sd}", oval(sd * 0.36, EV + 0.48, 0.17, 0.11, n=12, rot=math.radians(-sd * 15)), RED, off=0.014)
    # cheek stripes (shrine-fox whisker marks)
    for j, (dv, ang) in enumerate(((0.06, 12), (-0.07, -4))):
        f.d(f"Stripe{sd}{j}", [(sd * 0.84, EV - 0.32 + dv + 0.035), (sd * 1.16, EV - 0.32 + dv + ang * 0.004 * 1),
                               (sd * 0.84, EV - 0.32 + dv - 0.035)], RED, off=0.014)
f.mouth("cat", w=1.0)
parts += f.parts
# forehead flame mark
flame = [(0, EV + 0.95), (0.07, EV + 0.75), (0.12, EV + 0.6), (0.06, EV + 0.5), (0, EV + 0.47), (-0.06, EV + 0.5),
         (-0.12, EV + 0.6), (-0.07, EV + 0.75)]
parts.append(decal("Mark", flame, RED, FRONT, off=0.014, on=["Body"]))
ship("slime_kitsune", parts)
