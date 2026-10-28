# Goomancer (Boss, tier 7 Secret): grand wizard slime. Periwinkle goo under a huge midnight-blue
# pointed hat (gold band, gold stars and a crescent moon, the tip bent over and drooping), a big
# fluffy white beard and bushy brows, wise half-lidded glowing eyes, and a crooked wooden staff
# held by a goo arm, topped with a glowing lime goo orb with gold sparks orbiting it.
from models._slimepool import *

flat_decals()  # boss size: face parts hug the body instead of standing out


def crescent(cu, cv, r, cut=0.42, n=14, rot=0.0):
    """crescent moon: outer circle arc minus a circle shifted by cut*r towards +u (rotated by rot)."""
    c, s = math.cos(rot), math.sin(rot)
    ri = r * 0.86
    dx = cut * r
    # where the two circles cross
    xi = (dx * dx + r * r - ri * ri) / (2 * dx)
    yi = math.sqrt(max(r * r - xi * xi, 1e-6))
    a0 = math.atan2(yi, xi)
    pts = []
    for k in range(n + 1):  # outer arc, the long way round (through -u)
        a = a0 + (math.tau - 2 * a0) * k / n
        pts.append((math.cos(a) * r, math.sin(a) * r))
    b0 = math.atan2(-yi, xi - dx)
    b1 = math.atan2(yi, xi - dx)
    if b1 < b0:
        b1 += math.tau
    for k in range(1, n):  # inner arc back (through -u of the shifted circle)
        a = b0 - (b0 + math.tau - b1) * k / n
        pts.append((dx + math.cos(a) * ri, math.sin(a) * ri))
    return [(cu + x * c - y * s, cv + x * s + y * c) for x, y in pts]


PERI, PERI_D, PERI_L = hexc("8a98ff"), hexc("6170e6"), hexc("bcc4ff")
HAT, HAT_D, HAT_L = hexc("2c2a8c"), hexc("1e1c5e"), hexc("4a46c4")
BEARD, BEARD_D = hexc("ffffff"), hexc("dde2f4")
WOOD, WOOD_D, WOOD_L = hexc("8a5a2e"), hexc("57361a"), hexc("b27a42")
ORB, ORB_L, ORB_D = hexc("9dff3a"), hexc("f2ffd0"), hexc("4fd61a")
EYE_GLOW = hexc("b8ff4a")

# ---- body: round periwinkle goo, a little shorter than usual so the hat can tower
H = 2.85
b = Body([(0, 1.12), (0.12, 1.36), (0.5, 1.52), (1.05, 1.52), (1.7, 1.34), (2.25, 1.0), (2.65, 0.5), (H, 0)],
         paint=lambda a, z, p: mix(mix(PERI_D, PERI, smoothstep(0.0, 1.0, z)), PERI_L, 0.4 * smoothstep(1.6, 2.8, z)),
         segs=32, sub=3, gloss=0.6)
parts = [b.obj]

# ---- the hat: brim + a tall cone swept along a path that bends over and droops to the right
HB = Vector((0.0, 0.15, 2.58))  # brim centre
tilt = Vector((0.0, 0.12, 1.0)).normalized()  # leans back a touch so the brim clears the face
brim_prof = [(0.0, 0), (0.0, 0.85), (-0.06, 1.3), (-0.15, 1.58), (-0.09, 1.66), (0.04, 1.6), (0.1, 1.3), (0.14, 0.85), (0.14, 0)]
parts.append(lathe("HatBrim", brim_prof, lambda p, n: mix(HAT_D, HAT, smoothstep(2.4, 2.7, p.z)), pos=tuple(HB), axis=tuple(tilt), segs=24))

ctrl = [HB + tilt * 0.05, HB + tilt * 1.2, HB + tilt * 2.3 + Vector((0.08, 0.0, 0)), Vector((0.35, 0.45, 5.4)),
        Vector((0.95, 0.45, 5.9)), Vector((1.55, 0.3, 5.75)), Vector((1.85, 0.15, 5.3))]
rad = [1.08, 0.9, 0.68, 0.47, 0.31, 0.19, 0.05]
# smooth the path (catmull on each coordinate via (t, value) pairs)
N = 4
path, rads = [], []
for i in range(len(ctrl) - 1):
    p0, p1, p2, p3 = ctrl[max(i - 1, 0)], ctrl[i], ctrl[i + 1], ctrl[min(i + 2, len(ctrl) - 1)]
    for k in range(N):
        t = k / N
        path.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
        rads.append(rad[i] + (rad[i + 1] - rad[i]) * t)
path.append(ctrl[-1]); rads.append(rad[-1])
cone = tube("HatCone", [tuple(p) for p in path], rads, None, segs=16, twist_free=True)
L = [0.0]
for p, q in zip(path, path[1:]):
    L.append(L[-1] + (q - p).length)


def hat_col(p, n):
    best, bt = 1e9, 0.0
    for i in range(len(path) - 1):
        seg = path[i + 1] - path[i]
        t = min(1, max(0, (p - path[i]).dot(seg) / max(seg.length_squared, 1e-9)))
        d = (path[i] + seg * t - p).length
        if d < best:
            best, bt = d, (L[i] + seg.length * t) / L[-1]
    c = mix(HAT, HAT_L, 0.5 * smoothstep(0.3, 1.0, bt))
    return mix(HAT_D, c, smoothstep(-0.4, 0.6, n.dot(Vector((-0.4, -0.6, 0.7)).normalized())))


paint_fn(cone, hat_col)
parts.append(register(keep(cone, True), "Hat"))
# gold band round the hat base
band_prof = [(0.12, 0), (0.12, 1.11), (0.46, 1.05), (0.46, 0)]
parts.append(lathe("HatTrim", band_prof, lambda p, n: mix(GOLD_D, GOLD, smoothstep(2.65, 3.05, p.z)), pos=tuple(HB), axis=tuple(tilt), segs=28, smooth=True))

# stars + crescent moon on the hat (projected onto the cone)
for k, (yaw, z, r) in enumerate(((-30, 3.6, 0.24), (40, 4.0, 0.19), (-8, 4.6, 0.16), (95, 3.55, 0.2), (-95, 4.15, 0.17), (170, 3.85, 0.2))):
    parts.append(decal(f"HatStar{k}", star(0, 0, r, r * 0.42, rot=90 + yaw * 0.3), GOLD_L, frame_at(yaw, z, cy=0.4), off=0.01, th=0.02, on=["Hat"], step=0))
parts.append(decal("HatMoon", crescent(0, 0, 0.3, rot=math.radians(20)), GOLD, frame_at(18, 3.2, cy=0.3), off=0.01, th=0.02, on=["Hat"], step=0))

# ---- face: wise half-lidded glowing eyes, bushy white brows (goo), big fluffy beard
EV = 1.78
f = Face(b, eye_v=EV, eye_u=0.46)
for sd in (-1, 1):
    u = sd * 0.46
    eye = oval(u, EV, 0.46, 0.46, n=16)
    eye = [(x, min(y, EV + 0.1)) for x, y in eye]
    f.d(f"Eye{sd}", eye, INK, off=0.015)
    glow = oval(u, EV - 0.03, 0.34, 0.31, n=14)
    glow = [(x, min(y, EV + 0.06)) for x, y in glow]
    f.d(f"EyeGlow{sd}", glow, EYE_GLOW, off=0.03, th=0.01)
    f.d(f"Pupil{sd}", oval(u, EV - 0.05, 0.13, 0.15, n=10), INK, off=0.042, th=0.008)
    f.d(f"EyeHi{sd}", oval(u - 0.07, EV - 0.01, 0.06, 0.06, n=8), WHITE, off=0.052, th=0.008)
parts += f.parts

# beard + mustache: distinct metaball lobes (spaced ~1 radius apart so they bulge), crevices shaded
beard_balls = []
for sd in (-1, 1):
    beard_balls += [((sd * 0.3, -1.46, 1.4), 0.3, (1.3, 0.75, 0.75)), ((sd * 0.66, -1.3, 1.3), 0.26, (1.1, 0.8, 0.8)),
                    ((sd * 0.86, -1.12, 1.1), 0.19, (1, 0.9, 1.1))]  # mustache curling down at the ends
    beard_balls += [((sd * 0.55, -1.42, 0.98), 0.36, (1, 0.8, 1.1)), ((sd * 0.32, -1.55, 0.58), 0.36, (1, 0.8, 1.15))]
beard_balls += [((0, -1.58, 1.0), 0.42, (1, 0.8, 1.05)), ((0, -1.66, 0.34), 0.32, (1, 0.8, 1.2)), ((0, -1.74, 0.12), 0.18, (1, 0.9, 1.1))]


def lobe_col(balls, c_hi, c_lo):
    B = [(Vector(q[0]), q[1] * 0.574 * max(q[2] if len(q) > 2 else (1, 1, 1))) for q in balls]

    def fn(p, n):
        d = min((p - c).length / r for c, r in B)  # ~1 on a lone lobe, more in the crevices
        c = mix(c_hi, c_lo, 0.8 * smoothstep(1.15, 1.6, d))
        return mix(c, c_lo, 0.3 * smoothstep(0.9, 0.1, p.z))
    return fn


parts.append(goo("Beard", beard_balls, lobe_col(beard_balls, BEARD, BEARD_D), tris=560, resolution=0.09))
# bushy brows: inner ends up, outer tufts drooping past the eyes (kind, wise; not angry)
for sd in (-1, 1):  # one goo call per side, so they never merge into a unibrow
    brow_balls = [((sd * 0.3, -1.25, 2.14), 0.2, (1.2, 0.85, 0.8)), ((sd * 0.52, -1.15, 2.22), 0.25, (1.2, 0.85, 0.85)),
                  ((sd * 0.78, -0.98, 2.12), 0.23, (1.1, 0.85, 0.9)), ((sd * 0.96, -0.79, 1.94), 0.18, (1, 0.85, 1.1))]
    parts.append(goo(f"Brow{'L' if sd > 0 else 'R'}", brow_balls, lobe_col(brow_balls, BEARD, BEARD_D), tris=170, resolution=0.07))

# ---- staff on the left (viewer's left, -X): crooked wood, held by a goo arm, glowing orb on top
SX = -2.05
staff_pts = [(SX + 0.05, -0.35, 0.05), (SX - 0.05, -0.38, 1.0), (SX + 0.06, -0.4, 1.9), (SX - 0.04, -0.42, 2.8), (SX + 0.08, -0.45, 3.5), (SX, -0.45, 3.95)]
parts.append(horn("Staff", staff_pts, [0.15, 0.16, 0.15, 0.16, 0.17, 0.2], WOOD_D, WOOD, segs=8, smooth=False))
OC = Vector((SX, -0.45, 4.52))
for k in range(3):  # three wooden prongs cradling the orb
    a = math.radians(90 + k * 120)
    base = Vector((SX, -0.45, 3.95))
    tip = OC + Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 0.0))
    mid = (base + tip) / 2 + Vector((math.cos(a) * 0.18, math.sin(a) * 0.18, -0.05))
    parts.append(horn(f"Prong{k}", [tuple(base), tuple(mid), tuple(tip)], [0.12, 0.1, 0.05], WOOD_D, WOOD_L, segs=6, smooth=False))
parts.append(ball("Orb", 0.58, tuple(OC), lambda p, n: mix(ORB_D, mix(ORB, ORB_L, smoothstep(0.3, 0.9, n.dot(Vector((-0.4, -0.6, 0.7)).normalized()))), smoothstep(-0.6, 0.2, n.z + n.dot(Vector((0, -1, 0))) * 0.3)), subdiv=3))
# goo arm from the body side out to the staff
arm = [((-1.3, -0.3, 1.25), 0.36, (1, 1, 0.9)), ((-1.65, -0.35, 1.4), 0.28), ((SX + 0.05, -0.4, 1.5), 0.26, (1.1, 1.1, 1.0))]
parts.append(goo("Arm", arm, PERI, tris=260, resolution=0.08))

# ---- floating gold sparks orbiting the orb
for j, (pos, r, rot) in enumerate((((SX + 0.75, -0.6, 4.85), 0.2, 10), ((SX - 0.6, -0.3, 4.15), 0.16, 30), ((SX + 0.25, -0.9, 3.9), 0.13, 0))):
    parts.append(puffy_slab(f"Spark{j}", star(0, 0, r, r * 0.4, n=4, rot=rot), 0.08, pos, (1, 0, 0), (0, 0, 1), GOLD_L, rows=2))

ship("slime_goomancer", parts)
