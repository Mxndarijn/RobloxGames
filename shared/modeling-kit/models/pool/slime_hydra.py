# Hydra (Secret, merge-only hybrid of three Sirens): a three-headed sea serpent slime. Sea-green scaly
# body that is the middle head (fierce slit-pupil eyes, fangs), two serpent necks rising from the
# shoulders: the viewer's right head is awake and smirking, the left one is always fast asleep with a
# floating "Zzz". Glowing aqua spines run down the back and the necks, coral siren fins frame the
# middle head, and a serpent tail with a glowing fluke curls behind.
from models._slimepool import *

G_D, G, G_L = hexc("36bc78"), hexc("44d884"), hexc("98f4a8")
BELLY, BELLY_L = hexc("c8f08a"), hexc("eeffb8")
SCALE = hexc("2aa86c")
GLOW_D, GLOW, GLOW_L = hexc("30f0dc"), hexc("6afff2"), hexc("e0fffb")
FIN_D, FIN_L = hexc("ff6f96"), hexc("ffc0d4")
IRIS = hexc("ffe14a")
INKG = hexc("123024")
MOUTH_G = hexc("5a1838")
ZZZ = hexc("eafcff")
KEY = Vector((-0.45, -0.6, 0.66)).normalized()


def lit(c0, c1, lo=0.25):
    return lambda p, n: mix(c0, c1, lo + (1 - lo) * max(0.0, n.dot(KEY)))


def paint(a, z, p):
    ad = abs(math.degrees(a))
    c = mix(G_D, G, smoothstep(0.1, 1.2, z))
    c = mix(c, G_L, smoothstep(1.9, 2.8, z))
    # pale belly on the front below the mouth
    bel = smoothstep(55, 30, ad) * smoothstep(1.35, 1.0, z)
    c = mix(c, mix(BELLY, BELLY_L, smoothstep(0.3, 1.0, z)), bel)
    # scale rows: staggered darker crescents on the back and sides
    if bel < 0.5:
        R = 1.45
        u, v = a * R / 0.56, z / 0.42
        row = math.floor(v)
        u += 0.5 * (row % 2)
        fu, fv = u - math.floor(u) - 0.5, v - row
        d = math.hypot(fu, (fv - 0.2) * 0.9)
        edge = smoothstep(0.32, 0.5, d) * smoothstep(0.25, 0.6, z)
        c = mix(c, SCALE, 0.45 * edge * (1 - bel))
        c = mix(c, G_L, 0.25 * smoothstep(0.25, 0.0, d) * (1 - bel))
    c = mix(c, GLOW, 0.7 * smoothstep(0.32, 0.0, z))  # glowing foot
    return c


H = 2.75
b = Body([(0, 1.08), (0.14, 1.42), (0.55, 1.56), (1.15, 1.5), (1.75, 1.26), (2.3, 0.86), (2.62, 0.42), (H, 0)],
         paint=paint, segs=40, sub=2, gloss=0.7, shade=0.65)
parts = [b.obj]


# ---------------------------------------------------------------- side necks + serpent heads
def head_paint(C):
    def fn(p, n):
        c = mix(G_D, G_L, smoothstep(-0.35, 0.45, (p - C).z))
        c = mix(c, BELLY, 0.85 * smoothstep(-0.05, -0.32, (p - C).z) * smoothstep(0.0, -0.4, (p - C).y))  # pale jaw
        return mix(c, WHITE, 0.25 * max(0.0, n.dot(KEY)) ** 4)
    return fn


HEADS = {}
for sd in (-1, 1):
    root = b.point(math.radians(sd * 68), 1.75, -0.35)
    C = Vector((sd * 1.52, -0.3, 3.15 + (0.1 if sd > 0 else -0.06)))
    ctrl = [root, root + Vector((sd * 0.35, 0.25, 0.55)), Vector((sd * 1.65, 0.12, 2.5)), C + Vector((0, 0.32, -0.22))]
    pts = [Vector(q) for q in (lambda P: [P[0]] + P + [P[-1]])(ctrl)]
    path = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for k in range(4):
            t = k / 4
            path.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    path.append(pts[-2])
    N = len(path)
    neck = tube(f"Neck{sd}", path, [0.46 - 0.14 * (k / (N - 1)) for k in range(N)], None, segs=12, twist_free=True)
    paint_fn(neck, lambda p, n: mix(mix(G_D, G, 0.5 + 0.5 * max(0.0, n.dot(KEY))), BELLY, 0.7 * smoothstep(-0.3, -0.8, n.y)))
    parts.append(keep(neck, True))
    # head: rounded serpent skull, snout forward
    hd = ball(f"Head{sd}", 0.68, C, head_paint(C), squash=(1.0, 1.0, 0.84), subdiv=3)
    parts.append(register(hd, f"Head{sd}"))
    sn = ball(f"Snout{sd}", 0.46, C + Vector((0, -0.5, -0.17)), head_paint(C), squash=(1.0, 1.0, 0.7), subdiv=2)
    parts.append(register(sn, f"Snout{sd}"))
    HEADS[sd] = C
    # glowing crest spikes on the skull, tilted back
    for j, (dy, dz, L, tilt) in enumerate(((-0.12, 0.5, 0.42, 0.25), (0.18, 0.5, 0.5, 0.6), (0.45, 0.36, 0.38, 1.0))):
        base = C + Vector((0, dy, dz))
        parts.append(crystal(f"Crest{sd}{j}", tuple(base), (sd * 0.12, tilt, 1), L, 0.12, GLOW_D, GLOW_L, segs=5))
    # coral siren frills on the sides of the head
    for e in (-1, 1):
        r0 = C + Vector((e * 0.6, 0.05, 0.05))
        X = Vector((e, 0.35, 0.3)).normalized()
        parts.append(puffy_slab(f"Frill{sd}{e}", [(0, -0.14), (0.3, -0.22), (0.48, -0.06), (0.4, 0.06), (0.52, 0.2), (0.22, 0.2), (0, 0.12)],
                                0.06, r0, X, (0, 0.25, 1), lambda p, n, r=r0, X=X: mix(FIN_D, FIN_L, smoothstep(0.05, 0.45, (p - r).dot(X))), rows=1))
    # glowing spines down the back of the neck
    for j, t in enumerate((0.25, 0.45, 0.65)):
        i = int(t * (N - 1))
        tg = (path[i + 1] - path[i - 1]).normalized()
        up = Vector((0, 1, 0.6)).normalized()
        out = (up - tg * up.dot(tg)).normalized()
        r = 0.4 - 0.14 * t
        parts.append(crystal(f"NeckSpine{sd}{j}", tuple(path[i] + out * (r - 0.08)), tuple(out + Vector((0, 0, 0.2))), 0.32, 0.09, GLOW_D, GLOW_L, segs=5))


def hdecal(name, sd, poly, color, off=0.02, th=0.025):
    C = HEADS[sd]
    return decal(name, [(C.x + u, C.z + v) for u, v in poly], color, FRONT, off=off, th=th, on=[f"Head{sd}", f"Snout{sd}"])


# viewer's right head: awake, smirking (eyes named Eye* so they blink with the middle face)
for e in (-1, 1):
    parts.append(hdecal("Eye1" if e > 0 else "Eye-1", 1, oval(e * 0.27, 0.13, 0.27, 0.31, n=14), INKG, off=0.015))
    parts.append(hdecal(f"Iris{e}", 1, oval(e * 0.27, 0.12, 0.19, 0.23, n=12), IRIS, off=0.03, th=0.012))
    parts.append(hdecal(f"Pupil{e}", 1, oval(e * 0.27, 0.12, 0.06, 0.19, n=8), INKG, off=0.04, th=0.01))
    parts.append(hdecal(f"EyeHi{e}", 1, oval(e * 0.27 - 0.04, 0.17, 0.06, 0.06, n=6), WHITE, off=0.05, th=0.01))
parts.append(hdecal("MouthR", 1, arc(0.05, -0.12, 0.17, 210, 320, 0.05, n=8), MOUTH_G))
parts.append(hdecal("FangR", 1, [(0.13, -0.27), (0.2, -0.26), (0.165, -0.36)], WHITE, off=0.04, th=0.015))
# viewer's left head: asleep (closed arcs, no blink), little smile, Zzz
for e in (-1, 1):
    parts.append(hdecal(f"LashS{e}", -1, arc(e * 0.27, 0.16, 0.11, 200, 340, 0.055, n=8), INKG))
parts.append(hdecal("MouthS", -1, arc(0, -0.08, 0.1, 210, 330, 0.045, n=6), MOUTH_G))
for e in (-1, 1):
    parts.append(hdecal(f"Nostril{e}", -1, oval(e * 0.09, -0.02, 0.05, 0.035, n=6), shade(G_D, 0.8), off=0.02, th=0.012))
    parts.append(hdecal(f"NostrilR{e}", 1, oval(e * 0.09, -0.02, 0.05, 0.035, n=6), shade(G_D, 0.8), off=0.02, th=0.012))


def zee(s):
    w, t = s, s * 0.28
    return [(-w / 2, w / 2), (w / 2, w / 2), (w / 2, w / 2 - t), (-w / 2 + t * 1.3, -w / 2 + t), (w / 2, -w / 2 + t), (w / 2, -w / 2),
            (-w / 2, -w / 2), (-w / 2, -w / 2 + t), (w / 2 - t * 1.3, w / 2 - t), (-w / 2, w / 2 - t)]


C = HEADS[-1]
for j, (dx, dz, s) in enumerate(((-0.62, 0.55, 0.22), (-0.92, 0.82, 0.29), (-1.28, 1.12, 0.36))):
    parts.append(slab(f"Zzz{j}", zee(s), 0.08, C + Vector((dx, -0.2, dz)), (1, 0, 0.12 * j), (0, 0, 1), ZZZ))

# ---------------------------------------------------------------- middle head face: fierce slit eyes, fangs
EV, EU = 1.68, 0.5
f = Face(b, eye_u=EU, eye_v=EV, mouth_v=1.22, s=1.0, ink=INKG, mouth_col=MOUTH_G)
for sd in (-1, 1):
    u = sd * EU
    pts = oval(u, EV, 0.5, 0.56, n=16)
    pts = [(x, min(y, EV + 0.2 + (x - u) * 0.35 * sd)) for x, y in pts]  # fierce lid slant
    f.d(f"Eye{sd}", pts, INKG, off=0.015)
    ip = [(x, min(y, EV + 0.15 + (x - u) * 0.35 * sd)) for x, y in oval(u, EV - 0.03, 0.38, 0.44, n=14)]
    f.d(f"Iris{sd}", ip, IRIS, off=0.03, th=0.012)
    f.d(f"Pupil{sd}", oval(u, EV - 0.04, 0.09, 0.34, n=10), INKG, off=0.04, th=0.01)
    f.d(f"EyeHi{sd}", oval(u - 0.1, EV + 0.06, 0.1, 0.08, n=8), WHITE, off=0.05, th=0.012)
f.mouth("fangs", w=1.15)
parts += f.parts

# ---------------------------------------------------------------- coral siren fins either side of the middle head
FIN = [(0, -0.22), (0.45, -0.32), (0.75, -0.12), (0.62, 0.0), (0.85, 0.16), (0.6, 0.24), (0.68, 0.45), (0.3, 0.36), (0, 0.24)]
for sd in (-1, 1):
    root = b.point(math.radians(sd * 92), 1.85, -0.1)
    X = Vector((sd * 1, 0.3, 0.35)).normalized()
    Y = Vector((0, 0.2, 1)).normalized()
    parts.append(puffy_slab(f"Fin{sd}", FIN, 0.08, root, X, Y,
                            lambda p, n, r=root, X=X: mix(FIN_D, FIN_L, smoothstep(0.1, 0.8, (p - r).dot(X))), rows=2))

# ---------------------------------------------------------------- glowing crest on the middle head + back spines
for j, (y, L, tilt) in enumerate(((-0.25, 0.5, 0.15), (0.2, 0.6, 0.5))):
    q = b.point(math.pi, 2.7, 0) if y > 0 else Vector((0, y, H - 0.04))
    if y > 0:
        q = Vector((0, y, H - 0.08))
    parts.append(crystal(f"Crown{j}", tuple(q - Vector((0, 0, 0.05))), (0, tilt, 1), L, 0.17, GLOW_D, GLOW_L, segs=5))
for k, z in enumerate((2.45, 2.05, 1.62, 1.18, 0.75)):
    q = b.point(math.pi, z, -0.08)
    d = (q - Vector((0, 0, z - 0.25))).normalized()
    L = 0.5 - 0.06 * abs(k - 1)
    parts.append(crystal(f"Spine{k}", tuple(q), tuple(d), L, 0.14, GLOW_D, GLOW_L, segs=5))

# ---------------------------------------------------------------- serpent tail curling behind, glowing fluke
tp = [Vector(q) for q in ((0.2, 1.1, 0.3), (0.55, 1.75, 0.3), (0.9, 2.25, 0.5), (0.85, 2.55, 0.95), (0.45, 2.5, 1.3))]
tail = tube("Tail", tp, [0.42, 0.33, 0.24, 0.16, 0.1], None, segs=10, twist_free=True)
paint_fn(tail, lambda p, n: mix(G_D, G, 0.4 + 0.6 * max(0.0, n.dot(Vector((0, 0.3, 1)).normalized()))))
parts.append(keep(tail, True))
fl = [(0, 0), (0.25, 0.3), (0.5, 0.42), (0.38, 0.12), (0.55, -0.12), (0.25, -0.1)]
parts.append(puffy_slab("Fluke", fl, 0.07, tp[-1] + Vector((0.02, 0, -0.02)), (-0.55, 0.0, 0.5), (0.1, 1, 0.1),
                        lambda p, n: mix(GLOW_D, GLOW_L, smoothstep(0.0, 0.5, (p - tp[-1]).length)), rows=2))

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_hydra", parts)
