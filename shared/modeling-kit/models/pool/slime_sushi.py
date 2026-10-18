# Sushi (Rare hybrid: mochi + chomp + sprout): a nigiri slime. Wide, soft rice body (mochi's squish)
# with lumpy grains and a dark nori belt, a glossy striped salmon slab draped over the top ending in a
# fish tail (chomp), a sprout-leaf garnish with wasabi (sprout), chopsticks stuck in, happy ^^ grin.
from models._slimepool import *

RICE, RICE_D, GRAIN = hexc("fbf8f0"), hexc("e6dccb"), hexc("ffffff")
NORI, NORI_L = hexc("1e2e26"), hexc("3a5446")
SAL, SAL_D, SAL_L, FAT = hexc("ff8650"), hexc("f05a30"), hexc("ffa878"), hexc("fff2e6")
WOOD, WOOD_D, LACQ = hexc("f0c88a"), hexc("c8945a"), hexc("e02a36")
LEAF, LEAF_L, WASABI, WASABI_L = hexc("3fb83a"), hexc("8ff05a"), hexc("8ccf3a"), hexc("c8f070")
PINK, PINK_D = hexc("ffa6c4"), hexc("ff6f9c")

BAND = (0.42, 0.98)


def nzv(p, s):
    return noise.noise(Vector((p.x * s, p.y * s, p.z * s)))


def paint(a, z, p):
    c = mix(RICE_D, RICE, smoothstep(0.0, 0.9, z))
    return mix(c, RICE_D, 0.5 * max(0.0, nzv(p, 5.0)))


def bump(a, z):
    p = Vector((math.sin(a) * 1.5, math.cos(a) * 1.5, z))
    return 0.03 * nzv(p, 4.5) * (0.3 if BAND[0] - 0.05 < z < BAND[1] + 0.05 else 1.0)


PROF = [(0, 1.42), (0.08, 1.54), (0.3, 1.6), (1.2, 1.58), (1.6, 1.48), (1.88, 1.22), (2.04, 0.8), (2.12, 0.3), (2.14, 0)]
b = Body(PROF, paint=paint, bump=bump, sx=1.04, sy=0.86, segs=40, sub=2, gloss=0.35,
         bands=[(BAND[0], BAND[1], NORI)])
parts = [b.obj]

# rice grains: little raised ovals all over the white parts (face area kept clear)
grains = []
for k in range(44):
    yaw = (k * 137.5 + 13 * math.sin(k * 1.7)) % 360
    z = 0.12 + ((k * 0.7548 + 0.3 * math.sin(k * 2.9)) % 1.0) * 1.85
    if BAND[0] - 0.12 < z < BAND[1] + 0.1:
        continue
    if abs(((yaw + 180) % 360) - 180) < 50 and z > 0.95:
        continue
    grains.append((yaw, z, 0.17, 0.08, (k * 53) % 180))
parts += spots(b, grains, GRAIN, n=6, off=0.008, th=0.025)
# nori sheen: a lighter diagonal stripe pair on the belt
for k, yaw in enumerate((-60, 60, 150, -150)):
    parts.append(decal(f"NoriHi{k}", rect(0, 0, 0.07, 0.42, math.radians(25)), NORI_L, frame_at(yaw, 0.7), off=0.006, th=0.008, on=["Body"]))


# ---- salmon slab draped over the top: closed thick sheet following the rice surface
def top_z(x, y):
    """height of the rice surface's upper part above (x, y); droops past the edge."""
    rho = math.hypot(x / b.sx, y / b.sy)
    up = [(z, r) for z, r in b.prof if z > 1.0]
    for (z0, r0), (z1, r1) in zip(up, up[1:]):
        if r1 <= rho <= r0:
            return z0 + (z1 - z0) * (r0 - rho) / max(r0 - r1, 1e-9)
    if rho < up[-1][1]:
        return b.H
    return up[0][0] - (rho - up[0][1]) * 1.5


SX0, SX1, SY0, SY1 = -1.42, 1.42, -0.8, 1.25


def sal_pt(s, t, side):
    x = SX0 + (SX1 - SX0) * s
    y = SY0 + (SY1 - SY0) * t
    # rounded slab outline: pinch the corners
    e = (2 * s - 1) ** 2, (2 * t - 1) ** 2
    x *= 1 - 0.1 * e[1]
    y *= 1 - 0.08 * e[0]
    dome = 0.32 * (1 - e[0] ** 1.5) * (1 - e[1] ** 2) + 0.08
    z = top_z(x, y) + 0.03
    return Vector((x, y, z + (dome if side > 0 else 0.0)))


def salmon(nu=16, nv=12):
    bm = bmesh.new()
    top = [[bm.verts.new(sal_pt(i / nu, j / nv, 1)) for j in range(nv + 1)] for i in range(nu + 1)]
    bot = [[bm.verts.new(sal_pt(i / nu, j / nv, -1)) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
            bm.faces.new((bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j], bot[i][j]))
    for i in range(nu):
        for j in (0, nv):
            bm.faces.new((top[i][j], bot[i][j], bot[i + 1][j], top[i + 1][j]))
    for j in range(nv):
        for i in (0, nu):
            bm.faces.new((top[i][j], top[i][j + 1], bot[i][j + 1], bot[i][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm("Salmon", bm)

    def col(p, n):
        c = mix(SAL_D, SAL, smoothstep(1.6, 2.3, p.z))
        d = (p - Vector((0, 0, 1.4))).normalized()
        h = max(0.0, d.dot(Vector((-0.45, -0.55, 0.7)).normalized()))
        return mix(c, WHITE, 0.6 * smoothstep(0.93, 0.985, h))
    paint_fn(o, col)
    return keep(o, True)


sal = salmon()
register(sal)
parts.append(sal)
# white fat lines: gently curved diagonal strokes projected from above
for k in range(6):
    x0 = -1.5 + k * 0.5
    pts = [(x0 + 0.5 * t + 0.08 * math.sin(t * math.pi), -0.75 + 1.95 * t) for t in [i / 8 for i in range(9)]]
    pts = [(x, y) for x, y in pts if abs(x) < 1.3 * (1 - 0.1 * ((y - 0.22) / 1.0) ** 2) and -0.72 < y < 1.18]
    if len(pts) < 3:
        continue
    w = 0.09
    poly = [(x - w / 2, y) for x, y in pts] + [(x + w / 2, y) for x, y in reversed(pts)]
    parts.append(decal(f"Fat{k}", poly, FAT, TOP, off=0.006, th=0.012, on=["Salmon"], step=None))

# fish tail (chomp's crescent) flicking up at the back end of the slab
tail = [(0, -0.22), (0.4, -0.38), (0.82, -0.62), (0.62, -0.14), (0.56, 0.08), (0.74, 0.48), (0.92, 0.82),
        (0.48, 0.42), (0, 0.24)]
tz = top_z(0, SY1) + 0.12
parts.append(puffy_slab("Tail", tail, 0.2, (0, SY1 - 0.15, tz), (0, 1, 0.35), (0, -0.35, 1),
                        lambda p, n: mix(SAL_D, SAL_L, smoothstep(tz - 0.4, tz + 0.7, p.z))))

# chopsticks stuck in at the back right, crossing
for k, (base, tip) in enumerate((((0.55, 0.55, 2.0), (1.55, 1.5, 3.7)), ((0.85, 0.35, 2.0), (2.0, 0.85, 3.45)))):
    B, T = Vector(base), Vector(tip)
    m = B + (T - B) * 0.72
    parts.append(horn(f"Stick{k}", [tuple(B), tuple(m)], [0.055, 0.075], WOOD_D, WOOD, segs=6))
    parts.append(horn(f"StickEnd{k}", [tuple(m), tuple(T)], [0.077, 0.085], LACQ, LACQ, segs=6))

# sprout garnish + wasabi on the front-left of the slab
gp = sal_pt(0.2, 0.3, 1) + Vector((0, 0, -0.02))
wp = sal_pt(0.62, 0.22, 1) + Vector((0, 0, -0.04))
parts.append(goo("Wasabi", [(tuple(wp + Vector((0.0, 0.0, 0.06))), 0.26, (1, 1, 0.6)), (tuple(wp + Vector((0.03, 0.03, 0.22))), 0.15)],
                 zgrad(WASABI, WASABI_L, wp.z, wp.z + 0.35), tris=120, resolution=0.06))
leaf = [(0, 0)] + [(0.34 + 0.36 * math.cos(t), 0.26 * math.sin(t) * (1 - 0.35 * math.cos(t))) for t in [math.pi - k * math.tau / 14 for k in range(1, 14)]]
lp = gp + Vector((0.05, 0.1, 0.3))
for sd in (-1, 1):
    X = Vector((sd, -0.2, 0.6)).normalized()
    parts.append(puffy_slab(f"Leaf{sd}", leaf, 0.09, tuple(lp), X, (0, math.cos(math.radians(40)), math.sin(math.radians(40))),
                            along(LEAF, LEAF_L, lp, lp + X * 0.7)))

# pink pickled-ginger rosette at the foot (mochi pink)
gpos = b.point(math.radians(-62), 0.15, 0.1)
for k in range(5):
    a = k * math.tau / 5
    d = Vector((math.cos(a), math.sin(a), 0))
    parts.append(ball(f"Ginger{k}", 0.2, tuple(gpos + d * 0.14 + Vector((0, 0, 0.12 + 0.04 * (k % 2)))),
                      lambda p, n: mix(PINK_D, PINK, smoothstep(0.0, 0.35, p.z)), squash=(1, 0.55, 0.7), rot=(0.4, 0, a), subdiv=1))

# ---- face: happy ^^ eyes, big open grin, mochi blush
f = Face(b, eye_u=0.62, eye_v=1.52, mouth_v=1.16, s=1.3)
f.eyes("happy").mouth("grin", w=0.9).cheeks(color=PINK_D, w=0.34, h=0.16, u=1.08, v=1.3)
parts += f.parts
ship("slime_sushi", parts)
