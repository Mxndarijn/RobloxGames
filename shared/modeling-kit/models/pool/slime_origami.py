# Origami (Secret): a folded paper crane slime. Crisp low-poly body of flat triangular folds
# (every facet its own shade of one pastel), sharp folded wings with white paper backs, one wing
# printed with a washi sakura pattern, a pointed folded tail and neck tip, ink-dot eyes and a
# brush-stroke smile, and a red paper lantern hanging from the tail.
import hashlib
from models._slimepool import *

P, P_D, P_L = hexc("ffa9c4"), hexc("f27fa6"), hexc("ffd3e1")      # pastel sakura pink paper
BACK = hexc("fff8f2")                                              # white back of the paper
WASHI, WASHI_D = hexc("2f4fa8"), hexc("1f3680")                   # indigo washi print
SAKURA, SAKURA_C, DOT = hexc("ff8fb4"), hexc("ffe46a"), hexc("ffd34a")
LANT, LANT_D, LANT_GOLD = hexc("ff3a3a"), hexc("c41e2e"), hexc("ffc23a")
LIGHT = Vector((-0.45, -0.6, 0.66)).normalized()


def h01(*k):
    """stable 0..1 hash (facet jitter must not change between rounds)."""
    return int(hashlib.md5(repr(k).encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def paper(c0, c1, n, key, amt=1.0):
    """one flat facet colour: random shade between c0 and c1 + a baked fold light."""
    t = h01(key)
    c = mix(c0, c1, t)
    k = 0.9 + 0.16 * max(-1.0, min(1.0, n.dot(LIGHT))) * amt
    return shade(c, k)


def set_face_col(bm, f, c):
    col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for lp in f.loops:
        lp[col] = c


# ---------------------------------------------------------------- faceted body
class FacetBody:
    """antiprism-folded body: rings of N verts, every other ring turned half a step, so each band
    is a strip of triangles. Flat shaded, one colour per facet."""

    def __init__(self, rings, tip, N=8, sx=1.0, sy=1.0, name="Body"):
        self.name, self.H = name, tip
        bm = bmesh.new()
        R = []
        for k, (z, r) in enumerate(rings):
            off = 0.5 * (k % 2)
            R.append([bm.verts.new((math.sin((i + off) * math.tau / N) * r * sx,
                                    -math.cos((i + off) * math.tau / N) * r * sy, z)) for i in range(N)])
        for k in range(len(R) - 1):
            a, b = R[k], R[k + 1]
            for i in range(N):
                j = (i + 1) % N
                if k % 2 == 0:  # b[i] sits between a[i] and a[j]
                    bm.faces.new((a[i], a[j], b[i]))
                    bm.faces.new((b[i], a[j], b[j]))
                else:           # a[i] sits between b[i] and b[j]
                    bm.faces.new((b[i], b[j], a[i]))
                    bm.faces.new((a[i], b[j], a[j]))
        top = bm.verts.new((0, 0, tip))
        bot = bm.verts.new((0, 0, rings[0][0]))
        for i in range(N):
            j = (i + 1) % N
            bm.faces.new((R[-1][i], R[-1][j], top))
            bm.faces.new((R[0][j], R[0][i], bot))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.normal_update()
        for fi, f in enumerate(bm.faces):
            c = paper(P_D, P_L, f.normal, ("body", fi))
            if f.calc_center_median().z < 0.05:
                c = shade(P_D, 0.8)
            set_face_col(bm, f, c)
        self.obj = keep(obj_from_bm(name, bm), False)
        register(self.obj, name)


# ---------------------------------------------------------------- folded paper sheets
def sheet(name, V, T, th, top_col, back_col=BACK, edge_col=None):
    """thin closed paper solid from triangles T over verts V: front faces get top_col(i, normal),
    the back is white paper, the cut edges edge_col. Each triangle is its own flat facet."""
    V = [Vector(v) for v in V]
    fn = []
    for a, b, c in T:
        fn.append((V[b] - V[a]).cross(V[c] - V[a]).normalized())
    vn = [Vector((0, 0, 0)) for _ in V]
    for (a, b, c), n in zip(T, fn):
        for i in (a, b, c):
            vn[i] += n
    vn = [n.normalized() if n.length > 1e-6 else Vector((0, 0, 1)) for n in vn]
    bm = bmesh.new()
    top = [bm.verts.new(v + n * th / 2) for v, n in zip(V, vn)]
    bot = [bm.verts.new(v - n * th / 2) for v, n in zip(V, vn)]
    E = set()
    for ti, (a, b, c) in enumerate(T):
        f = bm.faces.new((top[a], top[b], top[c]))
        set_face_col(bm, f, top_col(ti, fn[ti]))
        g = bm.faces.new((bot[c], bot[b], bot[a]))
        set_face_col(bm, g, paper(shade(back_col, 0.9), back_col, -fn[ti], (name, "b", ti), 0.6))
        E |= {(a, b), (b, c), (c, a)}
    ec = edge_col or shade(back_col, 0.92)
    for a, b in E:
        if (b, a) not in E:
            f = bm.faces.new((top[b], top[a], bot[a], bot[b]))
            set_face_col(bm, f, ec)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return keep(obj_from_bm(name, bm), False)


def plain(name, c0=P_D, c1=P_L):
    return lambda i, n: paper(c0, c1, n, (name, i))


b = FacetBody([(0.0, 0.5), (0.3, 1.2), (0.75, 1.68), (1.55, 1.62), (2.4, 1.02)], 3.05, N=7, sx=1.04, sy=0.96)  # tapered belly
parts = [b.obj]

# wings: long folded triangles rising up and out, a raised crease from the root to the tip
wing_tris = {}
for sd in (-1, 1):
    A = Vector((sd * 1.0, -0.4, 1.95))
    B = Vector((sd * 0.95, 0.95, 1.75))
    F = Vector((sd * 2.6, -0.35, 2.7))
    T = Vector((sd * 3.25, 1.05, 4.0))
    R = (A + B) / 2 + Vector((sd * 0.35, -0.12, 0.42))
    V = [A, B, T, F, R]
    tris = [(0, 3, 4), (3, 2, 4), (4, 2, 1)]
    if sd < 0:
        tris = [(a_, c_, b_) for a_, b_, c_ in tris]
    washi = sd == -1  # slime's right wing = viewer's left in the hero view
    col = (lambda i, n: paper(WASHI_D, WASHI, n, ("washi", i))) if washi else plain(f"wing{sd}")
    w = sheet(f"Wing{sd}", V, tris, 0.07, col)
    parts.append(w)
    wing_tris[sd] = (V, tris)

# washi print: sakura flowers + gold dots projected onto each front facet of the printed wing
def sakura_poly(r, n=5):
    pts = []
    for k in range(n * 6):
        a = k / (n * 6) * math.tau
        petal = abs(math.sin(a * n / 2))
        notch = 1 - 0.25 * max(0.0, 1 - abs(math.sin(a * n / 2) - 1) * 12)  # notch at petal tips
        rr = r * (0.35 + 0.65 * petal ** 0.6) * notch
        pts.append((math.cos(a + math.pi / 2) * rr, math.sin(a + math.pi / 2) * rr))
    return pts


V, tris = wing_tris[-1]
V = [Vector(v) for v in V]
register(parts[1], "WashiWing")
k = 0
for ti, (ia, ib, ic) in enumerate(tris):
    a, bb, c = V[ia], V[ib], V[ic]
    n = (bb - a).cross(c - a).normalized()
    U = (c - a).normalized()
    W = n.cross(U)
    cen = (a + bb + c) / 3
    fr = Frame(cen, U, W, n)
    # sample points inside the triangle (barycentric grid), keep a margin to the edges
    for (p, q, s, kind) in ((0.34, 0.33, 0.33, "f"), (0.6, 0.2, 0.2, "d"), (0.2, 0.6, 0.2, "d"), (0.2, 0.2, 0.6, "f")):
        pt = a * p + bb * q + c * s
        u, v = (pt - cen).dot(U), (pt - cen).dot(W)
        span = min((bb - a).length, (c - a).length, (c - bb).length)
        try:
            if kind == "f":
                r = min(0.2, span * 0.13)
                d1 = decal(f"Washi{k}", [(u + x, v + y) for x, y in sakura_poly(r)], SAKURA, fr, off=0.045, th=0.012, on=["WashiWing"], step=None)
                d2 = decal(f"WashiC{k}", oval(u, v, r * 0.35, r * 0.35, n=8), SAKURA_C, fr, off=0.06, th=0.008, on=["WashiWing"], step=None)
                parts += [d1, d2]
            else:
                parts.append(decal(f"Washi{k}", oval(u, v, 0.09, 0.09, n=8), DOT, fr, off=0.045, th=0.01, on=["WashiWing"], step=None))
        except ValueError:
            print("washi skip", ti, kind)
        k += 1

# tail: a long pointed fold rising from the back
tL, tR = Vector((-0.45, 1.05, 1.2)), Vector((0.1, 1.2, 1.2))
tK = Vector((-0.12, 1.12, 1.85))
tT = Vector((-1.85, 2.4, 3.0))
tM = tK.lerp(tT, 0.4) + Vector((0, 0.1, 0.05))
parts.append(sheet("Tail", [tL, tR, tK, tT, tM], [(0, 2, 4), (2, 1, 4), (0, 4, 3), (4, 1, 3)], 0.06, plain("tail")))

# neck tip: a folded diamond spike on top with a flat crane head bent forward
nL, nR = Vector((-0.3, 0.1, 2.62)), Vector((0.3, 0.1, 2.62))
nF, nB = Vector((0, -0.22, 2.68)), Vector((0, 0.42, 2.62))
nT = Vector((0, -0.25, 4.35))
parts.append(sheet("Neck", [nL, nR, nF, nB, nT], [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4)], 0.05, plain("neck")))
hT = Vector((0, -0.2, 4.5))
hB = Vector((0, -1.15, 3.92))
hL, hR = Vector((-0.13, -0.3, 3.98)), Vector((0.13, -0.3, 3.98))
parts.append(sheet("Head", [hT, hB, hL, hR], [(0, 2, 1), (0, 1, 3)], 0.05, plain("head", P, P_L)))

# floating folded paper petals (two-facet folds) drifting around
for k, (pos, yaw, sc) in enumerate((((-2.0, -0.6, 1.0), 30, 0.38), ((1.9, -0.9, 0.7), -40, 0.32), ((-1.5, -1.1, 3.4), 70, 0.3), ((2.25, 0.2, 1.65), 10, 0.28))):
    O = Vector(pos)
    q = Matrix.Rotation(math.radians(yaw), 3, "Z") @ Matrix.Rotation(math.radians(35), 3, "X")
    pv = [O + q @ Vector(v) * sc for v in ((-1, 0, 0), (0, 0, 1.3), (1, 0, 0), (0, 0.35, 0.2), (0, 0, -1.0))]
    parts.append(sheet(f"Petal{k}", pv, [(0, 3, 1), (3, 2, 1), (0, 4, 3), (3, 4, 2)], 0.03, plain(f"petal{k}", SAKURA, P)))

# paper lantern hanging from the tail tip
hang = tT + Vector((0, 0.02, -0.02))
lz1 = hang.z - 0.55
lc = Vector((hang.x, hang.y, lz1 - 0.42))
parts.append(tube("LanternString", [hang, (hang.x, hang.y, lz1 + 0.02)], [0.018, 0.018], INK, segs=4))
lant = lathe("Lantern", [(-0.42, 0.0), (-0.41, 0.2), (-0.25, 0.38), (0, 0.43), (0.25, 0.38), (0.41, 0.2), (0.42, 0.0)],
             LANT, pos=lc, segs=10, smooth=False)
bm = bmesh.new(); bm.from_mesh(lant.data); bm.normal_update()
for fi, f in enumerate(bm.faces):
    c = f.calc_center_median()
    a = math.atan2(c.x - lc.x, c.y - lc.y)
    set_face_col(bm, f, paper(LANT_D, LANT, f.normal, ("lant", fi)) if int((a + math.pi) / math.tau * 10) % 2 else shade(LANT, 1.05))
bm.to_mesh(lant.data); bm.free()
parts.append(lant)
for zz in (lc.z + 0.41, lc.z - 0.41):
    parts.append(lathe("LantCap", [(-0.05, 0.0), (-0.05, 0.21), (0.05, 0.21), (0.05, 0.0)], LANT_GOLD, pos=(lc.x, lc.y, zz), segs=10, smooth=False))
parts.append(tube("LantTassel", [(lc.x, lc.y, lc.z - 0.46), (lc.x, lc.y, lc.z - 0.75)], [0.05, 0.02], LANT_GOLD, segs=5))

# face: tiny ink dots, a tapered brush-stroke smile, soft blush
f = Face(b, eye_u=0.5, eye_v=1.55, mouth_v=1.12, s=1.0)
for sd in (-1, 1):
    f.d(f"Eye{sd}", oval(sd * 0.52, 1.55, 0.25, 0.3, n=12), INK)
    f.d(f"EyeHi{sd}", oval(sd * 0.52 - 0.05, 1.62, 0.08, 0.08, n=6), WHITE, off=0.045, th=0.01)


def brush(cu, cv, rad, a0, a1, w, n=14):
    outer, inner = [], []
    for k in range(n + 1):
        t = k / n
        a = math.radians(a0 + (a1 - a0) * t)
        ww = w * (0.25 + 0.75 * math.sin(math.pi * t) ** 0.7) * (1.15 - 0.3 * t)
        outer.append((cu + math.cos(a) * (rad + ww / 2), cv + math.sin(a) * (rad + ww / 2)))
        inner.append((cu + math.cos(a) * (rad - ww / 2), cv + math.sin(a) * (rad - ww / 2)))
    return outer + list(reversed(inner))


f.d("Mouth", brush(0, 1.32, 0.3, 208, 332, 0.1), INK)
f.cheeks(color=hexc("ff5c8a"), w=0.3, h=0.15, u=0.82, v=1.3)
parts += f.parts

ship("slime_origami", parts)
