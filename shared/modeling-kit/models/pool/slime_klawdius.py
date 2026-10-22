# Klawdius (Boss, Mythic, Scoot, Feisty): giant hermit crab slime. A coral-red goo slime living in a
# huge spiral seashell that rises up behind it like a backpack (tip up and back), two oversized
# fiddler-crab claws raised at its sides (its right one much bigger), little pointed crab legs round
# the base, angry eyes under heavy brows and a grumpy underbite.
from models._slimepool import *

CORAL, CORAL_D, CORAL_L = hexc("ff5a46"), hexc("d83c34"), hexc("ff8a6a")
BELLY = hexc("ffb08a")
JOINT = hexc("b8302c")
TIP = hexc("fff0dc")
SHELL, SHELL_L, SHELL_D = hexc("f8d4ae"), hexc("fff0dc"), hexc("d89c7c")
STRIPE, STRIPE_D = hexc("cc4cb0"), hexc("9a3aa4")
BARN, BARN_D = hexc("e4e8ee"), hexc("8a8f9c")
BROW = hexc("6a1420")


# ---------------------------------------------------------------- body
def paint(a, z, p):
    c = mix(CORAL, CORAL_D, smoothstep(1.0, 2.7, z) * 0.35)
    # pale front belly under the face
    bz = 0.25 + 0.95 * max(0.0, math.cos(a * 1.25)) ** 1.5
    f = smoothstep(bz + 0.12, bz - 0.12, z)
    return mix(c, BELLY, f * 0.85)


H = 2.8
b = Body([(0, 1.3), (0.2, 1.52), (0.7, 1.58), (1.4, 1.42), (2.0, 1.1), (2.5, 0.62), (H, 0)],
         paint=paint, segs=30, sub=3, sy=1.0, gloss=0.45, shade=0.85)
parts = [b.obj]

# ---------------------------------------------------------------- spiral shell (backpack)
SH_L = 4.0
SH_PROF = [(0, 1.2), (0.3, 1.66), (0.85, 1.8), (1.45, 1.5), (2.1, 1.0), (2.8, 0.6), (3.5, 0.26), (SH_L, 0)]


def _rad(z):
    return Body.radius_of(SH_PROF, z)


# helical phase: pitch shrinks with the radius (log spiral look)
_PH = [(0.0, 0.0)]
for i in range(1, 331):
    z = SH_L * i / 330
    _PH.append((z, _PH[-1][1] + (SH_L / 330) / (0.62 * _rad(z) + 0.12)))


def phase(a, z):
    for (z0, p0), (z1, p1) in zip(_PH, _PH[1:]):
        if z <= z1:
            ph = p0 + (p1 - p0) * (z - z0) / max(z1 - z0, 1e-9)
            break
    else:
        ph = _PH[-1][1]
    return (ph - a / math.tau) % 1.0


def sh_bump(a, z):
    w = phase(a, z)
    f = math.sin(math.pi * w) ** 0.55  # 0 at the suture, 1 mid-whorl
    return -0.24 * (1 - f) * smoothstep(SH_L, SH_L - 0.3, z)


def sh_paint(a, z, p):
    w = phase(a, z)
    c = mix(SHELL_D, SHELL, smoothstep(0.02, 0.2, min(w, 1 - w)))
    c = mix(c, SHELL_L, 0.35 * smoothstep(0.6, 2.6, z))
    s = smoothstep(0.15, 0.08, abs(w - 0.5))
    return mix(c, mix(STRIPE, STRIPE_D, 0.25), s)


TILT = math.radians(-24)  # tip up and back (+Y)
SH_POS = Vector((0, 1.6, 1.2))
shell_b = Body(SH_PROF, paint=sh_paint, bump=sh_bump, segs=26, sub=4, name="Shell", shade=0.5, gloss=0.3,
               register_surface=False)
M_SH = Matrix.Translation(SH_POS) @ Matrix.Rotation(TILT, 4, "X")
shell_b.obj.data.transform(M_SH)
parts.append(shell_b.obj)

# knobs on the whorl shoulders (whelk spikes): break the soft-serve read
knobs = []
for i in range(80):
    a = math.radians(i * 47)
    # find z on the shoulder (phase 0.8) for this yaw by scanning
    best = None
    for j in range(200):
        z = 0.3 + j * (2.6 / 200)
        w = phase(a, z)
        if abs(w - 0.8) < 0.012:
            best = z
            break
    if best is None:
        continue
    knobs.append((a, best))
    if len(knobs) >= 9:
        break
for k, (a, z) in enumerate(knobs):
    p = M_SH @ shell_b.point(a, z, -0.06)
    n = (M_SH.to_3x3() @ Vector((math.sin(a), -math.cos(a), 0.45))).normalized()
    s = 0.3 * (1.0 - 0.3 * z / 2.9)
    parts.append(lathe(f"Knob{k}", [(0, s), (s * 1.3, s * 0.5), (s * 1.9, 0)], along(SHELL, SHELL_L, p, p + n * s * 1.9),
                       pos=tuple(p), axis=tuple(n), segs=6, smooth=True))

# barnacles: little volcano cones on the shell
for k, (a, z) in enumerate(((150, 1.2), (215, 2.0), (125, 2.7), (245, 0.9))):
    ar = math.radians(a)
    p = M_SH @ shell_b.point(ar, z, -0.02)
    n = (M_SH.to_3x3() @ Vector((math.sin(ar), -math.cos(ar), 0.25))).normalized()
    s = 0.24 if k < 2 else 0.18
    parts.append(lathe(f"Barnacle{k}", [(0, s), (0.12 * s / 0.24, s * 0.82), (0.22 * s / 0.24, s * 0.45), (0.2 * s / 0.24, s * 0.28), (0.08, 0)],
                       along(BARN_D, BARN, p, p + n * 0.2), pos=tuple(p), axis=tuple(n), segs=7, smooth=False))

# ---------------------------------------------------------------- claws (fiddler: its right one big)
def claw(sd, k):
    """sd: -1 = slime's right (viewer's left in front view), k: size scale."""
    out = []
    sh = b.point(math.radians(sd * 82), 1.2, -0.15)
    elbow = sh + Vector((sd * 0.38 * k, -0.15, 0.08))
    wrist = elbow + Vector((sd * 0.12 * k, -0.2, 0.75 * k))
    out.append(horn(f"Pec{sd}", [tuple(sh), tuple(sh.lerp(elbow, 0.5)), tuple(elbow)], [0.3 * k, 0.26 * k, 0.24 * k],
                    CORAL_D, CORAL))
    out.append(ball(f"PecElbow{sd}", 0.27 * k, tuple(elbow), JOINT, subdiv=2))
    out.append(horn(f"PecFore{sd}", [tuple(elbow), tuple(elbow.lerp(wrist, 0.5)), tuple(wrist)],
                    [0.24 * k, 0.24 * k, 0.26 * k], CORAL, CORAL))
    out.append(ball(f"PecWrist{sd}", 0.28 * k, tuple(wrist), JOINT, subdiv=2))
    # palm: fat oval pointing up and a bit outward
    D = Vector((sd * 0.25, -0.1, 1)).normalized()
    S = Vector((1, 0, 0)) * sd  # outward in the X-Z plane
    S = (S - D * S.dot(D)).normalized()
    pc = wrist + D * 0.55 * k
    out.append(ball(f"PecPalm{sd}", 0.6 * k, tuple(pc), along(CORAL_D, CORAL_L, wrist, pc + D * 0.6 * k),
                    squash=(0.95, 0.72, 1.15), rot=(math.radians(6), math.radians(-sd * 14), 0), subdiv=3 if k > 1 else 2))
    # pincer fingers: thick fixed finger (outer) + movable finger (inner), open V
    top = pc + D * 0.5 * k
    for j, (side, L, bend) in enumerate(((1, 1.2, -0.42), (-1, 1.0, 0.34))):
        root = top + S * side * 0.24 * k
        pts, rad = [], []
        for i in range(6):
            t = i / 5
            off = S * side * (0.28 * math.sin(t * math.pi * 0.9) + bend * t * t) * k
            pts.append(tuple(root + D * L * k * t + off))
            rad.append((0.38 * (1 - t) ** 0.7 + 0.04) * k)
        o = horn(f"PecFinger{sd}{j}", pts, rad, CORAL, CORAL, segs=8)
        P0, P1 = Vector(pts[0]), Vector(pts[-1])
        paint_fn(o, lambda p, n, P0=P0, P1=P1: mix(CORAL, TIP, smoothstep(0.55, 0.85, (p - P0).dot(P1 - P0) / (P1 - P0).length_squared)))
        out.append(o)
        # teeth bumps on the inner edge
        for i, t in enumerate((0.35, 0.6)):
            q = Vector(pts[int(t * 5)]).lerp(Vector(pts[int(t * 5) + 1]), t * 5 - int(t * 5))
            out.append(lathe(f"PecTooth{sd}{j}{i}", [(0, 0.09 * k), (0.12 * k, 0)], TIP, pos=tuple(q - S * side * 0.17 * k),
                             axis=tuple(-S * side), segs=6, smooth=False))
    return out


parts += claw(-1, 1.35)
parts += claw(1, 0.78)

# ---------------------------------------------------------------- crab legs round the base
for sd in (-1, 1):
    for k, a in enumerate((62, 92, 122)):
        ar = math.radians(sd * a)
        root = b.point(ar, 0.42, -0.12)
        rd = Vector((math.sin(ar), -math.cos(ar), 0))
        knee = root + rd * 0.5 + Vector((0, 0, 0.32))
        tip = root + rd * 0.92 + Vector((0, 0, -0.42))
        tip.z = 0.0
        o = horn(f"Leg{sd}{k}", [tuple(root), tuple(knee), tuple(root.lerp(tip, 0.5) + rd * 0.32 + Vector((0, 0, 0.12))), tuple(tip)],
                 [0.17, 0.14, 0.1, 0.02], CORAL_D, CORAL, segs=6)
        R0, T0 = Vector(root), Vector(tip)
        paint_fn(o, lambda p, n, R0=R0, T0=T0: mix(CORAL_D, TIP, smoothstep(0.75, 0.95, (p - R0).dot(T0 - R0) / (T0 - R0).length_squared)))
        parts.append(o)

# ---------------------------------------------------------------- face: angry eyes, heavy brows, grumpy underbite
EV, MV = 1.72, 1.02
f = Face(b, eye_v=EV, mouth_v=MV, eye_u=0.5)
for sd in (-1, 1):
    u = sd * 0.5
    eye = oval(u, EV, 0.5, 0.56, n=16)
    eye = [(x, min(y, EV + 0.1 - (x - u) * 0.6 * sd)) for x, y in eye]
    f.d(f"Eye{sd}", eye, INK, off=0.015)
    f.d(f"EyeHi{sd}", oval(u - 0.08, EV + 0.0, 0.14, 0.13, n=10), WHITE, off=0.05, th=0.012)
    f.d(f"EyeHi2{sd}", oval(u + 0.09, EV - 0.15, 0.07, 0.07, n=8), WHITE, off=0.05, th=0.012)
    # heavy brow: thick slab, inner end low
    f.d(f"Brow{sd}", [(sd * 0.14, EV + 0.14), (sd * 0.8, EV + 0.42), (sd * 0.82, EV + 0.6), (sd * 0.1, EV + 0.32)],
        BROW, off=0.03, th=0.06)
mouth = arc(0, MV - 0.2, 0.34, 28, 152, 0.11, n=12)
f.d("Mouth", mouth, MOUTH, off=0.02)
for sd in (-1, 1):  # two little underbite fangs poking up
    x = sd * 0.2
    f.d(f"Fang{sd}", [(x - 0.07, MV - 0.0), (x + 0.07, MV - 0.0), (x, MV + 0.15)], WHITE, off=0.04, th=0.015)
parts += f.parts

ship("slime_klawdius", parts)
