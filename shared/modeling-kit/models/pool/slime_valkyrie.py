# Valkyrie (Divine): a winged warrior-maiden slime. Bright azure body under a polished chrome-silver
# helmet (gold brim, gold crest, blue brow gem) with big sculpted feather wings (long primaries plus
# gold-rooted coverts), two long golden braids falling from under the helmet down its sides with silver
# cuffs, a royal-red cape with a gold hem flowing down its back onto the ground, a silver armoured
# collar with a gold rim and a blue gem, a gold rune halo floating over the head, a big floating spear
# of light with winged guard, a silver shield with gold rim, rivets and a winged-star emblem, floating
# feathers and light motes, and a fierce battle-cry face: angry gold-iris eyes, hard brows, war paint.
#
# Rig names: wings Wing*, braids RibbonBraid-1/1, cape RibbonCape (they sway).
from models._slimepool import *

AZ_D, AZ, AZ_L = hexc("3d9cff"), hexc("62b6ff"), hexc("9ad2ff")
# chrome silver: bright sky reflection above, a cool darker horizon band, light ground bounce below
SIL_HI, SIL, SIL_M, SIL_D = hexc("ffffff"), hexc("e6eefa"), hexc("c2d0e8"), hexc("a4b6d8")
GOLD_B, GOLD_M, GOLD_W = hexc("ffd65c"), hexc("ffe47c"), hexc("fff8d0")
HAIR_D, HAIR, HAIR_L = hexc("ffd060"), hexc("ffe680"), hexc("fff6c0")
CAPE_D, CAPE, CAPE_L = hexc("dc3040"), hexc("f0404c"), hexc("ff5a5e")
FEATH, FEATH_T = hexc("ffffff"), hexc("ffe9a0")
LIGHT_C, LIGHT_W = hexc("ffe680"), hexc("fffbe8")
GEM = hexc("6cc8ff")
INKV = hexc("1e2a5a")


def paint(a, z, p):
    c = mix(AZ_D, AZ, smoothstep(0.0, 0.9, z))
    return mix(c, AZ_L, smoothstep(1.0, 2.1, z))


b = Body([(0, 1.05), (0.14, 1.36), (0.55, 1.53), (1.2, 1.52), (1.85, 1.3), (2.4, 0.94), (2.8, 0.48), (3.0, 0)],
         paint=paint, segs=26, sub=2, gloss=0.8, shade=0.45)
parts = [b.obj]
H = b.H
key = Vector((-0.55, -0.7, 0.45)).normalized()


def chrome(p, n):
    """chrome-silver by normal: white sky reflection on top, cool horizon band, lighter bounce below,
    a sharp white glint on the upper front-left."""
    t = n.z
    c = mix(SIL_M, SIL_D, smoothstep(-0.3, 0.2, t))
    c = mix(c, SIL, smoothstep(0.3, 0.55, t))
    c = mix(c, SIL_HI, smoothstep(0.8, 0.98, t))
    return mix(c, SIL_HI, 0.85 * smoothstep(0.88, 0.97, n.dot(key)))


def gold(p, n):
    return mix(GOLD_B, GOLD_W, 0.3 + 0.7 * max(0.0, n.dot(Vector((-0.3, -0.5, 0.8)).normalized())))


def frame_tube(name, pts, radii, color_fn, segs=6):
    """tube with parallel-transported rings; color_fn(L, theta, p, n) per corner (L = arc length)."""
    bm = bmesh.new()
    n_ = len(pts)
    rings, info = [], {}
    L = 0.0
    ref = None
    for i, p in enumerate(pts):
        if i:
            L += (pts[i] - pts[i - 1]).length
        t = (pts[min(i + 1, n_ - 1)] - pts[max(i - 1, 0)]).normalized()
        ref = Vector((0, 0, 1)) if ref is None else ref
        ref = (ref - t * ref.dot(t))
        if ref.length < 1e-4:
            ref = Vector((1, 0, 0)) - t * t.x
        ref = ref.normalized()
        side = t.cross(ref)
        ring = []
        for j in range(segs):
            th = j * math.tau / segs
            v = bm.verts.new(p + (ref * math.cos(th) + side * math.sin(th)) * radii[i])
            info[v] = (L, th)
            ring.append(v)
        rings.append(ring)
    for a, c in zip(rings, rings[1:]):
        for j in range(segs):
            bm.faces.new((a[j], a[(j + 1) % segs], c[(j + 1) % segs], c[j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    col = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            Lv, th = info[lp.vert]
            lp[col] = color_fn(Lv, th, lp.vert.co, lp.vert.normal)
    return keep(obj_from_bm(name, bm), True)


# ---------------------------------------------------------------- helmet: chrome cap over the crown
HZ = 2.08
prof = [(HZ + (H - HZ) * (k / 8) ** 0.9, b.radius(HZ + (H - HZ) * (k / 8) ** 0.9) + 0.07) for k in range(9)]
prof[-1] = (H + 0.07, 0.0)
parts.append(lathe("Helmet", prof, chrome, segs=24, smooth=True))
parts.append(torus("Brim", b.radius(HZ + 0.05) + 0.07, 0.09, (0, 0, HZ + 0.05), (0, 0, 1), gold, segs=28, rsegs=3))
crest = []
for k in range(9):
    t = math.radians(-70 + 140 * k / 8)
    crest.append(Vector((0, math.sin(t) * 1.5, 1.45 + math.cos(t) * 1.66)))
parts.append(horn("Crest", crest, [0.07, 0.1, 0.12, 0.13, 0.13, 0.13, 0.12, 0.1, 0.07], GOLD_M, GOLD_W, segs=5))
parts.append(gem("BrowGem", (0, -b.radius(HZ + 0.12) - 0.14, HZ + 0.14), 0.14, GEM, h=0.28, axis=(0, -1, 0), segs=6))


# ---------------------------------------------------------------- sculpted feather wings
def feather_poly(L, W, n=5):
    right = [(W / 2 * math.sin(math.pi * min(1.0, (k / n) * 1.15)) ** 0.7 * (1 - 0.35 * k / n), L * k / n) for k in range(1, n)]
    left = [(-x * 0.75, y) for x, y in reversed(right)]
    return [(-W * 0.18, 0), (W * 0.18, 0)] + right + [(0.05 * W, L)] + left


for sd in (-1, 1):
    root = b.point(math.radians(sd * 80), 2.42, 0.02)
    # long primaries: fan from up to out, tips bent up (sweep)
    for i, (L, ang) in enumerate(((2.45, 72), (2.2, 52), (1.8, 32), (1.3, 13))):
        a = math.radians(ang)
        d = Vector((sd * math.cos(a), 0.32, math.sin(a))).normalized()
        X = d.cross(Vector((0, -1, 0.15))).normalized()
        o = root + Vector((0, 0.1 + 0.04 * i, -0.05 * i))
        col = lambda p, n, o=o, d=d, L=L: mix(FEATH_T, FEATH, smoothstep(0.0, 0.4 * L, (p - o).dot(d)))
        parts.append(puffy_slab(f"Wing{sd}{i}", feather_poly(L, 0.6 - 0.03 * i), 0.1, tuple(o), tuple(X), tuple(d), col, rows=1))
    # coverts: shorter gold-rooted feathers layered in front of the primaries
    for i, (L, ang) in enumerate(((1.3, 58), (1.0, 30))):
        a = math.radians(ang)
        d = Vector((sd * math.cos(a), 0.2, math.sin(a))).normalized()
        X = d.cross(Vector((0, -1, 0.15))).normalized()
        o = root + Vector((0, -0.08, 0.0))
        col = lambda p, n, o=o, d=d, L=L: mix(GOLD_M, FEATH, smoothstep(0.1 * L, 0.65 * L, (p - o).dot(d)))
        parts.append(puffy_slab(f"WingC{sd}{i}", feather_poly(L, 0.5), 0.12, tuple(o), tuple(X), tuple(d), col, rows=1))
    parts.append(ball(f"WingRoot{sd}", 0.22, tuple(root + Vector((0, -0.05, 0.05))), gold, squash=(0.8, 1.0, 1.0), subdiv=1))

# ---------------------------------------------------------------- golden braids from under the helmet
for sd in (-1, 1):
    pts = []
    N = 16
    for k in range(N):
        t = k / (N - 1)
        yaw = math.radians(sd * (64 + 22 * t))
        z = 2.0 - 1.55 * t
        pts.append(b.point(yaw, z, 0.2 + 0.18 * math.sin(t * math.pi)))
    radii = [0.19 * (1 - 0.3 * k / (N - 1)) * (1 + 0.2 * abs(math.sin(k * math.pi / 2.0))) for k in range(N)]

    def plait(L, th, p, n):
        k = int(L / 0.24)
        s = math.sin(th + (0.8 if k % 2 else -0.8))
        c = mix(HAIR_D, HAIR, smoothstep(-0.6, 0.4, s))
        c = mix(c, HAIR_L, 0.6 * smoothstep(0.5, 1.0, n.dot(key)))
        f = (L / 0.24) % 1.0
        return mix(c, HAIR_D, 0.5 * smoothstep(0.82, 0.98, f))
    parts.append(frame_tube(f"RibbonBraid{sd}", pts, radii, plait, segs=6))
    end = pts[-1]
    parts.append(lathe(f"BraidCuff{sd}", [(-0.1, 0.17), (0.1, 0.17)], chrome, pos=tuple(end + (end - pts[-2]).normalized() * 0.02),
                       axis=tuple((end - pts[-2]).normalized()), segs=8))
    parts.append(ball(f"BraidTuft{sd}", 0.17, tuple(end + (end - pts[-2]).normalized() * 0.2), lambda p, n: mix(HAIR, HAIR_L, 0.5 + 0.5 * n.z),
                      squash=(0.8, 0.8, 1.4), subdiv=1))

# ---------------------------------------------------------------- royal red cape down the back onto the ground
def cape_pt(s, t):
    w = 0.62 + 0.38 * t  # narrow at the shoulders, wide at the hem
    yaw = math.radians(180 + (s - 0.5) * 150 * w)  # across the back
    z = 1.98 - 1.93 * t
    r = Body.radius_of(b.prof, max(z, 0.35)) + 0.12 + 0.75 * t ** 2.2
    r += 0.09 * math.sin(s * math.tau * 3.0) * t ** 1.3  # folds
    return Vector((math.sin(yaw) * r, -math.cos(yaw) * r, z))


def shell(name, fn, nu, nv, thick, color):
    bm = bmesh.new()
    P = [[fn(i / nu, j / nv) for j in range(nv + 1)] for i in range(nu + 1)]

    def nrm(i, j):
        a = P[min(i + 1, nu)][j] - P[max(i - 1, 0)][j]
        c = P[i][min(j + 1, nv)] - P[i][max(j - 1, 0)]
        return a.cross(c).normalized()
    outer = [[bm.verts.new(P[i][j] + nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    inner = [[bm.verts.new(P[i][j] - nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1]))
            bm.faces.new((inner[i][j + 1], inner[i + 1][j + 1], inner[i + 1][j], inner[i][j]))
    for i in range(nu):
        for j in (0, nv):
            bm.faces.new((outer[i][j], inner[i][j], inner[i + 1][j], outer[i + 1][j]))
    for j in range(nv):
        for i in (0, nu):
            bm.faces.new((outer[i][j], outer[i][j + 1], inner[i][j + 1], inner[i][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm)
    paint_fn(o, color)
    return keep(o, True)


def cape_col(p, n):
    c = mix(CAPE_D, CAPE, smoothstep(0.0, 1.6, p.z))
    c = mix(c, CAPE_L, 0.5 * smoothstep(0.3, 0.9, n.dot(Vector((0.3, 0.6, 0.5)).normalized())))
    return mix(c, GOLD_M, smoothstep(0.17, 0.11, p.z))  # gold hem


cape = shell("RibbonCape", cape_pt, 11, 6, 0.07, cape_col)
for v in cape.data.vertices:
    v.co.z = max(v.co.z, 0.02)
parts.append(cape)

# ---------------------------------------------------------------- armoured collar (gorget) with a gold rim and a gem
CZ = 0.86
parts.append(torus("Collar", b.radius(CZ) + 0.05, 0.14, (0, 0, CZ), (0, 0, 1),
                   lambda p, n: mix(chrome(p, n), GOLD_M, smoothstep(0.55, 0.75, n.z)), segs=28, rsegs=5))
parts.append(gem("CollarGem", (0, -b.radius(CZ) - 0.2, CZ), 0.15, GEM, h=0.3, axis=(0, -1, 0), segs=6))
for sd in (-1, 1):  # little gold wing flourishes either side of the gem
    parts.append(slab(f"CollarWing{sd}", [(0, 0), (sd * 0.38, 0.12), (sd * 0.3, 0.02), (sd * 0.4, -0.04), (sd * 0.22, -0.08)], 0.04,
                      tuple(b.point(math.radians(sd * 9), CZ, 0.17)), (1, 0, 0), (0, 0.15, 1), GOLD_M))

# ---------------------------------------------------------------- rune halo over the head, tilted to the face
HC = Vector((0, 0.5, 3.45))
hn = Vector((0, -0.6, 1)).normalized()
hq = hn.to_track_quat("Z", "Y")
parts.append(torus("Halo", 0.95, 0.07, tuple(HC), tuple(hn), lambda p, n: mix(GOLD_M, GOLD_W, 0.4 + 0.6 * max(0.0, n.z)), segs=26, rsegs=4))
for k in range(6):
    a = k * math.tau / 6 + math.pi / 6
    q = HC + hq @ Vector((math.cos(a) * 0.95, math.sin(a) * 0.95, 0))
    parts.append(slab(f"Rune{k}", [(0, -0.17), (0.1, 0), (0, 0.17), (-0.1, 0)], 0.05, tuple(q + Vector((0, -0.1, 0))), (1, 0, 0),
                      (0, 0.2, 1), LIGHT_W))

# ---------------------------------------------------------------- spear of light (viewer's right)
S0 = Vector((2.15, 0.25, 0.3))
S1 = Vector((2.35, 0.1, 3.05))
sd_ = (S1 - S0).normalized()
SL = (S1 - S0).length
parts.append(lathe("Spear", [(0, 0.09), (0.1, 0.11), (SL, 0.09)],
                   lambda p, n: mix(gold(p, n), LIGHT_W, 0.8 * smoothstep(0.5, 1.0, (p - S0).dot(sd_) / SL)),
                   pos=tuple(S0), axis=tuple(sd_), segs=6))
parts.append(lathe("SpearGuard", [(-0.06, 0.0), (-0.05, 0.22), (0.05, 0.22), (0.07, 0.0)], GOLD_M, pos=tuple(S1), axis=tuple(sd_), segs=6, smooth=False))
for s2 in (-1, 1):  # winged guard
    parts.append(slab(f"GuardWing{s2}", [(0, 0), (s2 * 0.5, 0.32), (s2 * 0.42, 0.12), (s2 * 0.5, 0.06), (s2 * 0.25, -0.06)], 0.05,
                      tuple(S1 + Vector((s2 * 0.1, -0.02, 0))), (1, 0, 0), tuple(sd_), lambda p, n: mix(GOLD_M, GOLD_W, 0.6)))
BL = 1.45
parts.append(lathe("SpearBlade", [(0, 0.0), (0.08, 0.26), (BL * 0.32, 0.36), (BL, 0.0)],
                   lambda p, n: mix(LIGHT_W, LIGHT_C, smoothstep(0.14, 0.34, (p - S1 - sd_ * ((p - S1).dot(sd_))).length)),
                   pos=tuple(S1 + sd_ * 0.06), axis=tuple(sd_), segs=6, sy=0.45, smooth=False))
parts.append(torus("BladeGlow", 0.48, 0.035, tuple(S1 + sd_ * 0.55), tuple(sd_), LIGHT_C, segs=12, rsegs=3))
parts.append(ball("SpearPommel", 0.13, tuple(S0 - sd_ * 0.05), gold, subdiv=1))

# ---------------------------------------------------------------- shield (viewer's left): chrome, gold rim, rivets, winged star
SC = Vector((-2.08, -0.3, 1.2))
sn = Vector((-0.55, -1, 0.1)).normalized()
su = Vector((0, 0, 1)).cross(sn).normalized()
sv = sn.cross(su).normalized()
SR = 0.82
parts.append(lathe("Shield", [(-0.07, 0.0), (-0.07, SR), (0.02, SR + 0.03), (0.1, SR * 0.75), (0.15, 0.0)], chrome,
                   pos=tuple(SC), axis=tuple(sn), segs=16, smooth=True))
parts.append(torus("ShieldRim", SR, 0.08, tuple(SC + sn * 0.04), tuple(sn), gold, segs=20, rsegs=3))
for k in range(8):
    a = k * math.tau / 8 + math.tau / 16
    q = SC + sn * 0.09 + (su * math.cos(a) + sv * math.sin(a)) * (SR - 0.15)
    parts.append(gem(f"Rivet{k}", tuple(q), 0.045, GOLD_W, h=0.08, axis=tuple(sn), segs=4))
parts.append(slab("ShieldStar", star(0, 0, 0.45, 0.18, n=4, rot=90), 0.05, tuple(SC + sn * 0.16), tuple(su), tuple(sv), GOLD_M))
for s2 in (-1, 1):
    parts.append(slab(f"ShieldWing{s2}", [(s2 * 0.1, 0.0), (s2 * 0.5, 0.28), (s2 * 0.42, 0.08), (s2 * 0.5, 0.02), (s2 * 0.3, -0.12)], 0.04,
                      tuple(SC + sn * 0.14 + sv * 0.05), tuple(su), tuple(sv), FEATH))
parts.append(gem("ShieldBoss", tuple(SC + sn * 0.2), 0.14, GEM, h=0.2, axis=tuple(sn), segs=6))

# ---------------------------------------------------------------- floating feathers and light motes
for j, (pos, ang) in enumerate((((-2.4, -0.2, 2.9), 30), ((1.35, -0.9, 3.85), -40))):
    a = math.radians(ang)
    parts.append(puffy_slab(f"Feather{j}", feather_poly(0.55, 0.22), 0.04, pos, (math.cos(a), 0, -math.sin(a)), (math.sin(a), 0.15, math.cos(a)),
                            lambda p, n: FEATH, rows=1))
for j, (x, y, z, r) in enumerate([(2.85, -0.1, 3.55, 0.13), (2.75, -0.3, 2.3, 0.1), (-1.5, -0.8, 3.6, 0.1), (-2.75, -0.2, 2.0, 0.09)]):
    parts.append(slab(f"Mote{j}", star(0, 0, r * 1.6, r * 0.4, n=4), 0.05, (x, y, z), (1, 0, 0), (0, 0.25, 1), LIGHT_C))

# ---------------------------------------------------------------- fierce battle-cry face
f = Face(b, eye_u=0.5, eye_v=1.55, mouth_v=1.15, ink=INKV, mouth_col=hexc("7a1a3a"))
f.eyes("angry", iris=hexc("ffc83a"), w=0.48, h=0.62)
for sd in (-1, 1):  # hard brows: inner ends down
    f.d(f"Brow{sd}", rect(sd * f.eu, f.ev + 0.36, 0.42, 0.08, math.radians(20 * sd)), INKV, off=0.02)
f.mouth("grin", w=0.95)
for sd in (-1, 1):  # gold war-paint chevrons under the eyes
    u = sd * (f.eu + 0.3)
    f.d(f"Paint{sd}", [(u - 0.13, f.ev - 0.26), (u, f.ev - 0.36), (u + 0.13, f.ev - 0.26), (u + 0.13, f.ev - 0.33), (u, f.ev - 0.43), (u - 0.13, f.ev - 0.33)],
        GOLD_M, off=0.012, th=0.015)
parts += f.parts

ship("slime_valkyrie", parts)
