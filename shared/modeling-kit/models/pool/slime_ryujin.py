# Ryujin (Divine hybrid: Lunara + Solaris + Supernova): the dragon-god slime. A moonlit lavender body
# that warms to sun-gold at the crown, wrapped by a long jade cloud dragon (Eastern dragon): its body
# coils once and a quarter round the slime, low across the front, high round the back, the neck over
# the crown and the head resting on top facing the viewer. Cream-gold belly plates, gold dorsal fins,
# small gold antlers, long flowing gold whiskers, a white cloud mane, a cloud tuft on the tail tip,
# and a glowing star pearl (Supernova's white-pink) held in a little claw at the front. The slime
# wears a calm, wise half-lidded smile with jade eyes.
#
# Rig names: the free tail end is cut into Tail0..Tail2 (each sways), the whiskers are Ant-1/Ant1.
from models._slimepool import *

LAV_D, LAV, LAV_L, SUN = hexc("a294ff"), hexc("bcaeff"), hexc("ddd6ff"), hexc("fff2b8")
JADE_D, JADE, JADE_L = hexc("48c88e"), hexc("6eeaac"), hexc("c0fadc")
BELLY, BELLY_D = hexc("fff2b8"), hexc("ffd46a")
GOLD_B, GOLD_M, GOLD_W = hexc("ffd254"), hexc("ffe47a"), hexc("fff8d4")
CLOUD, CLOUD_M = hexc("ffffff"), hexc("eefdf6")
PEARL_C, PEARL_P = hexc("fffaf4"), hexc("ffb6dc")
INKR = hexc("2a2050")


def paint(a, z, p):
    c = mix(LAV_D, LAV, smoothstep(0.0, 1.0, z))
    c = mix(c, LAV_L, smoothstep(1.2, 2.3, z))
    c = mix(c, SUN, 0.75 * smoothstep(2.35, 2.95, z))
    return c


b = Body([(0, 1.03), (0.14, 1.34), (0.55, 1.5), (1.2, 1.49), (1.85, 1.27), (2.4, 0.9), (2.8, 0.45), (3.0, 0)],
         paint=paint, segs=32, sub=2, gloss=0.8, shade=0.45)
parts = [b.obj]
H = b.H


# ---------------------------------------------------------------- the dragon's path (tail tip -> head)
def cyl(yaw, r, z):
    a = math.radians(yaw)
    return (math.sin(a) * r, -math.cos(a) * r, z)


CTRL = [cyl(122, 2.75, 1.5), cyl(126, 2.8, 1.02), cyl(148, 2.35, 0.6), cyl(180, 1.9, 0.5),  # free tail, curling up behind
        cyl(115, 1.84, 0.42), cyl(60, 1.86, 0.4), cyl(0, 1.86, 0.42), cyl(-60, 1.86, 0.55),  # low round the front
        cyl(-120, 1.8, 0.95), cyl(-180, 1.7, 1.45), cyl(-240, 1.55, 1.95),  # up round the back
        cyl(-290, 1.3, 2.45), (0.75, 0.55, 3.0), (0.85, 0.05, 3.3), (0.72, -0.35, 3.38)]  # neck over the crown


def path_pts(ctrl, n):
    P = [Vector(c) for c in ctrl]
    P = [P[0]] + P + [P[-1]]
    out = []
    nseg = len(ctrl) - 1
    for k in range(n):
        x = min(nseg - 1e-6, k / (n - 1) * nseg)
        i = int(x)
        t = x - i
        p0, p1, p2, p3 = P[i], P[i + 1], P[i + 2], P[i + 3]
        out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return out


NP = 76
PTS = path_pts(CTRL, NP)
LEN = [0.0]
for p, q in zip(PTS, PTS[1:]):
    LEN.append(LEN[-1] + (q - p).length)


def rad_at(s):
    """tube radius along the dragon, s 0 (tail tip) -> 1 (neck end)."""
    return 0.07 + 0.25 * smoothstep(0.0, 0.32, s) - 0.04 * smoothstep(0.85, 1.0, s)


# ring frames: "in" = towards the slime's axis (belly side), parallel-transported where that fails
FR = []
for i, p in enumerate(PTS):
    t = (PTS[min(i + 1, NP - 1)] - PTS[max(i - 1, 0)]).normalized()
    inn = Vector((-p.x, -p.y, -0.35))
    inn = (inn - t * inn.dot(t))
    if inn.length < 1e-3:
        inn = FR[-1][1]
    inn = inn.normalized()
    if i > len(PTS) - 12:  # the neck over the crown: belly down
        down = Vector((0, 0, -1)) - t * t.z
        w = smoothstep(len(PTS) - 12, len(PTS) - 6, i)
        inn = (inn * (1 - w) + down.normalized() * w).normalized()
    side = t.cross(inn).normalized()
    FR.append((t, inn, side))


def dragon_piece(name, i0, i1, rsegs=8):
    """tube from ring i0 to i1 (closed caps), belly plates on the inner side, scaled jade back."""
    bm = bmesh.new()
    rings, info = [], {}
    for i in range(i0, i1 + 1):
        p = PTS[i]
        t, inn, side = FR[i]
        s = i / (NP - 1)
        r = rad_at(s)
        ring = []
        for j in range(rsegs):
            th = j * math.tau / rsegs
            v = bm.verts.new(p + (inn * math.cos(th) + side * math.sin(th)) * r)
            info[v] = (LEN[i], math.cos(th))
            ring.append(v)
        rings.append(ring)
    for a, c in zip(rings, rings[1:]):
        for j in range(rsegs):
            bm.faces.new((a[j], a[(j + 1) % rsegs], c[(j + 1) % rsegs], c[j]))
    caps = [bm.faces.new(list(reversed(rings[0]))), bm.faces.new(rings[-1])]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            L, ci = info[lp.vert]
            belly = smoothstep(0.15, 0.45, ci)  # cos(theta) 1 = facing the slime
            plate = 0.5 + 0.5 * math.cos(L / 0.2 * math.tau)
            bc = mix(BELLY, BELLY_D, 0.55 * smoothstep(0.6, 0.95, plate))
            sc = 0.5 + 0.5 * math.cos(L / 0.16 * math.tau + ci * 3.0)
            jc = mix(JADE, JADE_D, 0.45 * smoothstep(0.55, 0.95, sc))
            jc = mix(jc, JADE_L, 0.5 * smoothstep(-0.3, -0.95, ci))  # light along the spine
            lp[col] = mix(jc, bc, belly)
    o = obj_from_bm(name, bm)
    return keep(o, True)


# free tail end in three swaying pieces, overlapping one ring so no gap opens
CUTS = [0, 6, 12, 19]
for k in range(3):
    parts.append(dragon_piece(f"Tail{k}", CUTS[k], CUTS[k + 1] + 1))
parts.append(dragon_piece("Dragon", CUTS[3], NP - 1))

# ---------------------------------------------------------------- gold dorsal fins along the spine
for k, i in enumerate(range(11, NP - 6, 6)):
    p = PTS[i]
    t, inn, side = FR[i]
    s = i / (NP - 1)
    r = rad_at(s)
    up = (-inn * 0.45 + Vector((0, 0, 1))).normalized()
    base = p + up * (r * 0.8)
    L = 0.42 + 0.1 * math.sin(k * 1.7)
    poly = [(-0.22, 0), (0.24, 0), (0.08, L * 0.45), (-0.2, L)]
    nm = f"Spine{k}"
    parts.append(puffy_slab(nm, poly, 0.06, tuple(base), tuple(-t), tuple(up),
                            lambda p_, n_, base=base, up=up, L=L: mix(GOLD_B, GOLD_W, smoothstep(0.0, L, (p_ - base).dot(up))), rows=1))

# cloud tuft on the tail tip
TT = PTS[0]
parts.append(goo("CloudTuft", [(TT, 0.26), (TT + Vector((0.15, 0.2, 0.18)), 0.2), (TT + Vector((-0.12, 0.15, 0.26)), 0.17),
                              (TT + Vector((0.05, 0.3, -0.05)), 0.18)],
                 lambda p, n: mix(CLOUD_M, CLOUD, smoothstep(-0.4, 0.5, n.z)), tris=160, resolution=0.06))

# ---------------------------------------------------------------- the head (built facing -Y at the origin, then placed)
HEAD_POS = PTS[-1] + Vector((0.0, -0.22, 0.12))
HEAD_DIR = Vector((-0.45, -1.0, -0.12)).normalized()  # snout points front, a bit to the viewer's left


def place(o, M):
    o.data.transform(M)
    o.data.update()
    return o


fwd = HEAD_DIR
right = fwd.cross(Vector((0, 0, 1))).normalized()
upv = right.cross(fwd).normalized()
# local frame: x = -right? local -Y = forward, +Z = up, +X = right side of the head
Mrot = Matrix(((-right.x, -fwd.x, upv.x), (-right.y, -fwd.y, upv.y), (-right.z, -fwd.z, upv.z))).to_4x4()
# local x maps to -right so the head's local +X ends up on the viewer's side consistently; columns are images of x, y, z
M = Matrix.Translation(HEAD_POS) @ Mrot @ Matrix.Scale(1.35, 4)

jade_lit = lambda p, n: mix(mix(JADE, hexc("8ef4c0"), 0.5 + 0.5 * n.z), JADE_L, 0.6 * smoothstep(0.3, 1.0, n.z))
head = []
head.append(ball("Skull", 0.4, (0, 0.05, 0.02), jade_lit, squash=(1.0, 1.15, 0.88)))
head.append(ball("Snout", 0.3, (0, -0.48, -0.04), jade_lit, squash=(0.82, 1.55, 0.66)))
head.append(ball("NosePad", 0.15, (0, -0.86, 0.02), lambda p, n: mix(JADE, JADE_L, 0.5 + 0.5 * n.z), squash=(1.2, 0.8, 0.8)))
head.append(ball("Jaw", 0.22, (0, -0.5, -0.24), lambda p, n: mix(BELLY_D, BELLY, 0.5 + 0.5 * n.z), squash=(0.8, 1.5, 0.45)))
for sd in (-1, 1):
    head.append(ball(f"DEye{sd}", 0.11, (sd * 0.25, -0.22, 0.17), GOLD_M, squash=(0.7, 1.0, 1.0), subdiv=1))
    head.append(ball(f"DPupil{sd}", 0.05, (sd * 0.31, -0.27, 0.17), INKR, squash=(0.6, 0.8, 1.4), subdiv=1))
    head.append(ball(f"DBrow{sd}", 0.1, (sd * 0.22, -0.2, 0.3), jade_lit, squash=(1.3, 1.6, 0.55), subdiv=1))
    head.append(ball(f"Nostril{sd}", 0.035, (sd * 0.08, -0.98, 0.06), JADE_D, subdiv=1))
    # antlers: gold, up and back with one forward tine
    a0 = Vector((sd * 0.17, 0.12, 0.28))
    ant = [a0, a0 + Vector((sd * 0.12, 0.2, 0.3)), a0 + Vector((sd * 0.22, 0.45, 0.55)), a0 + Vector((sd * 0.25, 0.68, 0.62))]
    head.append(horn(f"Horn{sd}", ant, [0.075, 0.065, 0.05, 0.02], GOLD_B, GOLD_W, segs=6))
    tb = ant[1].lerp(ant[2], 0.5)
    head.append(horn(f"Tine{sd}", [tb, tb + Vector((sd * 0.08, -0.12, 0.22))], [0.045, 0.015], GOLD_B, GOLD_W, segs=5))
for o in head:
    place(o, M)
parts += head

# whiskers (Ant*): long flowing gold barbels from the snout, waving back and down
for sd in (-1, 1):
    w0 = M @ Vector((sd * 0.18, -0.86, -0.02))
    sdir = (M.to_3x3() @ Vector((sd, 0, 0))).normalized()
    pts = [w0]
    for k in range(1, 7):
        t = k / 6
        pts.append(w0 + sdir * (1.0 * t) + HEAD_DIR * (-1.2 * t) + Vector((0, 0, -0.35 * t + 0.12 * math.sin(t * math.tau))))
    parts.append(horn(f"Ant{sd}", pts, [0.06, 0.055, 0.05, 0.045, 0.038, 0.028, 0.014], GOLD_M, GOLD_W, segs=5))

# cloud mane: white puffs behind the skull and down the neck, small tufts further along the spine
def puff(name, c, r, squash=(1, 1, 1)):
    return ball(name, r, tuple(c), lambda p, n: mix(mix(CLOUD_M, CLOUD, smoothstep(-0.6, 0.2, n.z)), CLOUD, 0.5), squash=squash, subdiv=2)


for k, (loc, r) in enumerate((((0, 0.35, 0.18), 0.3), ((0.2, 0.42, -0.02), 0.24), ((-0.2, 0.42, -0.02), 0.24))):
    parts.append(puff(f"Mane{k}", M @ Vector(loc), r))
for k, i in enumerate((NP - 13, NP - 24)):
    p = PTS[i]
    t, inn, side = FR[i]
    parts.append(puff(f"ManeN{k}", p - inn * rad_at(i / (NP - 1)) * 0.85, 0.22 - 0.03 * k, (1.2, 1.2, 0.9)))

# ---------------------------------------------------------------- glowing star pearl held in a little claw at the front
PC = Vector((1.55, -1.25, 1.55))
key = Vector((-0.35, -0.75, 0.55)).normalized()
parts.append(ball("Pearl", 0.36, tuple(PC), lambda p, n: mix(PEARL_P, PEARL_C, 0.25 + 0.75 * max(0.0, n.dot(key)) ** 0.7), subdiv=2))
parts.append(torus("PearlRing", 0.52, 0.035, tuple(PC), (0.35, -0.3, 1), lambda p, n: mix(GOLD_M, GOLD_W, 0.5 + 0.5 * n.z), segs=20, rsegs=4))
for j, (x, y, z, r) in enumerate([(2.15, -1.0, 2.05, 0.13), (1.0, -1.6, 2.0, 0.1), (2.1, -1.35, 1.15, 0.09)]):
    parts.append(slab(f"Twinkle{j}", star(0, 0, r * 1.6, r * 0.4, n=4), 0.05, (x, y, z), (1, 0, 0), (0, 0.25, 1), PEARL_P))
# claw: a short jade foreleg from the coil, three gold talons cupping the pearl from below
ci = int(0.49 * NP)
lp = PTS[ci]
leg = [lp, lp.lerp(PC, 0.45) + Vector((0, 0, -0.15)), PC + Vector((0.05, 0.12, -0.38))]
parts.append(horn("Leg", leg, [0.13, 0.11, 0.1], JADE, JADE_L, segs=7))
for j, ang in enumerate((-50, 10, 70)):
    a = math.radians(ang)
    root = PC + Vector((0.05, 0.12, -0.36))
    d = Vector((math.cos(a) * 0.9, math.sin(a) * 0.5 - 0.3, 0.0)).normalized()
    tal = [root, PC + d * 0.33 + Vector((0, 0, -0.18)), PC + d * 0.36 + Vector((0, 0, 0.0))]
    parts.append(horn(f"Talon{j}", tal, [0.06, 0.05, 0.015], GOLD_B, GOLD_W, segs=5))

# ---------------------------------------------------------------- calm, wise face
f = Face(b, eye_u=0.5, eye_v=1.58, mouth_v=1.15, ink=INKR)
f.eyes("sly", iris=hexc("2fc488"))
f.mouth("smile", w=1.1)
f.cheeks(color=hexc("ffa0c8"), w=0.28, h=0.13)
parts += f.parts

ship("slime_ryujin", parts)
