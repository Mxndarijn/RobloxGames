# Soda Pop (hybrid: bubbles + gummy + mochi). Fizzy cola drop: dark-to-amber cola body full of rising
# fizz, a fluffy white foam head (mochi crown) dripping down, a crimped red bottle cap worn like a
# crown, a bent striped straw, soap-bubble fizz floating up (bubbles) and a big bubbly grin (gummy).
from models._slimepool import *

COLA_D, COLA, AMBER, AMBER_L = hexc("3a1206"), hexc("9a3212"), hexc("e2741a"), hexc("ffc060")
FOAM, FOAM_D = hexc("fffaf0"), hexc("f2dcc0")
CAP, CAP_D, CAP_L = hexc("ff2a3a"), hexc("b0101e"), hexc("ff8a8a")
STRAW_A, STRAW_B = hexc("ff3048"), WHITE


def adiff(a, b):
    return math.atan2(math.sin(a - b), math.cos(a - b))


DRIPS = [(math.radians(d), depth, w) for d, depth, w in
         ((38, 0.42, 0.16), (-52, 0.55, 0.15), (95, 0.62, 0.17), (-110, 0.4, 0.15), (150, 0.58, 0.16),
          (-160, 0.66, 0.17), (205, 0.0, 0.1))]


def foam_edge(a):
    d = 0.0
    for c, depth, w in DRIPS:
        x = adiff(a, c) / w
        if abs(x) < 3:
            d = max(d, depth * math.exp(-x * x * 1.4) ** 0.4)
    return 2.28 + 0.05 * math.sin(a * 7) - d


def paint(a, z, p):
    c = mix(COLA_D, COLA, smoothstep(0.0, 0.9, z))
    c = mix(c, AMBER, smoothstep(0.7, 2.1, z))
    # glassy glow through the front belly
    c = mix(c, AMBER_L, 0.35 * smoothstep(0.9, 0.2, abs(a)) * smoothstep(0.4, 1.0, z) * smoothstep(1.7, 1.1, z))
    e = foam_edge(a)
    f = smoothstep(e - 0.03, e + 0.03, z)
    return mix(c, mix(FOAM_D, FOAM, smoothstep(e, e + 0.5, z)), f)


b = Body([(0, 1.05), (0.12, 1.34), (0.5, 1.5), (1.05, 1.5), (1.7, 1.32), (2.3, 0.95), (2.75, 0.45), (2.95, 0)],
         paint=paint, segs=28, sub=2, gloss=0.85)
parts = [b.obj]

# foam head: lumpy cloud of suds on the crown
TOPZ = b.H
suds = [((0, 0.05, TOPZ - 0.22), 0.72, (1.2, 1.15, 0.42))]
for k in range(6):
    a = k * math.tau / 6 + 0.5
    suds.append(((math.sin(a) * 0.62, -math.cos(a) * 0.6 + 0.05, TOPZ - 0.28 + 0.05 * math.sin(k * 2.3)), 0.3 + 0.05 * ((k * 3) % 2)))
parts.append(goo("Foam", suds, zgrad(FOAM_D, FOAM, TOPZ - 0.6, TOPZ + 0.1), tris=190, resolution=0.08))

# fizz inside the cola: columns of rising bubble rings on the sides and back (face stays clear)
fizz = []
for yaw, z0 in ((72, 0.45), (128, 0.7), (172, 0.4), (-118, 0.55), (-68, 0.4)):
    for k, (dz, w) in enumerate(((0.0, 0.26), (0.46, 0.19), (0.82, 0.13))):
        fizz.append((yaw + 5 * math.sin(k * 2.0 + yaw), z0 + dz, w))
parts += spots(b, fizz, AMBER_L, n=7)
parts += spots(b, [(y - w * 9, z + w * 0.22, w * 0.34) for y, z, w in fizz if w > 0.15], WHITE, n=6, off=0.03)

# crimped bottle cap, worn tilted like a crown
def bottle_cap(name, R=0.74, H=0.28, teeth=18):
    o = lathe(name, [(0.0, 0.0), (0.0, R * 1.02), (H, R * 0.9), (H + 0.03, R * 0.6), (H + 0.04, 0.0)],
              CAP, segs=teeth * 2, smooth=False)
    me = o.data
    for v in me.vertices:
        r = math.hypot(v.co.x, v.co.y)
        if r < 1e-4:
            continue
        a = math.atan2(v.co.y, v.co.x)
        k = 1 + 0.09 * math.cos(a * teeth) * smoothstep(H * 0.95, 0.0, v.co.z)
        v.co.x *= k
        v.co.y *= k
    return o


cap = bottle_cap("Cap")
M = Matrix.Translation((0.28, -0.12, TOPZ + 0.1)) @ Matrix.Rotation(math.radians(24), 4, "X") @ Matrix.Rotation(math.radians(20), 4, "Y")
cap.data.transform(M)
cc = M @ Vector((0, 0, 0.3))


def cap_col(p, n):
    q = M.inverted() @ p
    r = math.hypot(q.x, q.y)
    c = mix(CAP_D, CAP, smoothstep(-0.02, 0.2, q.z))
    if q.z > 0.27:  # top face: gold ring + star
        c = GOLD if 0.44 < r < 0.55 else CAP
    hl = max(0.0, n.dot(Vector((-0.4, -0.6, 0.7)).normalized()))
    return mix(c, CAP_L, 0.5 * smoothstep(0.9, 0.99, hl))


paint_fn(cap, cap_col)
register(cap)
parts.append(cap)
parts.append(decal("CapStar", star(0, 0, 0.3, 0.13), GOLD_L,
                   Frame(M @ Vector((0, 0, 0)), M.to_3x3() @ Vector((1, 0, 0)), M.to_3x3() @ Vector((0, 1, 0)), M.to_3x3() @ Vector((0, 0, 1))),
                   off=0.01, th=0.02, on=["Cap"]))

# bent striped straw stuck in the top
base = Vector((-0.5, 0.25, TOPZ - 0.3))
pts = [base, base + Vector((-0.18, 0.04, 0.95)), base + Vector((-0.27, 0.06, 1.45)), base + Vector((-0.36, 0.06, 1.6)),
       base + Vector((-0.58, 0.06, 1.7)), base + Vector((-0.95, 0.06, 1.62))]
straw = tube("Straw", pts, [0.14] * len(pts), None, segs=10)
L = [0.0]
for p0, p1 in zip(pts, pts[1:]):
    L.append(L[-1] + (p1 - p0).length)


def straw_col(p, n):
    best, bl = 1e9, 0.0
    for i in range(len(pts) - 1):
        seg = pts[i + 1] - pts[i]
        t = min(1, max(0, (p - pts[i]).dot(seg) / seg.length_squared))
        d = (pts[i] + seg * t - p).length
        if d < best:
            best, bl = d, L[i] + seg.length * t
    ang = math.atan2(n.y, n.x)
    return STRAW_A if math.sin(bl * 8.0 + ang) > 0 else STRAW_B


paint_fn(straw, straw_col)
parts.append(keep(straw, True))


# soap-bubble fizz rising beside the head (bubbles DNA), amber-tinted
def soap(c):
    def fn(p, n):
        d = (p - Vector(c)).normalized()
        col = mix(hexc("ffd27a"), hexc("ffa8c8"), 0.5 + 0.5 * d.x)
        rim = 1 - abs(d.y)
        return mix(WHITE, col, 0.3 + 0.7 * rim)
    return fn


for k, (c, r) in enumerate((((1.45, -0.1, 2.55), 0.26), ((1.7, 0.1, 3.15), 0.19), ((1.25, 0.2, 3.6), 0.14),
                            ((-1.55, -0.2, 2.15), 0.18))):
    parts.append(ball(f"Fizz{k}", r, c, soap(c), subdiv=2))
    parts.append(ball(f"FizzHi{k}", r * 0.24, (c[0] - r * 0.4, c[1] - r * 0.62, c[2] + r * 0.42), WHITE, squash=(1, 0.6, 1.3), subdiv=1))

f = Face(b, eye_u=0.52, eye_v=1.58, mouth_v=1.08)
f.eyes("big", w=0.5, h=0.64, iris=hexc("ffb030")).mouth("grin", w=1.25).cheeks(color=hexc("ff7a9a"))
parts += f.parts
ship("slime_soda", parts)
