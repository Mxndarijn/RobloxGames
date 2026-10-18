# Bloom (Rare hybrid: sprout + mushie + bumble). Flower slime: a fresh green jelly sitting in a big
# cupped blossom of pink petals (mushie's polka dots on them), a golden pollen crown, sprout leaves at
# its feet, a tiny bee looping round it on a dotted flight path, and dreamy sparkle eyes.
from models._slimepool import *

G_D, G, G_L = hexc("3aa83a"), hexc("6fdc4a"), hexc("c8f27a")
POLLEN, POLLEN_D = hexc("ffd23a"), hexc("f09a1a")
PET, PET_D, PET_L, PET_IN = hexc("ff7ab8"), hexc("e8408e"), hexc("ffd0e6"), hexc("fff4f8")
PET2, PET2_D = hexc("ff4f9a"), hexc("c81e70")
LEAF, LEAF_L = hexc("2fae3a"), hexc("8ff05a")
BEE_Y, BEE_K = hexc("ffd02a"), hexc("2a2230")


def paint(a, z, p):
    c = mix(G_D, G, smoothstep(0.2, 1.4, z))
    c = mix(c, G_L, 0.45 * smoothstep(1.6, 2.6, z))
    return mix(c, POLLEN, smoothstep(2.42, 2.55, z))  # golden pollen crown


b = Body([(0, 0.95), (0.12, 1.22), (0.5, 1.38), (1.1, 1.36), (1.7, 1.18), (2.2, 0.86), (2.55, 0.45), (2.72, 0.1), (2.74, 0)],
         paint=paint, segs=32, sub=2, gloss=0.7)
parts = [b.obj]

# pollen grains on the crown
for k in range(6):
    a = k * 2.4
    rr = 0.12 + 0.36 * math.sqrt(k / 6)
    x, y = math.sin(a) * rr, -math.cos(a) * rr
    zz = b.H - 0.02 - 0.5 * rr * rr
    parts.append(ball(f"Pollen{k}", 0.075, (x, y + 0.05, zz + 0.03), POLLEN_D if k % 2 else hexc("ffb020"), subdiv=1))


# cupped petals: puffy slab bent upward towards its tip
def petal_poly(L, W, n=14):
    """round-tipped teardrop: narrow root at (0, 0), widest near 2/3 of the length."""
    pts = []
    for k in range(n):
        t = math.tau * k / n
        u = (1 - math.cos(t)) / 2  # 0 at root, 1 at tip
        pts.append((L * u, W / 2 * math.sin(t) * u ** 0.45))
    return pts


def petal(name, yaw, z, L, W, tilt, cup, col0, col1, colin, thick=0.12):
    a = math.radians(yaw)
    out = Vector((math.sin(a), -math.cos(a), 0))
    X = (out * math.cos(math.radians(tilt)) + Vector((0, 0, math.sin(math.radians(tilt))))).normalized()
    Y = Vector((math.cos(a), math.sin(a), 0))
    O = b.point(a, z, -0.25)
    o = puffy_slab(name, petal_poly(L, W), thick, O, X, Y, (0, 0, 0, 1), rows=2)
    N = X.cross(Y)
    for v in o.data.vertices:
        d = (v.co - O).dot(X) / L
        s = (v.co - O).dot(Y) / (W / 2)
        v.co += Vector((0, 0, 1)) * cup * d * d + N * 0.0 + Vector((0, 0, 1)) * 0.12 * cup * s * s
    def col(p, n):
        d = min(1.0, max(0.0, (p - O).dot(X) / L))
        c = mix(colin, col0, smoothstep(0.05, 0.5, d))
        return mix(c, col1, smoothstep(0.55, 1.0, d))
    paint_fn(o, col)
    register(o)
    FR[name] = (O, X, Y, L, cup, W)
    return o


FR = {}


petals = []
# back/outer ring: 8 big pink petals
def back(yaw):  # 0 at the front, 1 at the back: petals stand taller behind the face
    return 0.5 - 0.5 * math.cos(math.radians(yaw))


for k in range(8):
    yaw = k * 45
    petals.append(petal(f"Petal{k}", yaw, 0.38, 1.6, 1.3, 16 + 30 * back(yaw), 0.42 + 0.2 * back(yaw), PET, PET_D, PET_IN))
# inner ring: 8 smaller hot-pink petals between, steeper
for k in range(8):
    yaw = k * 45 + 22.5
    petals.append(petal(f"PetalIn{k}", yaw, 0.5, 1.15, 0.95, 30 + 30 * back(yaw), 0.3, PET2, PET2_D, PET, thick=0.1))
parts += petals

# mushie's polka dots on the big petals, projected along each petal's own normal
for k in range(8):
    nm = f"Petal{k}"
    O, X, Y, L, cup, W = FR[nm]
    N = X.cross(Y).normalized()
    if N.z < 0:
        N = -N
    for j, (d, sv, w) in enumerate(((0.55, 0.2, 0.2), (0.74, -0.14, 0.14))):
        c = O + X * (d * L) + Vector((0, 0, 1)) * cup * d * d
        fr = Frame(c + Y * sv, Y, N.cross(Y), N)
        parts.append(decal(f"Dot{k}{j}", oval(0, 0, w, w, n=6), WHITE, fr, off=0.012, th=0.02, on=[nm]))

# sprout leaves at its feet (sprout DNA)
leaf = [(0, 0)] + [(0.55 + 0.6 * math.cos(t), 0.4 * math.sin(t) * (1 - 0.35 * math.cos(t))) for t in [math.pi - k * math.tau / 10 for k in range(1, 10)]]
for k, yaw in enumerate((-125, 125, 180)):
    a = math.radians(yaw)
    X = Vector((math.sin(a), -math.cos(a), 0.18)).normalized()
    O = Vector((math.sin(a) * 1.15, -math.cos(a) * 1.15, 0.1))
    parts.append(puffy_slab(f"Leaf{k}", leaf, 0.12, O, X, (math.cos(a), math.sin(a), 0), along(LEAF, LEAF_L, O, O + X * 1.15), rows=2))

# tiny bee looping round the flower, with a dotted flight path (bumble DNA)
BEE = Vector((1.55, -0.95, 3.15))


def bee_col(p, n):
    q = p - BEE
    return BEE_K if (-0.11 < q.x < -0.02) or (0.08 < q.x < 0.15) else BEE_Y


parts.append(ball("Bee", 0.25, tuple(BEE), bee_col, squash=(1.3, 1.0, 1.0)))
parts.append(lathe("BeeSting", [(0, 0.07), (0.14, 0)], BEE_K, pos=tuple(BEE + Vector((0.3, 0, 0))), axis=(1, 0, 0), segs=6))
for sd in (-1, 1):
    wing = [(0, 0)] + [(0.2 + 0.2 * math.cos(t), 0.14 * math.sin(t)) for t in [math.pi - k * math.tau / 10 for k in range(1, 10)]]
    parts.append(puffy_slab(f"BeeWing{sd}", wing, 0.04, BEE + Vector((0.02, sd * 0.06, 0.18)), (0.25, sd * 0.55, 0.85), (1, 0, 0),
                            along(WHITE, hexc("a8e2ff"), BEE, BEE + Vector((0, 0, 0.5))), rows=1))
for sd in (-1, 1):  # eyes on the front (-x side faces the flower)
    parts.append(ball(f"BeeEye{sd}", 0.05, tuple(BEE + Vector((-0.3, -0.12 + sd * 0.0 + (sd * 0.1), 0.06))), BEE_K, subdiv=1))
for sd in (-1, 1):
    parts.append(horn(f"BeeAnt{sd}", [tuple(BEE + Vector((-0.2, sd * 0.08, 0.18))), tuple(BEE + Vector((-0.3, sd * 0.14, 0.38)))],
                      [0.02, 0.018], BEE_K, BEE_K, segs=4))
for k in range(6):  # dotted loop trail behind it
    t = k / 6
    ang = math.radians(-20 - 150 * t)
    pt = Vector((math.cos(ang) * 1.9, math.sin(ang) * 1.3 - 0.2, 3.05 - 0.55 * t + 0.25 * math.sin(t * math.pi)))
    if k == 0:
        continue
    parts.append(ball(f"Trail{k}", 0.055, tuple(pt), WHITE, subdiv=1))

f = Face(b, eye_u=0.5, eye_v=1.8, mouth_v=1.38)
f.eyes("sparkle", w=0.44, h=0.56, iris=hexc("ff6ab0")).mouth("cat", w=1.0).cheeks(color=hexc("ff8ac0"))
parts += f.parts
ship("slime_bloom", parts)
