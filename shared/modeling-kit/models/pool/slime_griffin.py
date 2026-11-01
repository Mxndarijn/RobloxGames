# Griffin (Mythic, Meadow set): half eagle, half lion. Lion-gold goo with a white eagle hood whose
# lower edge is a row of feather scallops, a hooked gold beak, a swept-back feather crest, two big
# layered wings (cream coverts, gold-tipped primaries) and a lion tail with a tufted tip.
# Signature face: proud, confident half-lidded eyes with sky-blue irises and white feather brows.
from models._slimepool import *

GOLD_B, GOLD_T, GOLD_LO = hexc("ffcb58"), hexc("ffdf84"), hexc("ffb94e")
HOOD, HOOD_D = hexc("fffcf4"), hexc("fbf2e6")
AMBER, AMBER_L = hexc("ffa640"), hexc("ffbe5c")
BEAK, BEAK_D = hexc("ffb12a"), hexc("f08a1e")
IRIS = hexc("4cc4ff")
FEATH, FEATH_D = hexc("ffffff"), hexc("fbf3e8")
TIP, TIP_L = hexc("ffb43c"), hexc("ffe08a")

H = 3.0


def hood_edge(a):
    """height of the hood's lower edge: low at the chest, rising round the sides, scalloped."""
    d = abs(math.degrees(a))
    base = 1.2 + 1.25 * smoothstep(25, 125, d)
    scal = 0.2 * abs(math.sin(a * 5))
    return base - scal


def paint(a, z, p):
    c = mix(GOLD_LO, GOLD_B, smoothstep(0.1, 1.2, z))
    c = mix(c, GOLD_T, smoothstep(1.6, 2.8, z))
    e = hood_edge(a)
    w = smoothstep(e - 0.04, e + 0.04, z)
    hood = mix(HOOD_D, HOOD, smoothstep(e, e + 0.8, z))
    return mix(c, hood, w)


b = Body([(0, 1.05), (0.12, 1.32), (0.5, 1.48), (1.1, 1.47), (1.8, 1.24), (2.45, 0.84), (2.85, 0.4), (H, 0)],
         paint=paint, segs=36, sub=2, gloss=0.75, lean=lambda z: 0.08 * max(0.0, (z - 2.2) / 0.8) ** 2)
parts = [b.obj]


def feather_poly(L, w, n=5, point=0.0):
    """feather: narrow quill end, widest ~60 %, round (or slightly pointed) tip."""
    top = []
    for k in range(n + 1):
        t = k / n
        x = t * L
        if t < 0.65:
            y = w / 2 * (0.4 + 0.6 * math.sin(math.pi / 2 * t / 0.65))
        else:
            q = (t - 0.65) / 0.35
            y = w / 2 * max(0.0, 1 - q ** (2 - point)) ** 0.5
        top.append((x, y))
    top[-1] = (L, 0.0)
    bot = [(x, -y) for x, y in reversed(top[1:-1])]
    return top + bot


def feather(name, root, d, N, L, w, cols, thick=0.11, bend=0.0, rows=2):
    d = Vector(d).normalized()
    y = d.cross(N).normalized()
    col = along(cols[0], cols[1], root, root + d * L, power=1.6)
    if len(cols) > 2:
        c0, c1, c2 = cols
        R = Vector(root)

        def col(p, n=None, R=R, d=d, L=L):
            t = min(1.0, max(0.0, (p - R).dot(d) / L))
            return mix(c0, c1, t / 0.6) if t < 0.6 else mix(c1, c2, (t - 0.6) / 0.4)
    o = puffy_slab(name, feather_poly(L, w), thick, tuple(root), tuple(d), tuple(y), col, rows=rows)
    if bend:
        R = Vector(root)
        for v in o.data.vertices:
            t = max(0.0, (v.co - R).dot(d) / L)
            v.co.z += bend * t * t
    return o


# ---- big wings: raised arm, long primaries fanning out-and-up, a row of coverts in front
def wing(sd):
    out = []
    root = b.point(math.radians(sd * 112), 1.6, -0.2)
    e_out = Vector((sd * 0.95, 0.35, 0)).normalized()
    e_up = Vector((0, 0.2, 1)).normalized()
    N = e_out.cross(e_up).normalized()

    def dirv(deg):
        th = math.radians(deg)
        return e_out * math.cos(th) + e_up * math.sin(th)
    arm = dirv(50)
    n = 6
    for i in range(n):
        t = i / (n - 1)
        o = root + arm * (0.12 + 1.15 * t) + N * (0.03 * i * sd)
        d = dirv(-68 + 100 * t)
        L = 0.95 + 0.95 * t ** 0.8
        out.append(feather(f"WingPrim{sd}{i}", o, d, N * sd, L, 0.55, (FEATH_D, FEATH, TIP)))
    for i in range(4):
        t = i / 3
        o = root + arm * (0.05 + 0.95 * t) - N * (0.12 * sd) + N * (0.02 * i * sd)
        d = dirv(-48 + 88 * t)
        L = 0.6 + 0.3 * t
        out.append(feather(f"WingCov{sd}{i}", o, d, N * sd, L, 0.48, (GOLD_B, GOLD_T), thick=0.13))
    arm_pts = [tuple(root + arm * (1.25 * k / 4) + e_up * 0.06 * math.sin(k / 4 * math.pi) - N * 0.07 * sd) for k in range(5)]
    out.append(horn(f"WingArm{sd}", arm_pts, [0.21, 0.19, 0.16, 0.13, 0.09], GOLD_B, GOLD_T, segs=8))
    return out


parts += wing(1) + wing(-1)

# ---- feather crest: white feathers swept back over the crown, gold tips
# a fan in a plane tilted back, so the feathers show their faces from the front (edge-on they read as spikes)
CX = Vector((1, 0, 0))
CB = Vector((0, 0.42, 1)).normalized()
CN = CX.cross(CB).normalized()
for k, (phi, L, w) in enumerate(((0, 1.25, 0.5), (-26, 1.05, 0.46), (26, 1.05, 0.46), (-50, 0.8, 0.4), (50, 0.8, 0.4))):
    ph = math.radians(phi)
    d = CB * math.cos(ph) + CX * math.sin(ph)
    root = Vector((0.06 * math.sin(ph), 0.2, H - 0.22)) + CN * (-0.05 * (k > 0) - 0.05 * (k > 2))
    parts.append(feather(f"Crest{k}", root, d, CN, L, w, (FEATH, TIP_L, TIP), thick=0.12))

# ---- lion tail: S-curve up behind the body, a tufted amber tip
ctrl = [(0.0, 1.2, 0.5), (0.25, 1.75, 0.6), (0.45, 2.05, 1.1), (0.5, 2.05, 1.7), (0.55, 1.9, 2.15)]
tp = [(x, y, z) for (x, z), (_, y) in zip(catmull([(c[0], c[2]) for c in ctrl], 3), catmull([(c[0], c[1]) for c in ctrl], 3))]
rad = [0.22 - 0.09 * (i / (len(tp) - 1)) for i in range(len(tp))]
parts.append(horn("Tail", tp, rad, GOLD_B, GOLD_T, segs=8))
tip = Vector(tp[-1])
parts.append(goo("TailTuft", [(tip + Vector((0, 0, 0.14)), 0.4, (1, 1, 1.2)), (tip + Vector((0.14, -0.05, 0.44)), 0.3),
                              (tip + Vector((-0.13, 0.07, 0.4)), 0.28), (tip + Vector((0, 0.02, 0.66)), 0.22)],
                 zgrad(AMBER, AMBER_L, tip.z - 0.2, tip.z + 0.6), resolution=0.07, tris=260))

# ---- proud face: half-lidded sky-blue eyes, white feather brows, hooked gold beak
f = Face(b, eye_v=1.7, eye_u=0.52, mouth_v=1.1)
f.eyes("sly", w=0.52, h=0.68, iris=IRIS)
for sd in (-1, 1):
    pts = [(sd * 0.22, 2.0), (sd * 0.8, 2.18), (sd * 0.9, 2.1), (sd * 0.3, 1.94)]
    f.d(f"Brow{sd}", pts, hexc("f5a63a"), off=0.02)
f.cheeks(color=hexc("ffa0a0"), w=0.26, h=0.12, u=0.86, v=1.38)
parts += f.parts

bp = b.point(0, 1.32, -0.12)
beak_col = zgrad(BEAK_D, hexc("ffd27a"), bp.z - 0.3, bp.z + 0.2)
parts.append(lathe("Beak", [(0, 0.4), (0.18, 0.38), (0.42, 0.26), (0.6, 0.12), (0.66, 0)], beak_col,
                   pos=tuple(bp), axis=(0, -1, -0.25), segs=10, sx=1.2, sy=0.95, smooth=True))
# the hook: a short curved tube from the beak tip down
bt = bp + Vector((0, -0.6, -0.15))
parts.append(horn("BeakHook", [tuple(bt + Vector((0, 0.05, 0.06))), tuple(bt + Vector((0, -0.04, -0.02))), tuple(bt + Vector((0, -0.02, -0.14)))],
                  [0.15, 0.11, 0.035], BEAK, BEAK_D, segs=8))

# ---- lion paws peeking out at the front foot, three toe beans each
for sd in (-1, 1):
    pp = b.point(math.radians(sd * 32), 0.26, 0.0)
    parts.append(ball(f"Paw{sd}", 0.34, tuple(pp + Vector((0, -0.08, 0))), zgrad(GOLD_LO, GOLD_T, 0.0, 0.5), squash=(1.0, 1.15, 0.62)))
    for t in (-1, 0, 1):
        tp2 = pp + Vector((t * 0.17 + sd * 0.02, -0.42 + 0.05 * abs(t), 0.06))
        parts.append(ball(f"Toe{sd}{t}", 0.11, tuple(tp2), GOLD_T, squash=(1, 1, 0.8), subdiv=1))

ship("slime_griffin", parts)
