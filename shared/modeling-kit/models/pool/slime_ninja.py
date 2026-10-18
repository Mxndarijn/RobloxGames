# Ninja (Legendary): black goo, red headband with long flowing tails, face mask, fierce eyes,
# shuriken stuck in its side, katana across the back.
from models._slimepool import *

K0, K1, K2 = hexc("10111c"), hexc("1d2033"), hexc("383e62")
MASK, MASK_D = hexc("2a2d44"), hexc("15161f")
SKIN, SKIN_D = hexc("ffd9b8"), hexc("f0b896")
RED, RED_D, RED_L = hexc("ee2238"), hexc("a01028"), hexc("ff6070")
STEEL, STEEL_D, STEEL_L = hexc("b8c4d4"), hexc("6c7890"), hexc("f2f6ff")


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


def proj_sheet(name, half_w, v0, v1, nu, nv, off, th, color, on=("Body",)):
    """big front decal with interior verts (lib decal() has only boundary verts, so a wide one's flat
    triangles sink into a curved body): a grid projected along -Y, row width from half_w(v)."""
    def fn(s, t):
        v = v0 + (v1 - v0) * t
        hw = half_w(v)
        u = -hw + 2 * hw * s
        hit = cast(Vector((u, -12, v)), Vector((0, 1, 0)), list(on))
        if hit is None:
            raise ValueError(f"{name}: ({u:.2f}, {v:.2f}) misses")
        loc, n, _ = hit
        if n.y > 0:
            n = -n
        return tuple(loc + n * (off + th / 2))
    return shell(name, fn, nu, nv, th, color)


def paint(a, z, p):
    c = mix(K0, K1, smoothstep(0.0, 1.6, z))
    return mix(c, K2, 0.6 * smoothstep(2.2, 3.1, z))


b = Body([(0, 1.08), (0.14, 1.34), (0.5, 1.46), (1.1, 1.42), (1.8, 1.2), (2.45, 0.82), (2.9, 0.35), (3.08, 0)],
         paint=paint, segs=36, sub=2, lean=lambda z: 0.18 * max(0.0, (z - 2.2) / 0.9) ** 2)
parts = [b.obj]


def band(name, z0, z1, off, color, n=6, bulge=0.0):
    prof = []
    for k in range(n + 1):
        z = z0 + (z1 - z0) * k / n
        prof.append((z, b.radius(z) + off + bulge * math.sin(k / n * math.pi)))
    o = lathe(name, prof, color, segs=30, sx=b.sx, sy=b.sy)
    # follow the body lean
    for v in o.data.vertices:
        v.co.y += b.lean(v.co.z)
    return o


# ---- mask: cloth band over the lower face, a knot seam at the back
mask = register(band("Mask", 0.55, 1.36, 0.04, lambda p, n: mix(MASK_D, MASK, smoothstep(0.55, 1.34, p.z)), n=5, bulge=0.0))
parts.append(mask)
# register the mask so fold decals can hit it
# (registered before the decals below)

# ---- headband: red band, steel forehead plate, knot + two long flowing tails at the back
HZ0, HZ1 = 2.06, 2.42
parts.append(band("Headband", HZ0, HZ1, 0.05, lambda p, n: mix(RED_D, RED, smoothstep(HZ0, HZ1 - 0.1, p.z)), n=4, bulge=0.02))
plate = [(-0.42, 2.12), (0.42, 2.12), (0.46, 2.36), (-0.46, 2.36)]
parts.append(decal("Plate", plate, zgrad(STEEL_D, STEEL_L, 2.1, 2.4), FRONT, off=0.07, th=0.05, on=["Body"]))
for sd in (-1, 1):
    parts.append(decal(f"Rivet{sd}", oval(sd * 0.36, 2.24, 0.07, 0.07, n=8), STEEL_D, FRONT, off=0.125, th=0.01, on=["Body"]))
parts.append(decal("Emblem", star(0, 2.24, 0.1, 0.045, n=4, rot=45), K0, FRONT, off=0.125, th=0.01, on=["Body"]))

kp = b.point(math.pi, 2.24, 0.12)
parts.append(ball("Knot", 0.17, tuple(kp), RED, squash=(1.2, 0.9, 1)))
for sd in (-1, 1):
    parts.append(ball(f"Loop{sd}", 0.15, tuple(kp + Vector((sd * 0.22, 0.02, 0.06))), RED_D, squash=(1.3, 0.7, 0.9)))


def tail_fn(sd, L, drop, phase):
    def fn(s, t):
        # centreline flows back and out, waving; t spans the ribbon width (mostly vertical)
        x = sd * (0.15 + 1.75 * s ** 0.8 + 0.14 * math.sin(s * 5.0 + phase))
        y = kp.y + 0.05 + L * s
        z = kp.z - drop * s ** 1.4 + 0.24 * math.sin(s * 4.2 + phase) * s
        w = 0.5 * (1 - 0.25 * s)
        notch = 0.0
        if s > 0.92:  # forked end
            notch = (s - 0.92) / 0.08 * 0.16 * (1 - abs(t - 0.5) * 2)
        return (x, y - notch, z + (t - 0.5) * w)
    return fn


def tail_col(p, n):
    s = min(1, max(0, (p.y - kp.y) / 1.6))
    return mix(RED, RED_D, 0.6 * s)


parts.append(shell("TailL", tail_fn(1, 1.0, 0.55, 0.0), 20, 2, 0.06, tail_col))
parts.append(shell("TailR", tail_fn(-1, 0.85, 1.0, 1.6), 18, 2, 0.06, tail_col))

# ---- katana across the back (handle over the right shoulder), shuriken in the left side
ex = 0.12
while True:
    A = b.point(math.radians(208), 2.55, ex) + Vector((0, 0, 0.0))
    B = b.point(math.radians(138), 0.75, ex)
    ok = True
    for k in range(11):
        q = A + (B - A) * (k / 10)
        if math.hypot(q.x, q.y - b.lean(q.z)) < b.radius(q.z) + 0.16:
            ok = False
    if ok:
        break
    ex += 0.03
d = (B - A).normalized()
A = A - d * 0.55  # handle pokes up over the shoulder
parts.append(lathe("Scabbard", [(0, 0.12), (2.3, 0.11), (2.5, 0.07), (2.55, 0)], lambda p, n: mix(hexc("1e2130"), hexc("3a3050"), 0.5),
                   pos=tuple(A + d * 0.75), axis=tuple(d), segs=8, sx=1.0, sy=0.7))
parts.append(lathe("Guard", [(0, 0.22), (0.07, 0.22)], GOLD, pos=tuple(A + d * 0.68), axis=tuple(d), segs=10))
parts.append(lathe("Hilt", [(0, 0.09), (0.66, 0.08)], RED_D, pos=tuple(A + d * 0.02), axis=tuple(d), segs=8))
for k in range(4):
    parts.append(torus(f"Wrap{k}", 0.085, 0.025, tuple(A + d * (0.12 + k * 0.15)), tuple(d), K0, segs=10, rsegs=4))
parts.append(ball("Pommel", 0.11, tuple(A), GOLD, squash=(1, 1, 1)))

sp = b.point(math.radians(-100), 1.2, -0.05)
sn = (sp - Vector((0, 0, sp.z))).normalized()
up = Vector((0.15, 0, 1)).normalized()
ux = up.cross(sn).normalized()
uy = sn.cross(ux).normalized()
shur = []
for k in range(8):
    a = math.radians(k * 45 + 15)
    r = 0.62 if k % 2 == 0 else 0.17
    shur.append((math.cos(a) * r, math.sin(a) * r))
parts.append(slab("Shuriken", shur, 0.06, tuple(sp + sn * 0.22), tuple(ux), tuple(uy), STEEL))
parts.append(lathe("ShurHub", [(-0.06, 0.1), (0.06, 0.1)], STEEL_D, pos=tuple(sp + sn * 0.22), axis=tuple(ux.cross(uy)), segs=10))

# ---- eye window (skin) between headband and mask, fierce slanted eyes + angry brows
WV0, WV1 = 1.24, 2.12
def win_w(v):
    t = min(1.0, abs((v - (WV0 + WV1) / 2) / ((WV1 - WV0) / 2)))
    return 1.02 * (1 - t ** 4) ** 0.25 + 0.01
parts.append(proj_sheet("Window", win_w, WV0, WV1, 14, 6, 0.012, 0.015, lambda p, n: mix(SKIN_D, SKIN, smoothstep(1.3, 2.0, p.z))))
f = Face(b, eye_v=1.68, eye_u=0.46)
f.eyes("angry", w=0.47, h=0.56, iris=hexc("e8243c"))
f.brows("angry", w=0.34, th=0.08, lift=-0.17)
parts += f.parts
if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_ninja", parts)
