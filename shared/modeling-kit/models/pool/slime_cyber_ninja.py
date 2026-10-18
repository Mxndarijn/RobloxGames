# Cyber Ninja (hybrid, tier 6: robo + ninja + zap): chrome-black ninja goo. Metal face mask with a
# glowing red visor slit, neon cyan headband with long flowing tails, a bare neon katana across the
# back with yellow sparks crackling on it, cyan circuit traces, hex-bolt visor hinges and a little
# comm antenna (robo), a lightning emblem (zap).
from models._slimepool import *

CYAN, CYAN_L, CYAN_D = hexc("2ef2ff"), hexc("d4ffff"), hexc("0a7fb0")
RED, RED_L, RED_D, RED_G = hexc("ff1a2e"), hexc("ffd0d4"), hexc("8a0010"), hexc("ff5a40")
BOLT, BOLT_L = hexc("ffe02a"), hexc("fff6a0")
PINK = hexc("ff2a78")
GLASS, GLASS_L = hexc("06070d"), hexc("1c2236")
STEEL_D, STEEL, STEEL_L = hexc("3a4258"), hexc("8a96b0"), hexc("eef2fa")
# chrome-black: dark gunmetal with sharp light bands (robo's chrome ramp, darkened)
CHROME_K = [(0.0, hexc("07080e")), (0.2, hexc("1a1e2c")), (0.36, hexc("4e5874")), (0.44, hexc("0c0e16")),
            (0.62, hexc("1e2336")), (0.82, hexc("5c6886")), (1.0, hexc("6a7698"))]


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
    """big front decal with interior verts: a grid projected along -Y, row width from half_w(v)."""
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


def ramp(stops, t):
    t = min(1.0, max(0.0, t))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return mix(c0, c1, smoothstep(t0, t1, t))
    return stops[-1][1]


H = 3.1


def paint(a, z, p):
    c = ramp(CHROME_K, z / H)
    return mix(c, hexc("3a4a8a"), 0.25 * (0.5 + 0.5 * math.sin(a * 2 + 0.6)))


def boxy(a, z):  # a touch of robo's rounded-square section
    n = 3.0
    return 1.0 / (abs(math.cos(a)) ** n + abs(math.sin(a)) ** n) ** (1 / n) - 1.0


b = Body([(0, 1.08), (0.14, 1.36), (0.5, 1.48), (1.1, 1.44), (1.8, 1.22), (2.45, 0.84), (2.9, 0.36), (H, 0)],
         paint=paint, segs=36, sub=2, gloss=1.0, shade=0.55, bump=lambda a, z: boxy(a, z) * 0.35,
         lean=lambda z: 0.16 * max(0.0, (z - 2.2) / 0.9) ** 2)
parts = [b.obj]


def band(name, z0, z1, off, color, n=6, bulge=0.0, segs=36):
    prof = []
    for k in range(n + 1):
        z = z0 + (z1 - z0) * k / n
        prof.append((z, b.radius(z) + off + bulge * math.sin(k / n * math.pi)))
    o = lathe(name, prof, color, segs=segs)
    # follow the body lean and the boxy section
    for v in o.data.vertices:
        a = math.atan2(v.co.x, -v.co.y)
        r = math.hypot(v.co.x, v.co.y)
        z = v.co.z
        k = (b.radius(z) * (1 + b.bump(a, z)) + (r - b.radius(z))) / max(r, 1e-6)
        v.co.x *= k
        v.co.y = v.co.y * k + b.lean(z)
    return o


def stroke(pts, widths):
    L, R = [], []
    n = len(pts)
    for i in range(n):
        a, c = Vector(pts[max(i - 1, 0)]), Vector(pts[min(i + 1, n - 1)])
        t = (c - a).normalized()
        nn = Vector((-t.y, t.x))
        p = Vector(pts[i])
        L.append(tuple(p + nn * widths[i] / 2)); R.append(tuple(p - nn * widths[i] / 2))
    return L + list(reversed(R))


# ---- metal mask over the lower face (chrome plate), cyan vent grin
MZ0, MZ1 = 0.5, 1.36
mask_col = lambda p, n: ramp([(0, hexc("10131e")), (0.35, hexc("262c44")), (0.62, hexc("7c88aa")), (0.7, hexc("c8d2ea")),
                              (0.8, hexc("2e3654")), (1, hexc("181c2c"))], (p.z - MZ0) / (MZ1 - MZ0))
mask = register(band("Mask", MZ0, MZ1, 0.045, mask_col, n=6, segs=28), "Mask")
parts.append(mask)
parts.append(band("MaskLip", MZ1 - 0.035, MZ1 + 0.035, 0.075, CYAN, n=1, segs=30))
# vent grin: slots in a smirk arc
for k in range(7):
    t = (k - 3) / 3
    x = t * 0.48
    y = 0.98 - 0.1 * (1 - t * t) + 0.05 * t
    parts.append(decal(f"Vent{k}", rect(x, y, 0.1, 0.22, math.radians(-8 * t)), hexc("05060a"), FRONT, off=0.02, th=0.012, on=["Mask"]))
    parts.append(decal(f"VentG{k}", rect(x, y, 0.055, 0.16, math.radians(-8 * t)), CYAN_L if k == 3 else CYAN, FRONT, off=0.035, th=0.01, on=["Mask"]))
parts.append(decal("MaskSeam", rect(0, 0.72, 0.04, 0.34), hexc("2a3044"), FRONT, off=0.02, th=0.01, on=["Mask"]))
for sd in (-1, 1):
    parts.append(decal(f"MaskRivet{sd}", oval(sd * 0.82, 0.78, 0.09, 0.09, n=8), STEEL_L, FRONT, off=0.02, th=0.03, on=["Mask"]))

# ---- visor: dark glass band between mask and headband, the red slit glowing in it
VV0, VV1 = 1.34, 2.08


def vis_w(v):
    t = min(1.0, abs((v - (VV0 + VV1) / 2) / ((VV1 - VV0) / 2)))
    return 1.12 * (1 - t ** 6) ** (1 / 6) + 0.01


visor = proj_sheet("Visor", vis_w, VV0, VV1, 10, 6, 0.02, 0.03, lambda p, n: mix(GLASS, GLASS_L, smoothstep(VV0, VV1, p.z) * 0.9))
parts.append(register(visor, "VisorGlass"))


def vd(name, poly, color, off, th=0.01):
    parts.append(decal(name, poly, color, FRONT, off=off, th=th, on=["VisorGlass"]))


EV = 1.7


def slit(w0, w1, dv):
    """V-shaped slit across the visor: dips in the middle (a frown of focus), widths per point."""
    pts, ws = [], []
    for k in range(17):
        t = (k - 8) / 8
        pts.append((t * 0.98, EV + dv + 0.16 * abs(t) ** 1.3 - 0.02))
        ws.append(w0 + (w1 - w0) * (1 - abs(t)) ** 0.5)
    return pts, ws


p, w = slit(0.22, 0.3, 0.0)
vd("EyeGlow", stroke(p, w), RED_D, 0.01)
p, w = slit(0.1, 0.15, 0.0)
vd("EyeSlit", stroke(p, w), RED, 0.02)
for sd in (-1, 1):  # the two eyes: hot lozenges inside the slit
    u = sd * 0.44
    v = EV + 0.16 * abs(u / 0.98) ** 1.3 - 0.02
    ang = math.radians(sd * 17)
    vd(f"Eye{sd}", [(u + math.cos(ang) * dx - math.sin(ang) * dy, v + math.sin(ang) * dx + math.cos(ang) * dy)
                   for dx, dy in ((-0.28, 0), (-0.14, 0.1), (0.28, 0.085), (0.19, -0.09), (-0.14, -0.09))], RED_G, 0.03)
    vd(f"EyeCore{sd}", oval(u, v, 0.28, 0.08, n=10, rot=ang), RED_L, 0.04)
vd("Glint", [(-0.82, 2.0), (-0.66, 2.0), (-0.84, 1.52), (-0.88, 1.6)], hexc("3a4668"), 0.015)

# ---- visor hinges: robo hex bolt "ears" at the visor ends
for sd in (-1, 1):
    hp = b.point(math.radians(sd * 88), 1.72, -0.04)
    ax = Vector((sd, -0.12, 0)).normalized()
    parts.append(lathe(f"HingeDisc{sd}", [(0, 0.3), (0.1, 0.3), (0.14, 0.24)], STEEL, pos=tuple(hp), axis=tuple(ax), segs=14))
    parts.append(lathe(f"HingeHex{sd}", [(0, 0.19), (0.2, 0.19)], lambda q, n: mix(STEEL, STEEL_L, 0.5 if n.z > 0.3 else 0.1),
                       pos=tuple(hp + ax * 0.12), axis=tuple(ax), segs=6, smooth=False))
    parts.append(lathe(f"HingeCore{sd}", [(0, 0.09), (0.06, 0.09), (0.08, 0)], CYAN, pos=tuple(hp + ax * 0.31), axis=tuple(ax), segs=10))

# ---- neon cyan headband, chrome plate with a lightning emblem, knot + two long glowing tails
HZ0, HZ1 = 2.08, 2.42
parts.append(band("Headband", HZ0, HZ1, 0.05, lambda p, n: mix(CYAN_D, CYAN, smoothstep(HZ0, HZ1 - 0.12, p.z)), n=3, bulge=0.02, segs=30))
parts.append(band("HeadbandLine", HZ0 + 0.13, HZ0 + 0.2, 0.08, CYAN_L, n=1, segs=28))
plate = [(-0.42, 2.12), (0.42, 2.12), (0.46, 2.38), (-0.46, 2.38)]
parts.append(decal("Plate", plate, zgrad(STEEL_D, STEEL_L, 2.1, 2.42), FRONT, off=0.09, th=0.05, on=["Body"]))
bolt = [(-0.05, 0.5), (0.25, 0.5), (0.08, 0.1), (0.3, 0.1), (-0.15, -0.55), (0.0, -0.08), (-0.22, -0.08)]
parts.append(decal("Emblem", [(x * 0.22, 2.25 + y * 0.22) for x, y in bolt], BOLT, FRONT, off=0.145, th=0.012, on=["Body"], step=0.05))
for sd in (-1, 1):
    parts.append(decal(f"Rivet{sd}", oval(sd * 0.36, 2.25, 0.06, 0.06, n=8), STEEL_D, FRONT, off=0.145, th=0.01, on=["Body"]))

kp = b.point(math.pi, 2.25, 0.12)
parts.append(ball("Knot", 0.17, tuple(kp), CYAN, squash=(1.2, 0.9, 1)))
for sd in (-1, 1):
    parts.append(ball(f"Loop{sd}", 0.15, tuple(kp + Vector((sd * 0.22, 0.02, 0.06))), CYAN_D, squash=(1.3, 0.7, 0.9)))


def tail_fn(sd, L, drop, phase, spread):
    def fn(s, t):
        x = sd * (0.15 + spread * s ** 0.8 + 0.14 * math.sin(s * 5.0 + phase))
        y = kp.y + 0.05 + L * s
        z = kp.z - drop * s ** 1.4 + 0.26 * math.sin(s * 4.2 + phase) * s
        w = 0.48 * (1 - 0.3 * s)
        notch = 0.0
        if s > 0.9:  # forked end
            notch = (s - 0.9) / 0.1 * 0.18 * (1 - abs(t - 0.5) * 2)
        return (x, y - notch, z + (t - 0.5) * w)
    return fn


def tail_col(p, n):
    s = min(1, max(0, (p.y - kp.y) / 1.5))
    c = mix(CYAN, hexc("1a6cff"), 0.75 * s)
    return mix(c, CYAN_L, 0.0)


parts.append(shell("TailL", tail_fn(1, 1.05, 0.5, 0.0, 1.85), 20, 2, 0.06, tail_col))
parts.append(shell("TailR", tail_fn(-1, 0.9, 0.95, 1.6, 1.6), 18, 2, 0.06, tail_col))

# ---- bare neon katana across the back (hilt over the right shoulder), yellow sparks on the blade
ex = 0.16
while True:
    A = b.point(math.radians(208), 2.6, ex)
    B = b.point(math.radians(138), 0.7, ex)
    ok = True
    for k in range(11):
        q = A + (B - A) * (k / 10)
        if math.hypot(q.x, q.y - b.lean(q.z)) < b.radius(q.z) * 1.12 + 0.12:
            ok = False
    if ok:
        break
    ex += 0.03
d = (B - A).normalized()
A = A - d * 0.6
blade0 = A + d * 0.78
blade_col = lambda p, n: mix(CYAN_L, CYAN, 0.35 + 0.65 * smoothstep(0.0, 0.25, abs(n.dot(d.cross(Vector((0, 1, 0))).normalized()))))
parts.append(lathe("Blade", [(0, 0.1), (2.2, 0.1), (2.55, 0.05), (2.75, 0)], lambda p, n: mix(WHITE, PINK, 0.45),
                   pos=tuple(blade0), axis=tuple(d), segs=6, sx=1.0, sy=0.28, smooth=False))
parts.append(lathe("BladeGlow", [(0.05, 0.16), (2.1, 0.16), (2.5, 0.08), (2.72, 0)], lambda p, n: mix(PINK, hexc("c0105a"), 0.3),
                   pos=tuple(blade0 + Vector((0, 0.03, 0))), axis=tuple(d), segs=6, sx=1.0, sy=0.12, smooth=False))
parts.append(lathe("Guard", [(0, 0.24), (0.08, 0.24)], STEEL_L, pos=tuple(A + d * 0.7), axis=tuple(d), segs=6, smooth=False))
parts.append(lathe("Hilt", [(0, 0.09), (0.68, 0.08)], RED_D, pos=tuple(A + d * 0.02), axis=tuple(d), segs=8))
for k in range(3):
    parts.append(torus(f"Wrap{k}", 0.085, 0.025, tuple(A + d * (0.15 + k * 0.19)), tuple(d), hexc("101420"), segs=8, rsegs=3))
parts.append(ball("Pommel", 0.11, tuple(A), PINK))
side = d.cross(Vector((0, 1, 0))).normalized()
for k, (t, o, r) in enumerate(((1.2, 0.28, 0.1), (1.9, -0.26, 0.08), (2.6, 0.24, 0.09), (3.1, -0.22, 0.07))):
    parts.append(gem(f"Spark{k}", tuple(A + d * t + side * o + Vector((0, 0.05, 0))), r, BOLT if k % 2 == 0 else BOLT_L, segs=4))

# ---- comm antenna (robo) on the left side of the head, red bulb
ab = b.point(math.radians(-38), 2.55, -0.04)
parts.append(lathe("AntBase", [(0, 0.15), (0.08, 0.13), (0.12, 0)], STEEL, pos=tuple(ab), axis=(-0.4, -0.1, 1), segs=10))
parts.append(horn("AntRod", [tuple(ab), tuple(ab + Vector((-0.12, -0.02, 0.45))), tuple(ab + Vector((-0.3, 0.02, 0.85)))],
                  [0.04, 0.035, 0.03], STEEL, STEEL_L, segs=6))
parts.append(ball("AntBulb", 0.13, tuple(ab + Vector((-0.33, 0.02, 0.95))), lambda p, n: mix(RED, RED_L, 0.4 * max(0.0, n.z))))

# ---- cyan circuit traces on the sides and back (short segments so they hug the body), node dots
def circuit(name, yaw, pts, wdt=0.05):
    fr = frame_at(yaw, 0)
    for i in range(len(pts) - 1):
        a, c = Vector(pts[i]), Vector(pts[i + 1])
        L = (c - a).length
        m = (a + c) / 2
        ang = math.atan2(c.y - a.y, c.x - a.x)
        parts.append(decal(f"{name}S{i}", rect(m.x, m.y, L + wdt, wdt, ang), CYAN, fr, off=0.012, th=0.012, on=["Body"], step=0.3))
    for k, q in enumerate((pts[0], pts[-1])):
        parts.append(decal(f"{name}N{k}", oval(q[0], q[1], 0.13, 0.13, n=8), CYAN_L, fr, off=0.016, th=0.014, on=["Body"]))


for sd in (-1, 1):
    circuit(f"CirA{sd}", sd * 100, [(sd * -0.35, 0.25), (sd * -0.35, 0.45), (sd * -0.1, 0.45), (sd * 0.1, 0.65), (sd * 0.1, 1.05)])
    circuit(f"CirB{sd}", sd * 125, [(0, 0.3), (0, 0.55), (sd * 0.25, 0.75), (sd * 0.25, 1.15), (sd * 0.05, 1.35)])
    circuit(f"CirC{sd}", sd * 45, [(sd * 0.2, 2.5), (sd * 0.0, 2.65), (sd * -0.18, 2.65)])
# neon crest line over the dome (seen from above / the hero view), from headband to headband
for k in range(7):
    y = -0.72 + k * 0.25
    parts.append(decal(f"Crest{k}", rect(0, y, 0.09, 0.27), CYAN, TOP, off=0.012, th=0.014, on=["Body"], step=0.3))
parts.append(decal("CrestDot", oval(0, 0.05, 0.2, 0.2, n=10), CYAN_L, TOP, off=0.02, th=0.014, on=["Body"]))
circuit("CirD", 180, [(-0.3, 0.3), (-0.3, 0.6), (0.0, 0.85), (0.0, 1.3)])

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_cyber_ninja", parts)
