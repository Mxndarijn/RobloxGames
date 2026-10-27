# Sir Goo (Legendary, Classic): brave knight slime. Lime goo under a steel helmet (nasal guard,
# raised visor with a slit, red plume), a red round shield with a gold star emblem on its left,
# a steel sword held up by a goo hand on its right, a royal-blue cape, determined eyes.
from models._slimepool import *

GOO, GOO_D, GOO_L = hexc("7ee04c"), hexc("3a9e2a"), hexc("c8f78e")
STEEL, STEEL_D, STEEL_L = hexc("d2dcec"), hexc("8a96b0"), hexc("ffffff")
RED, RED_D, RED_L = hexc("ee2238"), hexc("a01028"), hexc("ff7080")
BLUE, BLUE_D, BLUE_L = hexc("2f5bff"), hexc("1a2c9c"), hexc("6f8fff")
LEATHER = hexc("6a3a1e")


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


KEY = Vector((-0.4, -0.6, 0.7)).normalized()


def metal(c0, c1, c2):
    """steel look: dark facing down/away from the key light, a bright sheen facing it."""
    def fn(p, n):
        k = n.dot(KEY)
        c = mix(c0, c1, smoothstep(-0.6, 0.2, k))
        return mix(c, c2, smoothstep(0.55, 0.95, k))
    return fn


def paint(a, z, p):
    c = mix(GOO_D, GOO, smoothstep(0.0, 1.3, z))
    return mix(c, GOO_L, 0.4 * smoothstep(0.6, 0.1, abs(a)) * smoothstep(1.3, 0.4, z))


b = Body([(0, 1.1), (0.14, 1.36), (0.5, 1.5), (1.1, 1.48), (1.8, 1.28), (2.4, 0.95), (2.78, 0.5), (2.9, 0)],
         paint=paint, segs=36, sub=2)
parts = [b.obj]
H = b.H

# ---- helmet: steel dome over the top of the head, thick rim, nasal guard, raised visor with a slit
HZ = 2.0
prof = [(HZ - 0.05, b.radius(HZ) + 0.1)]
for k in range(1, 9):
    z = HZ + (H - HZ) * k / 9
    prof.append((z, b.radius(z) + 0.11))
prof.append((H + 0.11, 0))
helm = lathe("Helmet", prof, metal(STEEL_D, STEEL, STEEL_L), segs=28)
parts.append(register(helm, "Helmet"))
parts.append(torus("HelmRim", b.radius(HZ) + 0.12, 0.09, (0, 0, HZ - 0.02), (0, 0, 1), metal(STEEL_D, STEEL, STEEL_L), segs=28, rsegs=5))
# nasal guard
parts.append(decal("Nasal", [(-0.08, 1.45), (0.08, 1.45), (0.11, 2.05), (-0.11, 2.05)], metal(STEEL_D, STEEL, STEEL_L), FRONT, off=0.03, th=0.06, on=["Body"]))
# visor: raised plate on the helmet front, a dark slit, rivets
vis = [(-0.78, 2.12), (0.78, 2.12), (0.7, 2.5), (0.3, 2.62), (-0.3, 2.62), (-0.7, 2.5)]
parts.append(decal("Visor", vis, metal(STEEL_D, mix(STEEL, STEEL_L, 0.3), WHITE), FRONT, off=0.03, th=0.07, on=["Helmet"]))
parts.append(decal("Slit", rect(0, 2.36, 1.1, 0.09), INK, FRONT, off=0.105, th=0.01, on=["Helmet"]))
for sd in (-1, 1):
    parts.append(decal(f"Rivet{sd}", oval(sd * 0.68, 2.22, 0.09, 0.09, n=8), GOLD, FRONT, off=0.105, th=0.02, on=["Helmet"]))

# ---- plume: gold holder on top, five red feather tubes sweeping up and back
top = Vector((0, 0.15, H + 0.08))
parts.append(lathe("PlumeHolder", [(0, 0.16), (0.22, 0.12), (0.3, 0.15), (0.34, 0)], zgrad(GOLD_D, GOLD_L, top.z, top.z + 0.34), pos=tuple(top), segs=10))


def feather_poly(L, w, n=6, bend=0.0):
    """soft feather along +x: narrow quill end, widest at ~60 %, round tip; bend curls it to +y."""
    top, bot = [], []
    for k in range(n + 1):
        t = k / n
        if t < 0.65:
            y = w / 2 * (0.35 + 0.65 * math.sin(math.pi / 2 * t / 0.65))
        else:
            q = (t - 0.65) / 0.35
            y = w / 2 * math.sqrt(max(0.0, 1 - q * q))
        c = bend * t * t * L
        top.append((t * L, c + y)); bot.append((t * L, c - y))
    return top + list(reversed(bot[1:-1]))


# fan of upright feathers in the y-z plane, curling back; front ones short, back ones long
for k, (deg, L, w, dx) in enumerate(((-6, 1.5, 0.6, 0.0), (12, 1.8, 0.62, 0.13), (12, 1.75, 0.6, -0.13), (32, 1.9, 0.62, 0.0), (52, 1.8, 0.58, 0.12), (52, 1.75, 0.58, -0.12), (74, 1.55, 0.5, 0.0))):
    th = math.radians(deg)
    d = Vector((dx * 1.4, math.sin(th), math.cos(th))).normalized()
    yv = Vector((0, math.cos(th), -math.sin(th)))  # +y in the feather = towards the back/down
    o = top + Vector((dx, 0, 0.2))
    tint = (RED_D, RED) if k % 2 == 0 else (mix(RED_D, RED, 0.5), RED_L)
    parts.append(puffy_slab(f"Plume{k}", feather_poly(L, w, bend=0.22), 0.26, tuple(o), tuple(d), tuple(yv),
                            along(tint[0], tint[1], o, o + d * L, power=0.8), rows=2))

# ---- cape: royal blue sheet behind, flaring to the floor, gold clasp chain at the front
A0, A1 = math.radians(100), math.radians(260)
CZ = 1.95


def cape_pt(s, t):
    a = A0 + (A1 - A0) * s
    z = CZ - t * (CZ - 0.05)
    flare = 0.08 + 0.32 * t ** 1.6
    wave = 0.07 * math.sin(s * math.tau * 3.0) * t ** 2
    p = b.point(a, max(z, 0.04), extra=flare + wave)
    return (p.x, p.y, z)


def cape_col(p, n):
    t = (CZ - p.z) / CZ
    a = math.atan2(p.x, -p.y)
    fold = 0.5 + 0.5 * math.cos(abs(a) * 6.0)
    return mix(BLUE, BLUE_D, 0.25 * fold + 0.35 * t)


parts.append(shell("Cape", cape_pt, 14, 6, 0.07, cape_col))
col_pts = [tuple(b.point(math.radians(a), CZ, 0.14)) for a in range(85, 280, 15)]
parts.append(horn("Collar", col_pts, [0.1] * len(col_pts), GOLD, GOLD, segs=6))
for sd in (-1, 1):
    p = b.point(math.radians(sd * 85), CZ, 0.2)
    d = Vector((p.x, p.y, 0)).normalized()
    parts.append(lathe(f"Clasp{sd}", [(0, 0.16), (0.07, 0.16), (0.1, 0)], GOLD, pos=tuple(p), axis=tuple(d), segs=12))

# ---- shield on its left (+X, viewer's right): red domed disc, gold rim + boss, gold star emblem
SY = 52
sd_ = Vector((math.sin(math.radians(SY)), -math.cos(math.radians(SY)), 0.0))
SC = b.point(math.radians(SY), 1.2, 0.0) + sd_ * 0.32
shield = lathe("Shield", [(0, 0.92), (0.1, 0.92), (0.2, 0.7), (0.26, 0.35), (0.28, 0)],
               lambda p, n: mix(RED_D, RED, smoothstep(-0.5, 0.5, n.dot(KEY))), pos=tuple(SC), axis=tuple(sd_), segs=24)
parts.append(register(shield, "Shield"))
parts.append(torus("ShieldRim", 0.9, 0.08, tuple(SC + sd_ * 0.1), tuple(sd_), metal(GOLD_D, GOLD, GOLD_L), segs=24, rsegs=5))
fr = frame_at(SY, SC.z, cx=SC.x, cy=SC.y)
parts.append(decal("Emblem", star(0, 0, 0.55, 0.24), GOLD, fr, off=0.01, th=0.05, on=["Shield"], step=0.08))
parts.append(decal("EmblemHi", star(-0.02, 0.03, 0.3, 0.13), GOLD_L, fr, off=0.06, th=0.01, on=["Shield"], step=0.08))

# ---- sword on its right (-X, viewer's left): goo hand, leather grip, gold guard, steel blade
HC = Vector((-1.8, -0.6, 1.1))
parts.append(goo("Arm", [((-1.25, -0.3, 1.1), 0.36, (1, 1, 0.9)), ((-1.55, -0.45, 1.1), 0.28), (tuple(HC), 0.27, (1.05, 1.1, 1.0))],
                 lambda p, n: mix(GOO_D, GOO, smoothstep(0.7, 1.4, p.z)), tris=240, resolution=0.08))
ax = Vector((-0.12, 0, 1)).normalized()
G = HC + ax * 0.32
parts.append(lathe("Grip", [(0, 0.075), (0.62, 0.075)], LEATHER, pos=tuple(HC - ax * 0.32), axis=tuple(ax), segs=8))
parts.append(ball("Pommel", 0.12, tuple(HC - ax * 0.38), GOLD))
gx = Vector((1, 0, 0.12)).normalized()
parts.append(horn("Guard", [tuple(G - gx * 0.5), tuple(G), tuple(G + gx * 0.5)], [0.09, 0.11, 0.09], GOLD, GOLD_L, segs=6))
for s in (-1, 1):
    parts.append(ball(f"GuardEnd{s}", 0.11, tuple(G + gx * 0.53 * s), GOLD, subdiv=1))
blade = lathe("Blade", [(0, 0.2), (1.7, 0.17), (2.1, 0)], metal(STEEL_D, STEEL, WHITE), pos=tuple(G + ax * 0.05), axis=tuple(ax), segs=6, sx=0.28, smooth=False)
parts.append(blade)

# ---- face: determined eyes with blue irises, low brave brows, confident grin
f = Face(b, eye_v=1.5, eye_u=0.5, mouth_v=0.95)
f.eyes("angry", w=0.46, h=0.6, iris=hexc("2f7bff"))
for sd in (-1, 1):
    f.d(f"Brow{sd}", rect(sd * 0.5, 1.88, 0.42, 0.1, math.radians(18 * sd)), INK)
f.mouth("grin", w=0.85)
f.cheeks(color=hexc("ff8fb0"), w=0.26, h=0.12)
parts += f.parts
if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_sir_goo", parts)
