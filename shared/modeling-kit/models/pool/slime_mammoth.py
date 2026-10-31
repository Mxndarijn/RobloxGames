# Mammoth (Mythic, Frost & Sea family): a woolly ice-age mammoth slime. Warm caramel-brown shaggy fur
# (tuft rows in the body surface) under a frosty snow blanket on the back with ice crystals in it,
# a woolly top-knot, big floppy ears, a short curled trunk, two curled ivory tusks with frost tips,
# and a proud, sweet face.
from models._slimepool import *

FUR_D, FUR, FUR_L = hexc("c47e4c"), hexc("d8955e"), hexc("eeb47c")
SNOW_B, SNOW = hexc("cfe6ff"), hexc("fbfdff")
IVORY_D, IVORY, IVORY_L = hexc("f2dcae"), hexc("fbedcc"), hexc("fffaf0")
ICE_D, ICE_L = hexc("4aa8ff"), hexc("e0f8ff")
EAR_IN = hexc("f2a888")

NT = 18       # tuft columns round the body
ROW = 0.4     # tuft row height
H = 3.0
EV = 1.72


def axes(x, y):
    x = Vector(x).normalized()
    y = Vector(y)
    y = (y - x * y.dot(x)).normalized()
    return x, y


def tuft(a, z):
    v = z / ROW + 0.2 * noise.noise(Vector((math.cos(a) * 2.0, math.sin(a) * 2.0, z * 0.7)))
    row = math.floor(v)
    fv = v - row
    u = a * NT / math.tau + 0.5 * (row % 2)
    fu = u - math.floor(u)
    across = 1 - abs(fu - 0.5) * 2
    return max(0.0, across ** 0.6 - (1 - fv) * 0.9) if fv > 0 else 0.0


def face_zone(a, z):
    """1 on the smooth face (front, between eye and chin height), 0 elsewhere."""
    e = (math.degrees(a) / 52) ** 2 + ((z - 1.5) / 0.85) ** 2
    return 1 - smoothstep(0.8, 1.0, e)


def snow(a, z):
    """snow blanket over the crown and back: line low at the back, high at the front."""
    back = 0.5 - 0.5 * math.cos(a)  # 0 front, 1 back
    n = noise.noise(Vector((math.cos(a) * 1.8, math.sin(a) * 1.8, 7.1)))
    line = 2.75 - 1.15 * back ** 1.3 + 0.18 * n
    return smoothstep(line - 0.06, line + 0.06, z)


def fur_amount(a, z):
    return (1 - face_zone(a, z)) * smoothstep(0.15, 0.45, z)


def bump(a, z):
    return 0.14 * fur_amount(a, z) * tuft(a, z) * (1 - 0.5 * snow(a, z))


def paint(a, z, p):
    c = mix(FUR_D, FUR, smoothstep(0.1, 1.4, z))
    c = mix(c, FUR_L, 0.55 * smoothstep(1.3, 2.6, z))
    t = tuft(a, z)
    c = mix(c, FUR_D, 0.4 * fur_amount(a, z) * (1 - smoothstep(0.0, 0.2, t)))
    c = mix(c, mix(FUR, FUR_L, 0.7), 0.6 * face_zone(a, z))
    s = snow(a, z)
    sc = mix(SNOW_B, SNOW, smoothstep(0.0, 0.25, t) * 0.6 + 0.4 * smoothstep(1.8, 3.0, z))
    return mix(c, sc, s)


b = Body([(0, 1.2), (0.12, 1.5), (0.5, 1.68), (1.1, 1.66), (1.8, 1.42), (2.4, 1.0), (2.82, 0.45), (H, 0)],
         paint=paint, bump=bump, segs=54, sub=3, gloss=0.3)
parts = [b.obj]

# ---- woolly top-knot: a few fur cones on the crown, snow-dusted tips
def tuft_cone(name, base, d, L, r, c0, c1):
    d = Vector(d).normalized()
    return lathe(name, [(0, r), (L * 0.45, r * 0.8), (L, 0)], along(c0, c1, base, Vector(base) + d * L),
                 pos=tuple(base), axis=tuple(d), segs=6, smooth=True)


for k, (x, y, dx, dy, L) in enumerate(((0, -0.1, 0, -0.55, 0.75), (-0.24, 0.0, -0.5, -0.3, 0.6), (0.24, 0.0, 0.5, -0.3, 0.6),
                                       (-0.1, 0.25, -0.2, 0.2, 0.55), (0.12, 0.22, 0.25, 0.25, 0.55))):
    parts.append(tuft_cone(f"Knot{k}", Vector((x, y, H - 0.25)), (dx, dy, 1), L, 0.25, FUR_D, FUR_L))

# ---- floppy ears: big rounded flaps hanging on the sides, pink-peach inside
ear = [(-0.05, 0.3), (0.3, 0.5), (0.75, 0.52), (1.1, 0.35), (1.28, 0.0), (1.2, -0.38), (0.9, -0.55), (0.5, -0.5), (0.15, -0.32), (-0.05, -0.1)]
for sd in (-1, 1):
    a = math.radians(sd * 70)
    root = b.point(a, 2.3, -0.1)
    X, Y = axes((sd * 0.45, -0.25, -0.9), (sd * 0.9, -0.2, 0.3))
    fn = lambda p, n, r=root: mix(FUR_D, FUR, smoothstep(r.z - 0.9, r.z + 0.2, p.z))
    parts.append(puffy_slab(f"Ear{sd}", ear, 0.16, tuple(root), tuple(X), tuple(Y), fn, rows=3))
    inner = [(x * 0.68 + 0.12, y * 0.68 - 0.08) for x, y in ear]
    N = X.cross(Y).normalized()
    front = N if N.y < 0 else -N
    parts.append(puffy_slab(f"EarIn{sd}", inner, 0.06, tuple(root + front * 0.1), tuple(X), tuple(Y), EAR_IN, rows=2))

def spline(ctrl, n=4):
    """Catmull-Rom through 3D control points, n samples per segment."""
    P = [Vector(c) for c in ctrl]
    P = [P[0]] + P + [P[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return [tuple(q) for q in out]


# ---- trunk: from between the eyes down the face, the tip curling up to the viewer's right
tp = spline([(0.0, -1.48, 1.58), (0.0, -1.72, 1.2), (0.06, -1.9, 0.82), (0.24, -2.0, 0.56), (0.5, -2.0, 0.54),
              (0.66, -1.96, 0.72), (0.64, -1.94, 0.92)], 2)
tr = [0.3 - 0.17 * k / (len(tp) - 1) for k in range(len(tp))]
parts.append(horn("Trunk", tp, tr, mix(FUR, FUR_L, 0.6), mix(FUR_L, EAR_IN, 0.35), segs=10, smooth=True))

# ---- tusks: curled ivory, from beside the trunk root out, down, forward and up; frosty tips
for sd in (-1, 1):
    ctrl = [(sd * 0.42, -1.38, 1.15), (sd * 0.78, -1.72, 0.82), (sd * 1.12, -2.05, 0.74), (sd * 1.34, -2.36, 0.96),
            (sd * 1.36, -2.56, 1.36), (sd * 1.18, -2.58, 1.72)]
    pts = spline(ctrl, 3)
    n = len(pts) - 1
    radii = [0.18 * (1 - 0.75 * k / n) + 0.025 for k in range(n + 1)]
    parts.append(horn(f"Tusk{sd}", pts, radii, IVORY_D, hexc("e4f6ff"), segs=8, smooth=True))

# ---- ice crystals poking out of the snow blanket
for k, (yaw, z, L, r, tilt) in enumerate(((160, 2.35, 0.7, 0.15, 0.4), (-160, 2.35, 0.7, 0.15, 0.4), (180, 1.75, 0.6, 0.14, 0.2),
                                          (125, 1.85, 0.5, 0.12, 0.25), (-125, 1.85, 0.5, 0.12, 0.25))):
    a = math.radians(yaw)
    base = b.point(a, z, -0.12)
    nrm = Vector((math.sin(a), -math.cos(a), 0))
    d = (nrm + Vector((0, 0, 0.6 + tilt))).normalized()
    parts.append(crystal(f"Ice{k}", tuple(base), tuple(d), L, r, ICE_D, ICE_L, segs=6))

# ---- face: sweet proud eyes with a warm iris, small smile beside the trunk
f = Face(b, eye_v=EV, eye_u=0.55, mouth_v=1.0)
f.eyes("round", w=0.42, h=0.56, iris=hexc("8fd0ff"))
f.brows("raised", w=0.36, th=0.08, lift=-0.02, color=FUR_D)
f.mouth("smile", w=0.9, u=-0.4, v=1.12)
f.cheeks(color=hexc("ff9fb0"), w=0.26, h=0.13, u=0.86, v=EV - 0.36)
parts += f.parts

ship("slime_mammoth", parts)
