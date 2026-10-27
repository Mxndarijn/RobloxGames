# Goozilla (Boss): kaiju slime. Dark green pear-shaped goo with an olive belly, three rows of jagged
# glowing back plates down the spine to a stubby tail, tiny T-rex arms, stomping clawed feet,
# glowing angry eyes and a huge roaring mouth full of teeth.
from models._slimepool import *

flat_decals()  # boss size: face parts hug the body instead of standing out


GRN, GRN_D, GRN_L = hexc("2f9a4a"), hexc("17502c"), hexc("4cc46a")
BELLY, BELLY_D = hexc("c8e27a"), hexc("94b854")
GLOW, GLOW_L, GLOW_D = hexc("6bffd0"), hexc("f0fff8"), hexc("18b892")
CLAW = hexc("fff4d8")
MAW, MAW_D = hexc("5a0f2a"), hexc("2a0614")


def belly_z(a):
    return 0.2 + 1.25 * max(0.0, math.cos(a * 1.1)) ** 1.2


def paint(a, z, p):
    c = mix(GRN, GRN_D, smoothstep(1.2, 3.2, z) * 0.75)
    c = mix(c, GRN_D, 0.5 * smoothstep(1.6, 2.9, abs(a)))
    f = smoothstep(belly_z(a) + 0.12, belly_z(a) - 0.12, z)
    return mix(c, mix(BELLY, BELLY_D, smoothstep(1.2, 0.2, z) * 0.4), f)


H = 3.2
b = Body([(0, 1.3), (0.15, 1.55), (0.6, 1.62), (1.3, 1.5), (2.0, 1.2), (2.6, 0.82), (3.0, 0.4), (H, 0)],
         paint=paint, segs=44, sub=3, sy=1.05, gloss=0.4, shade=0.9,
         lean=lambda z: -0.18 * max(0.0, (z - 1.5) / 1.7) ** 1.5)
parts = [b.obj]

# ---- back plates: three rows of jagged glowing plates down the spine
def plate_poly(h, w):
    return [(-w / 2, 0), (-w * 0.32, h * 0.45), (-w * 0.44, h * 0.55), (-w * 0.12, h * 0.82), (0, h),
            (w * 0.14, h * 0.8), (w * 0.44, h * 0.58), (w * 0.3, h * 0.42), (w / 2, 0)]


def plate_col(base, tip):
    return along(GLOW_D, GLOW_L, base, tip, 0.9)


def plate_fn(base, up):
    base, up = Vector(base), Vector(up).normalized()
    tip = base + up
    def fn(p, n):
        t = max(0.0, min(1.0, (p - base).dot(up) / 1.0))
        if t < 0.18:
            return mix(GRN_D, GLOW_D, t / 0.18)
        return mix(GLOW_D, mix(GLOW, GLOW_L, smoothstep(0.6, 1.0, t)), smoothstep(0.18, 0.55, t))
    return fn


SPINE = [(3.08, 0.95, 0.78), (2.7, 1.2, 0.95), (2.2, 1.25, 1.0), (1.65, 1.08, 0.92), (1.1, 0.85, 0.78), (0.62, 0.6, 0.6)]
for k, (z, h, w) in enumerate(SPINE):
    # angle of the back surface at this height
    p = b.point(math.pi, z, -0.12)
    q = b.point(math.pi, z + 0.05, 0)
    r = b.point(math.pi, z - 0.05, 0)
    tang = (q - r).normalized()
    nrm = Vector((0, 1, 0)) - tang * tang.y
    nrm.normalize()
    up = (nrm * 0.8 + Vector((0, 0.2, 0.6))).normalized()
    if z > 3.0:
        p = Vector((0, b.lean(z) + 0.2, z - 0.12)); up = Vector((0, 0.3, 1)).normalized()
    side = up.cross(Vector((1, 0, 0)))
    parts.append(puffy_slab(f"Plate{k}", plate_poly(h, w), 0.16, p, side if side.length > 0 else (0, 1, 0), up,
                            plate_fn(p, up * h), rows=2))
    if 0 < k < 5:
        for sd in (-1, 1):
            a = math.pi - sd * 0.85
            ps = b.point(a, z - 0.08, -0.1)
            ups = (Vector((ps.x, ps.y - b.lean(z), 0)).normalized() * 0.85 + Vector((0, 0, 0.5))).normalized()
            ax = (Vector((0, 0, 1)) - ups * ups.z).normalized()
            hh, ww = h * 0.66, w * 0.66
            parts.append(puffy_slab(f"PlateS{k}{sd}", plate_poly(hh, ww), 0.12, ps, ax, ups, plate_fn(ps, ups * hh), rows=2))

# ---- stubby tail sweeping back from the base
tail_pts = [(0, 1.2, 0.45), (0, 1.8, 0.34), (0, 2.35, 0.3), (0.05, 2.8, 0.45), (0.12, 3.1, 0.75)]
parts.append(horn("Tail", tail_pts, [0.5, 0.4, 0.28, 0.17, 0.06], GRN_D, GRN, segs=12))
for k, t in enumerate((0.3, 0.55, 0.78)):
    i = t * (len(tail_pts) - 1)
    a, c = tail_pts[int(i)], tail_pts[min(int(i) + 1, len(tail_pts) - 1)]
    f = i - int(i)
    pos = Vector(a).lerp(Vector(c), f)
    rad = [0.5, 0.4, 0.28, 0.17, 0.06][int(i)] * (1 - f) + [0.5, 0.4, 0.28, 0.17, 0.06][min(int(i) + 1, 4)] * f
    up = Vector((0, 0, 1))
    base = pos + up * (rad * 0.7)
    hh = 0.42 - 0.1 * k
    parts.append(puffy_slab(f"TailPlate{k}", plate_poly(hh, hh * 1.05), 0.1, base, (0, 1, 0), up, plate_fn(base, up * hh), rows=2))

# ---- stomping feet: wide flat pads poking out front, three claws each
for sd in (-1, 1):
    fp = Vector((sd * 0.82, -1.05, 0.0))
    parts.append(ball(f"Foot{sd}", 0.62, tuple(fp + Vector((0, 0, 0.26))), zgrad(GRN_D, GRN, 0.0, 0.55), squash=(1.0, 1.15, 0.45)))
    for j in (-1, 0, 1):
        cp = fp + Vector((j * 0.26 + sd * 0.02, -0.6 + abs(j) * 0.08, 0.13))
        parts.append(lathe(f"Claw{sd}{j}", [(0, 0.11), (0.12, 0.09), (0.26, 0)], CLAW, pos=tuple(cp),
                           axis=(j * 0.25, -1, -0.15), segs=8))

# ---- tiny T-rex arms with claws, held up in front of the belly
for sd in (-1, 1):
    s0 = b.point(math.radians(sd * 48), 1.35, -0.1)
    pts = [tuple(s0), tuple(s0 + Vector((sd * 0.12, -0.28, -0.05))), tuple(s0 + Vector((sd * 0.05, -0.48, -0.22)))]
    parts.append(horn(f"Arm{sd}", pts, [0.18, 0.15, 0.12], GRN, GRN_L, segs=8))
    hand = Vector(pts[-1])
    for j in (-1, 1):
        parts.append(lathe(f"ArmClaw{sd}{j}", [(0, 0.06), (0.08, 0.05), (0.17, 0)], CLAW,
                           pos=tuple(hand + Vector((j * 0.06, -0.05, -0.04))), axis=(j * 0.3, -0.6, -1), segs=6))

# ---- face: glowing angry eyes, heavy brow ridge, huge roaring mouth
EV, MV = 2.15, 1.38
f = Face(b, eye_v=EV, mouth_v=MV, eye_u=0.5)
for sd in (-1, 1):
    u = sd * 0.5
    eye = oval(u, EV, 0.5, 0.42, n=16)
    eye = [(x, min(y, EV + 0.08 - (x - u) * 0.55 * sd)) for x, y in eye]
    halo = oval(u, EV, 0.66, 0.56, n=18)
    halo = [(x, min(y, EV + 0.15 - (x - u) * 0.55 * sd)) for x, y in halo]
    f.d(f"EyeHalo{sd}", halo, hexc("b8ff5a"), off=0.006, th=0.006)
    f.d(f"Eye{sd}", eye, INK, off=0.014)
    inner = oval(u + sd * 0.02, EV - 0.02, 0.38, 0.3, n=14)
    inner = [(x, min(y, EV + 0.04 - (x - u) * 0.55 * sd)) for x, y in inner]
    f.d(f"EyeGlow{sd}", inner, hexc("d8ff3a"), off=0.03, th=0.01)
    f.d(f"Pupil{sd}", oval(u + sd * 0.03, EV - 0.04, 0.09, 0.2, n=10), INK, off=0.045, th=0.008)
    f.d(f"EyeHi{sd}", oval(u - 0.1, EV - 0.06, 0.07, 0.07, n=8), WHITE, off=0.055, th=0.008)
    f.d(f"Brow{sd}", [(sd * 0.16, EV + 0.12), (sd * 0.72, EV + 0.3), (sd * 0.72, EV + 0.42), (sd * 0.12, EV + 0.25)], GRN_D, off=0.03, th=0.06)

mouth = []
for k in range(9):  # arched top lip, left to right
    x = -0.64 + 1.28 * k / 8
    mouth.append((x, MV + 0.3 - 0.1 * (x / 0.64) ** 2))
for k in range(1, 16):  # round jaw back, right to left
    a = -math.pi * k / 16
    mouth.append((math.cos(a) * 0.64, MV + 0.2 + math.sin(a) * 0.58))
parts.append(grid_decal("Mouth", mouth, lambda p, n: mix(MAW_D, MAW, smoothstep(MV - 0.4, MV + 0.3, p.z)), off=0.012, th=0.02, on=["Body"]))
parts.append(grid_decal("Tongue", oval(0, MV - 0.18, 0.6, 0.26, n=16), TONGUE, off=0.034, th=0.01, on=["Body"]))
# teeth: top row of big fangs + smaller lower teeth
for k in range(7):
    x = -0.48 + k * 0.16
    big = k in (0, 6)
    h = 0.26 if big else 0.16
    top = MV + 0.3 - 0.06 * (x / 0.6) ** 2
    f.d(f"Tooth{k}", [(x - 0.07, top + 0.02), (x + 0.07, top + 0.02), (x, top - h)], WHITE, off=0.045, th=0.012)
for k in range(4):
    x = -0.3 + k * 0.2
    bot = MV - 0.33 + 0.12 * (x / 0.55) ** 2 + 0.0
    f.d(f"LTooth{k}", [(x - 0.06, bot - 0.02), (x + 0.06, bot - 0.02), (x, bot + 0.13)], WHITE, off=0.045, th=0.012)
for sd in (-1, 1):
    f.d(f"Nostril{sd}", oval(sd * 0.13, MV + 0.47, 0.09, 0.055, n=8, rot=math.radians(-25 * sd)), GRN_D, off=0.015, th=0.01)
parts += f.parts

ship("slime_goozilla", parts)
