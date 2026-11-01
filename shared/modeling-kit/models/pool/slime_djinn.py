# Djinn (Mythic, Starlight set): a blue genie slime floating out of a golden oil lamp. Broad shoulders
# and a round head, a magenta vest with gold trim and a gold sash; the lower body pours into a fat
# swirl of smoke that spirals down into the lamp's spout. Arms folded across the chest with gold cuffs,
# a curled goatee, a gold-ringed topknot with a long swaying ponytail, gold hoop earrings, a cocky
# grin, and a trail of gold sparkles winding round it. The lamp is the slime's bottom.
from models._slimepool import *

BLUE_D, BLUE, BLUE_L = hexc("2c78ec"), hexc("3e9cff"), hexc("8ad0ff")
ARM_D, ARM_L = hexc("3a8cfa"), hexc("9ad8ff")
SMOKE_D, SMOKE, SMOKE_L = hexc("4096fa"), hexc("74c0ff"), hexc("f0faff")
VEST_D, VEST = hexc("9a3ad8"), hexc("c45cf2")
HAIR_D, HAIR = hexc("4a50d8"), hexc("6c76f0")
G_LO, G_MID, G_HI = hexc("f8be30"), hexc("ffcf3a"), hexc("ffeb8a")
RUBY = hexc("ff3a6a")
INKD = hexc("1e1a4a")
KEY = Vector((-0.45, -0.6, 0.66)).normalized()


def gold(p, n):
    return mix(G_LO, G_HI, smoothstep(-0.5, 0.95, n.dot(KEY))) if n.length > 0 else G_MID


def litc(c0, c1, lo=0.3):
    return lambda p, n: mix(c0, c1, lo + (1 - lo) * max(0.0, n.dot(KEY)))


# ---------------------------------------------------------------- lamp (the bottom), long axis along X
LX = -0.3  # lamp centre: shifted left so the spout tip sits under the body
LAMP_TOP = 0.84
lamp = lathe("Lamp", [(0.0, 0.5), (0.06, 0.56), (0.12, 0.5), (0.18, 0.34), (0.24, 0.44), (0.36, 0.78), (0.5, 0.92),
                      (0.62, 0.86), (0.72, 0.6), (0.78, 0.4), (0.82, 0.44), (LAMP_TOP, 0.36), (0.9, 0.2), (1.0, 0.1), (1.04, 0.0)],
             gold, pos=(LX, 0, 0), segs=20, sub=0, sx=1.3)
parts = [lamp]
parts.append(torus("LampRim", 0.42, 0.045, (LX, 0, LAMP_TOP - 0.03), (0, 0, 1), gold, segs=16, rsegs=4))
sp = [(LX + 0.95, 0, 0.42), (LX + 1.38, 0, 0.5), (LX + 1.68, 0, 0.7), (LX + 1.84, 0, 0.98)]
spout = tube("LampSpout", sp, [0.27, 0.18, 0.13, 0.11], None, segs=10)
paint_fn(spout, gold)
parts.append(keep(spout, True))
TIP = Vector(sp[-1])
parts.append(torus("SpoutLip", 0.12, 0.04, TIP, (0.45, 0, 1), gold, segs=10, rsegs=4))
hd = [Vector((LX - 1.05 - 0.42 * math.sin(t), 0, 0.5 + 0.2 * math.cos(t))) for t in (math.pi * k / 9 for k in range(10))]
handle = tube("LampHandle", hd, [0.08] * len(hd), None, segs=6, twist_free=True)
paint_fn(handle, gold)
parts.append(keep(handle, True))
parts.append(gem("LampGem", (LX, -0.9, 0.52), 0.14, RUBY, axis=(0, -1, 0.1), h=0.15, segs=6))

# ---------------------------------------------------------------- body: round head on broad shoulders, tail into smoke
VEST_Z0, VEST_Z1 = 1.72, 2.68
SASH_Z0 = 1.52


def vest_open(z):
    """half-angle (deg) of the open front of the bolero vest: narrow at the neck, wide at the hem."""
    return 40 + 46 * smoothstep(VEST_Z1, VEST_Z0, z)


def vest_hem(ad):
    """hem height: low at the back, curving up towards the open front."""
    return VEST_Z0 + 0.1 + 0.25 * smoothstep(110, 60, ad)


def sectors(a, z):
    ad = abs(math.degrees(a))
    if SASH_Z0 <= z < VEST_Z0:
        return G_MID  # gold sash
    hem = vest_hem(ad)
    if hem - 0.12 <= z <= VEST_Z1 and ad >= vest_open(z):
        if z < hem:
            return G_MID  # gold trim along the hem
        return mix(VEST_D, VEST, smoothstep(VEST_Z0, VEST_Z1, z))
    return None


def paint(a, z, p):
    c = mix(BLUE_D, BLUE, smoothstep(1.6, 2.6, z))
    c = mix(c, BLUE_L, smoothstep(2.9, 3.8, z))
    c = mix(c, SMOKE, smoothstep(1.7, 1.35, z))
    return c


b = Body([(1.3, 0.4), (1.55, 0.66), (1.85, 0.98), (2.15, 1.32), (2.42, 1.56), (2.6, 1.36), (2.78, 1.12), (3.0, 1.18), (3.3, 1.22),
          (3.62, 1.04), (3.86, 0.62), (3.98, 0)],
         paint=paint, sectors=sectors, segs=32, sub=2, gloss=0.8, shade=0.55, tuck=0, dome=0)
parts.append(b.obj)
H = b.H

# ---------------------------------------------------------------- fat smoke swirl spiralling down into the spout
CTRL = [Vector((0.0, 0.05, 1.75)), Vector((-0.12, -0.05, 1.38)), Vector((-0.42, -0.12, 1.12)), Vector((-0.2, -0.2, 0.86)),
        Vector((0.32, -0.16, 0.8)), Vector((0.85, -0.06, 0.96)), TIP + Vector((-0.06, 0, 0.1)), TIP + Vector((0, 0, -0.02))]


def smoke_tail(name, ctrl, r0, r1, segs=12, per=4, turns=2.2):
    """tapered smoke tail along a Catmull path with two light spiral stripes running round it."""
    P = [ctrl[0]] + ctrl + [ctrl[-1]]
    path = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(per):
            t = k / per
            path.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    path.append(ctrl[-1])
    N = len(path)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    rings, info = [], {}
    q, prev = None, None
    for i, p in enumerate(path):
        d = (path[min(i + 1, N - 1)] - path[max(i - 1, 0)]).normalized()
        q = d.to_track_quat("Z", "Y") if q is None else prev.rotation_difference(d) @ q
        prev = d
        t = i / (N - 1)
        r = r0 + (r1 - r0) * t ** 0.8
        ring = []
        for k in range(segs):
            a = k * math.tau / segs
            v = bm.verts.new(p + q @ Vector((math.cos(a) * r, math.sin(a) * r, 0)))
            info[v] = (t, a)
            ring.append(v)
        rings.append(ring)
    for ra, rb in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((ra[k], ra[(k + 1) % segs], rb[(k + 1) % segs], rb[k]))
    c0 = bm.verts.new(path[0] - (path[1] - path[0]).normalized() * 0.01)
    c1 = bm.verts.new(path[-1] + (path[-1] - path[-2]).normalized() * r1)
    info[c0], info[c1] = (0.0, 0.0), (1.0, 0.0)
    for k in range(segs):
        bm.faces.new((rings[0][(k + 1) % segs], rings[0][k], c0))
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % segs], c1))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    for f in bm.faces:
        for lp in f.loops:
            t, a = info[lp.vert]
            stripe = smoothstep(0.2, 0.7, math.sin(2 * a + t * turns * math.tau))
            c = mix(SMOKE_D, SMOKE, 0.3 + 0.7 * t)
            c = mix(c, SMOKE_L, 0.8 * stripe)
            lp[col] = mix(c, WHITE, 0.2 * max(0.0, lp.vert.normal.dot(KEY)))
    return keep(obj_from_bm(name, bm), True)


parts.append(smoke_tail("Smoke", CTRL, 0.6, 0.11))

# ---------------------------------------------------------------- folded arms: two separate forearms, gold cuffs
ARMS = {  # side: (shoulder z, elbow, forearm path to the hand)
    1: (2.4, Vector((1.66, -0.3, 2.02)), [Vector((1.1, -1.24, 2.16)), Vector((0.15, -1.52, 2.18)), Vector((-0.8, -1.34, 2.16))]),
    -1: (2.36, Vector((-1.6, -0.3, 1.74)), [Vector((-1.04, -1.08, 1.66)), Vector((-0.15, -1.3, 1.64)), Vector((0.78, -1.12, 1.66))]),
}
for sd, (shz, el, fore) in ARMS.items():
    sh = b.point(math.radians(sd * 80), shz, -0.15)
    upper = [sh, sh + (el - sh) * 0.5 + Vector((sd * 0.1, -0.05, 0)), el]
    o = tube(f"Arm{sd}", upper + fore, [0.3, 0.27, 0.24, 0.22, 0.21, 0.2], None, segs=10, twist_free=True)
    paint_fn(o, litc(ARM_D, ARM_L, 0.2))
    parts.append(keep(o, True))
    hand = fore[-1]
    parts.append(ball(f"Fist{sd}", 0.24, hand + Vector((-sd * 0.06, 0.04, 0)), litc(ARM_D, ARM_L, 0.25), subdiv=2))
    d = (fore[-1] - fore[-2]).normalized()
    parts.append(torus(f"Cuff{sd}", 0.22, 0.075, fore[-2] + (fore[-1] - fore[-2]) * 0.55, d, gold, segs=12, rsegs=5))

# ---------------------------------------------------------------- face: big confident eyes, raised brow, grin, goatee
EV, EU = 3.28, 0.42
f = Face(b, eye_u=EU, eye_v=EV, mouth_v=2.98, s=1.0, ink=INKD)
for sd in (-1, 1):
    u = sd * EU
    f.d(f"Eye{sd}", oval(u, EV, 0.4, 0.54, n=16), INKD, off=0.015)
    f.d(f"EyeHi{sd}", oval(u - 0.07, EV + 0.1, 0.17, 0.17, n=10), WHITE, off=0.05, th=0.012)
    f.d(f"EyeHi2{sd}", oval(u + 0.08, EV - 0.13, 0.07, 0.07, n=8), WHITE, off=0.05, th=0.012)
    lift = 0.1 if sd > 0 else 0.0  # one brow cocked up
    rot = math.radians(-14 * sd) if sd < 0 else math.radians(10)
    f.d(f"Brow{sd}", rect(u, EV + 0.32 + lift * 0.6, 0.38, 0.1, rot), INKD, off=0.02)
f.mouth("smile", w=1.5)
parts += f.parts
# curled goatee: hangs from the chin, tip curls forward and up
chin = b.point(0, 2.8, -0.1)
gp = [chin, chin + Vector((0, -0.14, -0.16)), chin + Vector((0, -0.26, -0.32)), chin + Vector((0, -0.4, -0.44)),
      chin + Vector((0, -0.56, -0.46)), chin + Vector((0, -0.66, -0.36)), chin + Vector((0, -0.64, -0.26))]
goat = tube("Goatee", gp, [0.27, 0.22, 0.16, 0.1, 0.065, 0.04, 0.012], None, segs=8, twist_free=True)
paint_fn(goat, litc(hexc("2e2c90"), HAIR_D, 0.1))
parts.append(keep(goat, True))

# ---------------------------------------------------------------- topknot: gold ring + long swaying ponytail
TK = Vector((0, 0.15, H - 0.12))
tp = [TK, TK + Vector((0, 0.04, 0.22)), TK + Vector((0, 0.2, 0.42)), TK + Vector((0, 0.5, 0.5)), TK + Vector((0, 0.82, 0.36)),
      TK + Vector((0, 1.02, 0.02)), TK + Vector((0, 1.1, -0.36)), TK + Vector((0, 1.04, -0.7))]
tail = tube("TailKnot", tp, [0.26, 0.25, 0.22, 0.19, 0.16, 0.12, 0.08, 0.03], None, segs=8, twist_free=True)
paint_fn(tail, litc(HAIR_D, HAIR, 0.25))
parts.append(keep(tail, True))
parts.append(torus("KnotRing", 0.25, 0.08, TK + Vector((0, 0.03, 0.18)), (0, 0.2, 1), gold, segs=12, rsegs=5))

# ---------------------------------------------------------------- gold hoop earrings
for sd in (-1, 1):
    ear = b.point(math.radians(sd * 86), 3.22, 0.02)
    parts.append(torus(f"Earring{sd}", 0.17, 0.04, ear + Vector((sd * 0.05, 0, -0.2)), (1, 0, 0), gold, segs=10, rsegs=4))

# ---------------------------------------------------------------- magic sparkle trail winding up round it (Starlight)
for j in range(6):
    t = j / 5
    a = math.radians(-60 + t * 300)
    r = 2.05 - 0.2 * t
    pos = Vector((math.sin(a) * r, -math.cos(a) * r * 0.75, 0.9 + t * 2.9))
    s = 0.12 + 0.12 * t
    parts.append(puffy_slab(f"Spark{j}", star(0, 0, s, s * 0.3, n=4), 0.06, pos, (1, 0, 0), (0, 0, 1),
                            G_MID if j % 2 else WHITE, rows=1))
    if False:  # little dots between the sparkles
        a2 = math.radians(-60 + (t + 0.1) * 300)
        q = Vector((math.sin(a2) * (r - 0.02), -math.cos(a2) * (r - 0.02) * 0.75, 0.9 + (t + 0.1) * 2.9))
        parts.append(ball(f"SparkDot{j}", 0.05, q, G_HI, subdiv=1))

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_djinn", parts)
