# Constellation (Celestial, merge-only hybrid of Gaia + Abyss + Monarch): a living star map.
# Indigo-to-violet night-sky goo with a soft pink/cyan nebula swirl; big raised white stars joined
# by thick glowing lines into constellations on its sides; a gold star crown with a glowing flower
# star at the front (Gaia); a glowing lure-star dangling from the crown on a stalk (Abyss); two
# butterfly wings drawn as constellations on its back (Monarch); a gold orbit hoop carrying a
# crescent moon and stars; a dreamy, awed face with star-shaped eyes.
from models._slimepool import *
import random

# body: lifted indigo -> violet -> lavender (darks go near-black in game, so start high)
IND, VIO, LAV = hexc("5a54ec"), hexc("8460f6"), hexc("bca6ff")
NEB_P, NEB_C = hexc("f08ae8"), hexc("6ad8ff")
STAR_W, STAR_Y = hexc("ffffff"), hexc("ffe98a")
LINE, LINE_L = hexc("8ef0ff"), hexc("eafcff")
GOLD, GOLD_L, GOLD_D = hexc("ffd25a"), hexc("fff0b0"), hexc("f2b440")
INKC = hexc("1e1c5e")
KEY = Vector((-0.45, -0.6, 0.66)).normalized()


def paint(a, z, p):
    c = mix(IND, VIO, smoothstep(0.3, 2.2, z))
    c = mix(c, LAV, 0.55 * smoothstep(2.3, 3.0, z))
    w = noise.noise(Vector((p.x * 1.3, p.y * 1.3, p.z * 1.3 + 3.0)))
    face = smoothstep(1.2, 0.55, abs(a)) * smoothstep(0.7, 1.1, z) * smoothstep(2.5, 2.1, z)
    s1 = math.sin(2 * a + 2.6 * z + 2.2 * w)
    s2 = math.sin(2 * a - 2.4 * z + 1.0 + 2.2 * w)
    c = mix(c, NEB_P, 0.5 * smoothstep(0.55, 0.95, s1) * (1 - face))
    c = mix(c, NEB_C, 0.42 * smoothstep(0.6, 0.97, s2) * (1 - face))
    c = mix(c, LINE, 0.55 * smoothstep(0.3, 0.0, z))  # glowing foot
    return c


b = Body([(0, 1.05), (0.14, 1.36), (0.55, 1.54), (1.2, 1.53), (1.85, 1.31), (2.4, 0.95), (2.8, 0.47), (3.0, 0)],
         paint=paint, segs=30, sub=2, gloss=0.8, shade=0.5)
parts = [b.obj]
H = b.H


def surf_frame(a, z):
    """outward normal N, sideways X and up-the-surface Y at body point (a radians, z)."""
    p0 = b.point(a, z)
    ta = (b.point(a + 0.01, z) - b.point(a - 0.01, z)).normalized()
    tz = (b.point(a, z + 0.01) - b.point(a, z - 0.01)).normalized()
    N = ta.cross(tz).normalized()
    if N.dot(Vector((p0.x, p0.y, 0))) < 0:
        N = -N
    X = ta
    Y = N.cross(X).normalized()
    return p0, N, X, Y


def pstar(name, pos, N, X, r, thick=0.13, n=5, col=STAR_Y, rot=90):
    """raised puffy star facing N; white face, coloured tips."""
    X = (X - N * X.dot(N)).normalized()
    Y = N.cross(X).normalized()
    N2 = X.cross(Y)
    return puffy_slab(name, star(0, 0, r, r * (0.45 if n == 5 else 0.34), n=n, rot=rot), thick, pos, X, Y,
                      lambda p, nn: mix(col, STAR_W, 0.35 + 0.65 * max(0.0, nn.dot(N2))), rows=1)


def body_star(name, yaw, z, r):
    p0, N, X, Y = surf_frame(math.radians(yaw), z)
    return pstar(name, p0 + N * 0.03, N, X, r, thick=0.12, col=STAR_Y if r > 0.2 else hexc("e4f6ff"))


def body_line(name, p0, p1, r=0.06):
    a0, z0 = math.radians(p0[0]), p0[1]
    a1, z1 = math.radians(p1[0]), p1[1]
    L = math.hypot((a1 - a0) * 1.45, z1 - z0)
    n = max(3, int(L / 0.16) + 1)
    pts = [b.point(a0 + (a1 - a0) * k / (n - 1), z0 + (z1 - z0) * k / (n - 1), 0.03) for k in range(n)]
    o = tube(name, pts, [r] * n, None, segs=4, twist_free=True)
    paint_fn(o, lambda p, nn: mix(LINE, LINE_L, 0.3 + 0.7 * max(0.0, nn.dot(KEY))))
    return keep(o, True)


# ---------------------------------------------------------------- constellations on the sides (big stars, thick lines)
CONST = {
    "L": ([(-58, 0.75, 0.24), (-82, 1.35, 0.2), (-108, 0.9, 0.17), (-118, 1.7, 0.26), (-96, 2.2, 0.18)],
          [(0, 1), (1, 2), (1, 3), (3, 4)]),
    "R": ([(60, 1.05, 0.22), (84, 0.6, 0.18), (100, 1.4, 0.26), (124, 0.95, 0.18), (96, 2.15, 0.2)],
          [(0, 2), (1, 2), (2, 3), (2, 4)]),
    "B": ([(160, 0.55, 0.2), (180, 0.95, 0.24), (200, 0.55, 0.2)], [(0, 1), (1, 2)]),
}
for cname, (stars, edges) in CONST.items():
    for i, j in edges:
        parts.append(body_line(f"Line{cname}{i}{j}", stars[i][:2], stars[j][:2]))
    for k, (yaw, z, r) in enumerate(stars):
        parts.append(body_star(f"Star{cname}{k}", yaw, z, r * 1.25))

# tiny star specks
rng = random.Random(11)
k = 0
for i in range(7):
    yaw, z = rng.uniform(-180, 180), rng.uniform(0.4, 2.7)
    if abs(yaw) < 50 and 0.75 < z < 2.3:
        continue
    r = rng.uniform(0.04, 0.065)
    parts.append(decal(f"Speck{k}", oval(0, 0, r, r, n=6), STAR_W, frame_at(yaw, z), off=0.01, th=0.012, on=["Body"], step=0))
    k += 1

# ---------------------------------------------------------------- gold star crown (Gaia flower at the front)
ZC = 2.62
band = [b.point(i * math.tau / 26, ZC, 0.045) for i in range(27)]
o = tube("CrownBand", band, [0.08] * 27, None, segs=5, twist_free=True)
paint_fn(o, lambda p, n: mix(GOLD_D, GOLD_L, 0.35 + 0.65 * max(0.0, n.dot(KEY))))
parts.append(keep(o, True))
for j, yaw in enumerate((-40, 40, -90, 90, -140, 140, 180)):
    a = math.radians(yaw)
    p0, N, X, Y = surf_frame(a, ZC)
    r = 0.42 if abs(yaw) < 60 else (0.36 if abs(yaw) < 120 else 0.3)
    Nf = (Vector((N.x, N.y, 0)).normalized() * 0.95 + Vector((0, 0, 0.12))).normalized()  # flare out a little
    pos = p0 + Vector((N.x, N.y, 0)).normalized() * 0.06 + Vector((0, 0, r * 0.9))
    parts.append(pstar(f"CrownStar{j}", pos, Nf, X, r, thick=0.15, col=GOLD))

# Gaia: a glowing flower-star on the front of the crown, with two leaves
FC = b.point(0, ZC + 0.12, 0.2) + Vector((0, 0, 0.18))
FN = Vector((0, -1, 0.35)).normalized()
FX = Vector((1, 0, 0))
FY = FN.cross(FX).normalized()
PET, PET_L = hexc("ff9ad8"), hexc("fff0fa")
LEAF, LEAF_L = hexc("48d672"), hexc("a8f27a")
for sd in (-1, 1):
    leaf = [(0, 0), (0.25, 0.14), (0.55, 0.14), (0.78, 0.0), (0.55, -0.11), (0.25, -0.1)]
    lx = Vector((sd * 0.94, 0, 0.34)).normalized()
    parts.append(puffy_slab(f"Leaf{sd}", leaf, 0.07, FC + FN * -0.03, lx, FN.cross(lx).normalized() if sd > 0 else lx.cross(FN).normalized(),
                            lambda p, n: mix(LEAF, LEAF_L, smoothstep(-0.3, 0.6, n.z)), rows=1))
for i in range(5):
    ang = math.radians(90 + i * 72)
    du, dv = math.cos(ang), math.sin(ang)
    c = FC + FX * (du * 0.24) + FY * (dv * 0.24) + FN * 0.02
    px = FX * du + FY * dv
    parts.append(puffy_slab(f"Petal{i}", oval(0.0, 0, 0.4, 0.3, n=7), 0.09, c, px, FN.cross(px).normalized(),
                            lambda p, n: mix(PET, PET_L, 0.3 + 0.7 * max(0.0, n.dot(FN))), rows=1))
parts.append(pstar("FlowerStar", FC + FN * 0.09, FN, FX, 0.2, thick=0.1, col=STAR_Y))

# ---------------------------------------------------------------- Abyss: a lure-star on a stalk arching over the face
stalk = [Vector(q) for q in ((0, 0.25, H - 0.12), (0, 0.15, H + 0.45), (0, -0.25, H + 0.9), (0, -0.75, H + 1.02), (0, -1.08, H + 0.78))]
spts = stalk
o = horn("AntLure", [tuple(q) for q in spts], [0.09, 0.08, 0.07, 0.06, 0.05], hexc("8e80ff"), LINE, segs=6)
parts.append(o)
LP = spts[-1] + Vector((0, -0.02, -0.2))
parts.append(ball("AntLureOrb", 0.25, tuple(LP), along(hexc("5ee4ff"), STAR_W, LP - Vector((0, 0, 0.22)), LP + Vector((0, -0.1, 0.22))), subdiv=2))
parts.append(pstar("AntLureStar", LP + Vector((0, -0.2, 0)), Vector((0, -1, 0.1)), Vector((1, 0, 0)), 0.2, thick=0.08, n=4, col=STAR_W, rot=90))

# ---------------------------------------------------------------- Monarch: constellation butterfly wings on the back
FORE = [(0, 0.05), (0.5, 0.9), (1.35, 1.7), (2.3, 1.95), (2.62, 1.5), (2.3, 0.72), (1.3, 0.12)]
HIND = [(0, -0.05), (1.0, -0.12), (1.8, -0.55), (1.72, -1.2), (1.0, -1.5), (0.3, -1.0)]
WF0, WF1, WF2 = hexc("6ac8ff"), hexc("b49cff"), hexc("ff96e6")


def wing(tag, poly, origin, X, Y, S, stars_at, turn=-4.0):
    X, Y, O = Vector(X).normalized(), Vector(Y).normalized(), Vector(origin)
    Nw = X.cross(Y).normalized()
    ct, st = math.cos(math.radians(turn)), math.sin(math.radians(turn))
    P = [((x * ct - y * st) * S, (x * st + y * ct) * S) for x, y in poly]
    w3 = lambda q: O + X * q[0] + Y * q[1]
    rmax = max(math.hypot(*q) for q in P)

    def col(p, n):
        q = p - O
        t = math.hypot(q.dot(X), q.dot(Y)) / rmax
        c = mix(WF0, WF1, smoothstep(0.1, 0.55, t))
        return mix(c, WF2, smoothstep(0.55, 1.0, t))

    out = [slab(f"Wing{tag}", P, 0.07, O, X, Y, col, smooth=False)]
    for i in range(len(P)):
        j = (i + 1) % len(P)
        out.append(keep(tube(f"Wing{tag}Line{i}", [w3(P[i]), w3(P[j])], [0.05, 0.05], LINE_L, segs=4), True))
    for i in stars_at:
        r = 0.2 if i in stars_at[:2] else 0.15
        out.append(pstar(f"Wing{tag}Star{i}", w3(P[i]), Nw, X, r, thick=0.17, col=STAR_Y))
    # a couple of inner star dots on both faces
    cx = sum(q[0] for q in P) / len(P)
    cy = sum(q[1] for q in P) / len(P)
    out.append(pstar(f"Wing{tag}Mid", w3((cx, cy)), Nw, X, 0.13, thick=0.13, n=4, col=STAR_W))
    return out


SC = 0.98
for sd in (-1, 1):
    root = Vector((sd * 0.28, 1.05, 2.05))
    X = Vector((sd * math.cos(math.radians(10)), math.sin(math.radians(10)), 0.0))
    Yf = Vector((0, 0.25, 1))
    parts += wing(f"F{sd}", FORE, root, X, Yf, SC, [3, 2, 4, 5])
    parts += wing(f"H{sd}", HIND, root + Vector((0, 0.05, -0.05)), X, Yf, SC * 0.95, [3, 2, 4])

# ---------------------------------------------------------------- gold orbit hoop with a crescent moon and stars
OC = Vector((0, 0, 0.85))
on_ = Vector((0.3, -0.1, 1)).normalized()
OR = 2.15
oq = on_.to_track_quat("Z", "Y")
parts.append(torus("Orbit", OR, 0.07, OC, on_, lambda p, n: mix(GOLD_D, GOLD_L, 0.4 + 0.6 * max(0.0, n.dot(KEY))), segs=36, rsegs=5))


def on_orbit(t, lift=0.0):
    return OC + oq @ Vector((math.cos(t) * OR, math.sin(t) * OR, lift))


def crescent(r, n=14):
    """outer circle r minus a circle 0.8 r offset 0.45 r to +x: horns point to +x."""
    out = []
    for i in range(n + 1):  # outer arc, 52 -> 308 deg through 180
        a = math.radians(52 + 256 * i / n)
        out.append((math.cos(a) * r, math.sin(a) * r))
    for i in range(1, n):  # inner arc of the bite, 283 -> 77 deg back through 180
        a = math.radians(283 - 206 * i / n)
        out.append((math.cos(a) * r * 0.8 + r * 0.45, math.sin(a) * r * 0.8))
    return out


# find the orbit points by yaw
def t_at(yaw):
    best = min(range(360), key=lambda d: abs(((math.degrees(math.atan2(on_orbit(math.radians(d)).x, -on_orbit(math.radians(d)).y)) - yaw) + 180) % 360 - 180))
    return math.radians(best)


MOON = hexc("ffe27a")
mp = on_orbit(t_at(-52)) + Vector((0.0, -0.18, 0.3))
# a flat slab: puffy_slab fans to the centroid, which fills a crescent's bite
parts.append(slab("Moon", crescent(0.66), 0.22, mp, Vector((0.97, 0.25, 0)), Vector((0, 0.12, 1)),
                  lambda p, n: mix(hexc("ffcc3a"), hexc("fff3a0"), 0.25 + 0.75 * max(0.0, n.dot(KEY))), smooth=False))
for j, (yaw, r) in enumerate(((52, 0.26), (130, 0.22), (-140, 0.22))):
    q = on_orbit(t_at(yaw))
    out = Vector((q.x, q.y, 0)).normalized()
    parts.append(pstar(f"OrbStar{j}", q + out * 0.12, (out * 0.4 + Vector((0, -1, 0.2))).normalized(), Vector((1, 0, 0)), r, thick=0.13, col=STAR_Y))

# a few loose sparkles drifting round it
for j, (pos, r) in enumerate((((-1.95, -0.5, 2.85), 0.17), ((2.0, -0.45, 2.6), 0.15), ((1.15, -1.4, 3.4), 0.12))):
    parts.append(pstar(f"Spark{j}", Vector(pos), Vector((0, -1, 0.15)), Vector((1, 0, 0)), r, thick=0.07, n=4, col=STAR_W))

# ---------------------------------------------------------------- face: dreamy awed star eyes, small "o" mouth
f = Face(b, eye_u=0.52, eye_v=1.6, mouth_v=1.12, s=1.1, ink=INKC)
for sd in (-1, 1):
    u = sd * f.eu
    f.d(f"Eye{sd}", oval(u, f.ev, 0.58, 0.68, n=18), INKC, off=0.015)
    f.d(f"EyeC{sd}", star(u, f.ev + 0.02, 0.25, 0.11, n=5), STAR_Y, off=0.035, th=0.012)
    f.d(f"EyeHi{sd}", oval(u - 0.14, f.ev + 0.2, 0.12, 0.12, n=8), STAR_W, off=0.05, th=0.012)
    f.d(f"EyeHi2{sd}", oval(u + 0.15, f.ev - 0.2, 0.07, 0.07, n=8), LINE_L, off=0.05, th=0.012)
f.d("Mouth", oval(0, 1.12, 0.2, 0.24, n=14), INKC, off=0.015)
f.d("MouthIn", oval(0, 1.08, 0.12, 0.11, n=10), hexc("ff7ab8"), off=0.03, th=0.012)
f.cheeks(color=hexc("ff9ad8"), w=0.3, h=0.14)
parts += f.parts

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_constellation", parts)
