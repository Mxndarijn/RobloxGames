# Robo (Legendary): chrome rounded-box robot goo, dark screen face with glowing cyan eyes and a pixel
# smile, antenna with red bulb, hex bolt ears, panel seams + rivets, gold wind-up key on the back.
from models._slimepool import *

CYAN, CYAN_L, CYAN_D = hexc("38f0ff"), hexc("d8ffff"), hexc("1890b8")
SCREEN, SCREEN_L = hexc("121a2e"), hexc("24345a")
BEZEL = hexc("4a5266")
SEAM = hexc("5a6478")
RED, RED_L = hexc("ff2a3a"), hexc("ffb0b0")
CHROME = [(0.0, hexc("4a5068")), (0.18, hexc("9aa6be")), (0.36, hexc("f0f4fa")), (0.46, hexc("3e4a68")),
          (0.6, hexc("6c7c9e")), (0.8, hexc("dfe7f4")), (1.0, hexc("ffffff"))]


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
        t = 0.5 - 0.5 * math.cos(math.pi * t)  # rows packed at the rounded ends
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


H = 2.95


def paint(a, z, p):
    c = ramp(CHROME, z / H)
    return mix(c, hexc("7f95c8"), 0.22 * (0.5 + 0.5 * math.sin(a * 2 + 0.6)))


def boxy(a, z):  # rounded-square cross-section (superellipse n=4)
    n = 4.0
    return 1.0 / (abs(math.cos(a)) ** n + abs(math.sin(a)) ** n) ** (1 / n) - 1.0


b = Body([(0, 1.15), (0.12, 1.36), (0.4, 1.42), (1.5, 1.42), (2.15, 1.3), (2.55, 1.0), (2.82, 0.52), (H, 0)],
         paint=paint, segs=36, sub=2, bump=lambda a, z: boxy(a, z) * 0.75, bands=[(0.56, 0.68, hexc("2ee4ff"))], gloss=1.0, shade=0.6)
parts = [b.obj]

# ---- screen face: bezel + dark glass, glowing eyes, pixel smile, glass glint
SV0, SV1 = 0.85, 2.15


def rr_w(v0, v1, hw, k=6):
    def f(v):
        t = min(1.0, abs((v - (v0 + v1) / 2) / ((v1 - v0) / 2)))
        return hw * (1 - t ** k) ** (1 / k) + 0.01
    return f


parts.append(proj_sheet("Bezel", rr_w(SV0 - 0.1, SV1 + 0.1, 1.12), SV0 - 0.1, SV1 + 0.1, 10, 6, 0.01, 0.03,
                        lambda p, n: mix(hexc("2e3446"), BEZEL, smoothstep(0.8, 2.2, p.z))))
screen = proj_sheet("Screen", rr_w(SV0, SV1, 1.0), SV0, SV1, 14, 9, 0.04, 0.02,
                    lambda p, n: mix(SCREEN, SCREEN_L, smoothstep(SV0, SV1, p.z) * 0.8))
parts.append(register(screen, "Screen"))


def sd_(name, poly, color, off):
    parts.append(decal(name, poly, color, FRONT, off=off, th=0.01, on=["Screen"]))


EV = 1.66
for sd in (-1, 1):
    u = sd * 0.46
    sd_(f"EyeGlow{sd}", oval(u, EV, 0.5, 0.62, n=18), CYAN_D, 0.01)
    sd_(f"Eye{sd}", oval(u, EV, 0.36, 0.48, n=16), CYAN, 0.02)
    sd_(f"EyeCore{sd}", oval(u - 0.05, EV + 0.08, 0.14, 0.18, n=10), CYAN_L, 0.03)
# pixel smile: little squares along an arc
for k in range(9):
    t = (k - 4) / 4
    x = t * 0.42
    y = 1.2 - 0.14 * (1 - t * t) + 0.02
    sd_(f"Px{k}", rect(x, y, 0.085, 0.085), CYAN, 0.02)
for sd in (-1, 1):
    sd_(f"Blush{sd}", rect(sd * 0.78, 1.32, 0.18, 0.06), hexc("ff5aa8"), 0.02)
    sd_(f"Blush2{sd}", rect(sd * 0.78, 1.42, 0.12, 0.05), hexc("ff5aa8"), 0.02)
sd_("Glint", [(-0.8, 2.0), (-0.6, 2.0), (-0.84, 1.6), (-0.9, 1.7)], hexc("5a6c98"), 0.015)

# ---- antenna with red bulb, base dome
parts.append(lathe("AntBase", [(0, 0.3), (0.1, 0.28), (0.18, 0.15), (0.2, 0)], zgrad(hexc("8a96ae"), WHITE, H - 0.05, H + 0.2),
                   pos=(0, 0, H - 0.06), segs=16))
parts.append(horn("AntRod", [(0, 0, H + 0.1), (0.05, 0.02, H + 0.5), (0.14, 0.05, H + 0.85)], [0.05, 0.04, 0.035], hexc("9aa6bc"), hexc("dfe6f0")))
parts.append(ball("Bulb", 0.23, (0.16, 0.05, H + 0.98), lambda p, n: mix(RED, RED_L, smoothstep(H + 0.9, H + 1.15, p.z) * 0.6)))
parts.append(torus("BulbRing", 0.1, 0.03, (0.15, 0.05, H + 0.82), (0.25, 0, 1), hexc("8a96ae"), segs=12, rsegs=4))

# ---- hex bolt ears
for sd in (-1, 1):
    p = b.point(math.radians(sd * 90), 1.75, -0.05)
    ax = (sd, 0, 0)
    parts.append(lathe(f"EarDisc{sd}", [(0, 0.38), (0.12, 0.38), (0.16, 0.32)], hexc("9aa6bc"), pos=tuple(p), axis=ax, segs=16))
    parts.append(lathe(f"EarHex{sd}", [(0, 0.24), (0.32, 0.24)], lambda q, n: mix(hexc("c8d0dc"), WHITE, 0.4 if n.z > 0.3 else 0.0),
                       pos=tuple(p + Vector(ax) * 0.14), axis=ax, segs=6, smooth=False))
    parts.append(lathe(f"EarBolt{sd}", [(0, 0.12), (0.12, 0.12), (0.16, 0)], GOLD, pos=tuple(p + Vector(ax) * 0.45), axis=ax, segs=10))

# ---- panel seams and rivets on the chrome
for k, yaw in enumerate((135, -135)):
    parts.append(decal(f"SeamV{k}", rect(0, 1.6, 0.07, 1.6), CYAN, frame_at(yaw, 0), off=0.01, th=0.012, on=["Body"], step=0.25))
for k in range(16):
    yaw = k * 22.5
    if abs(((yaw + 180) % 360) - 180) < 50:
        continue
    q = b.point(math.radians(yaw), 0.8, 0.0)
    parts.append(ball(f"Rivet{k}", 0.055, tuple(q), hexc("e8eef8"), subdiv=1))
parts.append(decal("Vent", rect(0, 2.42, 0.9, 0.05), SEAM, frame_at(180, 0), off=0.01, on=["Body"]))
for k in range(3):
    parts.append(decal(f"VentS{k}", rect(0, 2.2 - k * 0.14, 0.7, 0.06), SEAM, frame_at(180, 0), off=0.01, on=["Body"]))

# ---- gold wind-up key on the back
kp = b.point(math.pi, 1.45, 0.0)
parts.append(lathe("KeyShaft", [(-0.1, 0.09), (0.55, 0.08)], GOLD_D, pos=tuple(kp), axis=(0, 1, 0), segs=8))
parts.append(lathe("KeyCollar", [(0, 0.17), (0.12, 0.17)], GOLD, pos=tuple(kp + Vector((0, 0.08, 0))), axis=(0, 1, 0), segs=12))
for sd in (-1, 1):
    parts.append(torus(f"KeyLoop{sd}", 0.26, 0.075, tuple(kp + Vector((sd * 0.3, 0.62, 0))), (0, 1, 0),
                       lambda p, n: mix(GOLD, GOLD_L, smoothstep(1.2, 1.8, p.z)), segs=14, rsegs=5))
parts.append(ball("KeyHub", 0.12, tuple(kp + Vector((0, 0.62, 0))), GOLD))

# ---- chest buttons under the screen
for k, c in enumerate((hexc("ff3a4a"), hexc("ffd23a"), hexc("3aff7a"))):
    parts.append(decal(f"Btn{k}", oval((k - 1) * 0.26, 0.42, 0.17, 0.17, n=12), c, FRONT, off=0.02, th=0.05, on=["Body"]))
    parts.append(decal(f"BtnHi{k}", oval((k - 1) * 0.26 - 0.03, 0.45, 0.06, 0.06, n=8), WHITE, FRONT, off=0.075, th=0.006, on=["Body"]))

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_robo", parts)
