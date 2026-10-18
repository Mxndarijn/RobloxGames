# Snow Bunny (Epic hybrid: lop + frostbite + mochi): a cozy winter bunny. Icy blue goo frosted white
# on top (frostbite's wavy snowline), long frosty ears with ice-crystal tips, one ear flopped over
# (lop), fluffy lilac earmuffs, a striped pink knit scarf, snowflakes, big rosy mochi cheeks,
# sparkly ice-blue eyes and a shy :3 with a buck tooth.
from models._slimepool import *

ICE, ICE_D, ICE_L, SNOW = hexc("7cd0ff"), hexc("3a9cf0"), hexc("c4ecff"), hexc("ffffff")
CRY0, CRY1 = hexc("3a9cf0"), hexc("e0faff")
MUFF, MUFF_D, MUFF_L = hexc("b47cff"), hexc("8048e0"), hexc("e0c8ff")
SCARF, SCARF_D, STRIPE = hexc("ff3d8a"), hexc("d01e64"), hexc("fff4f8")
PINK, PINK_D, EARIN = hexc("ff9cc0"), hexc("ff5c94"), hexc("ffb6d0")


def snowline(a):
    return 2.02 + 0.1 * math.sin(a * 5 + 0.4) + 0.05 * math.sin(a * 9 + 1)


def paint(a, z, p):
    c = mix(ICE_D, ICE, smoothstep(0.0, 1.0, z))
    c = mix(c, ICE_L, smoothstep(1.0, 1.9, z))
    return mix(c, SNOW, smoothstep(snowline(a) - 0.035, snowline(a) + 0.035, z))


b = Body([(0, 1.18), (0.12, 1.44), (0.5, 1.56), (1.15, 1.5), (1.8, 1.24), (2.35, 0.84), (2.72, 0.32), (2.82, 0)],
         paint=paint, segs=40, sub=2, gloss=0.8)
parts = [b.obj]

# ---- ears: goo chains. Viewer-left stands tall; viewer-right bends over at the middle (lop DNA)
def ear_col(cx):
    def fn(p, n):
        c = mix(SNOW, ICE_L, smoothstep(3.3, 4.3, p.z))
        inner = smoothstep(-0.15, -0.55, n.y) * smoothstep(0.17, 0.1, abs(p.x - cx(p.z))) * smoothstep(2.85, 3.1, p.z) * smoothstep(4.05, 3.8, p.z)
        return mix(c, EARIN, inner)
    return fn


EAR_L = [(-0.42, 0.14, 2.5), (-0.52, 0.12, 3.0), (-0.62, 0.1, 3.5), (-0.7, 0.08, 3.95), (-0.72, 0.08, 4.12)]
EAR_R = [(0.42, 0.14, 2.5), (0.54, 0.12, 2.95), (0.7, 0.08, 3.38), (0.94, 0.0, 3.6), (1.2, -0.08, 3.52), (1.34, -0.12, 3.3)]


def resample(pts, step=0.1):
    P = [Vector(p) for p in pts]
    L = [0.0]
    for a, c in zip(P, P[1:]):
        L.append(L[-1] + (c - a).length)
    out = []
    n = max(2, int(L[-1] / step))
    for k in range(n + 1):
        l = L[-1] * k / n
        for i in range(len(P) - 1):
            if L[i + 1] >= l - 1e-9:
                t = (l - L[i]) / max(L[i + 1] - L[i], 1e-9)
                out.append((P[i] + (P[i + 1] - P[i]) * t, k / n))
                break
    return out


for nm, pts in (("EarL", EAR_L), ("EarR", EAR_R)):
    balls = []
    for p, t in resample(pts):
        r = 0.2 + 0.16 * math.sin(min(1.0, t * 1.25) * math.pi) ** 0.7 + 0.04 * (t < 0.15)
        balls.append((tuple(p), r, (1.0, 0.5, 1.0)))
    xs = [(p.z, p.x) for p, t in resample(pts, 0.05)]

    def cx(z, xs=xs):
        return min(xs, key=lambda q: abs(q[0] - z))[1]
    parts.append(goo(nm, balls, ear_col(cx), tris=400, resolution=0.06))
# ice-crystal tips: the tall ear points up, the bent ear grows an icicle hanging down
parts.append(crystal("EarIceL", (-0.72, 0.08, 4.2), (-0.1, 0, 1), 0.6, 0.17, CRY0, CRY1))
parts.append(crystal("EarIceR", (1.36, -0.12, 3.2), (0.1, -0.05, -1), 0.62, 0.16, CRY0, CRY1))
parts.append(crystal("EarIceR2", (1.18, -0.08, 3.36), (-0.15, -0.05, -1), 0.38, 0.11, CRY0, CRY1))

# ---- earmuffs: fluffy lilac puffs on the sides, band arching behind the ears
for sd in (-1, 1):
    c = Vector((sd * 1.38, 0.05, 2.0))
    balls = [(tuple(c), 0.44, (0.7, 1, 1))]
    for k in range(10):
        a = k * math.tau / 10
        balls.append((tuple(c + Vector((sd * 0.04, math.cos(a) * 0.32, math.sin(a) * 0.32))), 0.17))
    parts.append(goo(f"Muff{'L' if sd < 0 else 'R'}", balls,
                     lambda p, n, c=c: mix(MUFF_D, MUFF_L, smoothstep(c.z - 0.45, c.z + 0.4, p.z) * 0.8 + 0.2 * max(0.0, -n.y)),
                     tris=320, resolution=0.045))
band = [(1.3 * math.cos(t), 0.32, 2.12 + 0.95 * math.sin(t)) for t in [math.radians(10 + 160 * k / 12) for k in range(13)]]
parts.append(horn("Headband", band, [0.07] * len(band), hexc("9a66f0"), hexc("c9a8ff"), segs=6))

# ---- striped knit scarf round the base + a hanging end
SZ = 0.86
R = b.radius(SZ) + 0.04


def scarf_col(p, n):
    a = math.atan2(p.x, -p.y)
    c = SCARF if math.sin(a * 5) < 0.7 else STRIPE
    c = shade(c, 0.9 + 0.1 * abs(math.sin(a * 36)))  # knit ribs
    return mix(shade(c, 0.8), c, smoothstep(SZ - 0.13, SZ + 0.1, p.z))


parts.append(torus("Scarf", R, 0.15, (0, 0, SZ), (0, 0, 1), scarf_col, segs=32, rsegs=6))
# hanging end at the front-left, fringe at the bottom
ya = math.radians(-38)
o = b.point(ya, SZ, 0.2)
fringe = [(-0.26, 0.0), (0.26, 0.0), (0.28, -0.72)]
for k in range(5):
    x = 0.28 - (k + 0.5) * 0.112
    fringe += [(x + 0.03, -0.72), (x, -0.9), (x - 0.03, -0.72)]
fringe += [(-0.28, -0.72)]
X = Vector((math.cos(ya), math.sin(ya), 0))
parts.append(slab("RibbonScarf", fringe, 0.12, tuple(o + Vector((0, 0, -0.02))), tuple(X), (0.0, -0.25, 1.0),
                  lambda p, n: (SCARF if math.sin((p.z - SZ) * 10) < 0.5 else STRIPE) if p.z > SZ - 0.72 + 0.02 else mix(SCARF, STRIPE, 0.6)))

# ---- snowflakes on the sides and back
def flake(name, frame, r, col=SNOW, off=0.012):
    out = []
    for j in range(3):
        out.append(decal(f"{name}a{j}", rect(0, 0, 2 * r, r * 0.22, math.radians(j * 60)), col, frame, off=off + j * 0.006, th=0.01, on=["Body"]))
    return out


for k, (yaw, z, r) in enumerate(((75, 1.25, 0.2), (115, 1.6, 0.14), (160, 1.15, 0.22), (210, 1.6, 0.16), (250, 1.2, 0.2), (-70, 1.55, 0.13))):
    parts += flake(f"Flake{k}", frame_at(yaw, z), r)

# ---- face: big sparkly ice eyes, pink nose, :3 with one buck tooth, rosy mochi cheeks
f = Face(b, eye_u=0.52, eye_v=1.62, mouth_v=1.2)
f.eyes("sparkle", w=0.44, h=0.56, iris=hexc("52c8ff"))
f.nose(color=PINK_D, w=0.18, h=0.11, v=1.35)
f.mouth("cat", w=1.0, v=1.22)
f.d("Tooth", rect(0, 1.12, 0.11, 0.12), WHITE, off=0.035, th=0.015)
f.cheeks(color=PINK, w=0.42, h=0.22, u=0.98, v=1.32)
parts += f.parts
ship("slime_snow_bunny", parts)
