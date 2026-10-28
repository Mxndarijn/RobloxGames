# Sunny (Legendary, Garden): sunflower slime. Sunny-yellow goo with a brown seed-disc face, a big
# lion's-mane ring of two layers of orange/yellow petals round the head, cool sunglasses with a
# teal frame, a cheeky grin, and a green leaf arm on each side (one waving).
from models._slimepool import *

YEL, YEL_D, YEL_L = hexc("ffd83a"), hexc("f0a018"), hexc("fff2a0")
PET_O, PET_OD = hexc("ff9a1a"), hexc("e0600c")
PET_Y, PET_YL = hexc("ffc81e"), hexc("fff07a")
SEED, SEED_D, SEED_L = hexc("94562a"), hexc("4a2410"), hexc("b0703a")
LEAF, LEAF_D, LEAF_L = hexc("2fae3a"), hexc("1c7a28"), hexc("9af05a")
FRAME = hexc("1fd6c8")


def _inside(pt, poly):
    x, y = pt
    c = False
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            c = not c
    return c


def grid_decal(name, poly, color, frame=FRONT, off=0.008, th=0.012, on=None, step=0.08, cell=0.12):
    """decal with interior verts (copied from slime_goomancer.py): wide decals follow the curve."""
    from mathutils.geometry import delaunay_2d_cdt
    poly = densify(poly, step)
    n = len(poly)
    us, vs = [p[0] for p in poly], [p[1] for p in poly]
    inner = []
    u = min(us) + cell / 2
    while u < max(us):
        v = min(vs) + cell / 2
        while v < max(vs):
            if _inside((u, v), poly) and min((u - a) ** 2 + (v - b) ** 2 for a, b in poly) > (cell * 0.45) ** 2:
                inner.append((u, v))
            v += cell
        u += cell
    pts = [Vector(p) for p in poly + inner]
    V2, _, F, *_ = delaunay_2d_cdt(pts, [(i, (i + 1) % n) for i in range(n)], [list(range(n))], 1, 1e-6)
    F = [f for f in F if _inside(tuple(sum((V2[i] for i in f), Vector((0, 0))) / len(f)), poly)]
    bm = bmesh.new()
    top, bot = {}, {}
    for f in F:
        for i in f:
            if i in top:
                continue
            uu, vv = V2[i]
            hit = cast(frame.O + frame.U * uu + frame.V * vv + frame.D * 12, -frame.D, on)
            if hit is None:
                raise ValueError(f"grid_decal {name}: ({uu:.2f}, {vv:.2f}) misses every surface")
            loc, nn, _ = hit
            if nn.dot(frame.D) < 0:
                nn = -nn
            nn = (nn * 0.6 + frame.D * 0.4).normalized()
            bot[i] = bm.verts.new(loc + nn * off)
            top[i] = bm.verts.new(loc + nn * (off + th))
    ecount = {}
    for f in F:
        bm.faces.new([top[i] for i in f])
        bm.faces.new([bot[i] for i in reversed(f)])
        for a, b in zip(f, f[1:] + f[:1]):
            ecount[(a, b)] = ecount.get((a, b), 0) + 1
    for (a, b) in ecount:
        if (b, a) not in ecount:
            bm.faces.new((bot[a], bot[b], top[b], top[a]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return separate(keep(o, False), frame, on, off=off)


def paint(a, z, p):
    c = mix(YEL_D, YEL, smoothstep(0.0, 1.2, z))
    return mix(c, YEL_L, 0.45 * smoothstep(1.8, 2.8, z))


b = Body([(0, 1.08), (0.14, 1.34), (0.5, 1.48), (1.1, 1.46), (1.8, 1.26), (2.4, 0.92), (2.75, 0.48), (2.88, 0)],
         paint=paint, segs=36, sub=2)
parts = [b.obj]
H = b.H

# ---- petal mane: a ring in the front plane round the head, two layers, open at the bottom
ZC = 1.45  # ring centre height
YC = 0.15


def edge_t(a):
    """distance from (0, ZC) along (cos a, sin a) in the x-z plane to the body outline."""
    t = 0.0
    while t < 3:
        x, z = abs(math.cos(a)) * t, ZC + math.sin(a) * t
        if z >= H or z <= 0 or x >= b.radius(z) * b.sx:
            return t
        t += 0.02
    return t


def petal_poly(L, w, n=5):
    """petal along +x: narrow root, widest at ~55 %, soft pointed tip."""
    top = []
    for k in range(n + 1):
        t = k / n
        top.append((t * L, w / 2 * math.sin(math.pi * t ** 0.85) ** 0.6))
    bot = [(x, -y) for x, y in reversed(top[1:-1])]
    return top + bot


def petal_ring(tag, a0, a1, step, L, w, back, tilt, c_root, c_tip, tuck=0.3, n=5, rows=1, th=0.12):
    out = []
    a = a0
    k = 0
    while a <= a1 + 1e-6:
        ar = math.radians(a)
        r = Vector((math.cos(ar), 0, math.sin(ar)))
        tg = Vector((-math.sin(ar), 0, math.cos(ar)))
        d = (r * math.cos(math.radians(tilt)) + Vector((0, 1, 0)) * math.sin(math.radians(tilt))).normalized()
        o = Vector((0, YC + back, ZC)) + r * (edge_t(ar) - tuck)
        LL = L * (1 + 0.08 * math.sin(k * 2.3))
        out.append(puffy_slab(f"Petal{tag}{k}", petal_poly(LL, w, n), th, tuple(o), tuple(d), tuple(tg),
                              along(c_root, c_tip, o, o + d * LL, power=0.8), rows=rows))
        a += step
        k += 1
    return out


parts += petal_ring("G", -45, 225, 30, 0.75, 0.5, 0.42, 50, LEAF_D, LEAF, tuck=0.4, n=3)
parts += petal_ring("B", -40, 220, 20, 1.6, 0.85, 0.22, 26, PET_OD, PET_O, tuck=0.35)
parts += petal_ring("F", -30, 210, 20, 1.2, 0.72, 0.05, 14, PET_O, PET_YL, tuck=0.3)

# ---- seed disc face: brown oval on the front with lighter seeds in a sunflower spiral
DISC_U, DISC_V, DISC_W, DISC_H = 0.0, 1.45, 1.95, 1.7
disc = oval(DISC_U, DISC_V, DISC_W, DISC_H, n=28)
parts.append(grid_decal("Disc", disc, lambda p, n: mix(mix(SEED_D, SEED, 0.55), SEED, smoothstep(0.6, 2.2, p.z)), FRONT, off=0.01, th=0.02, on=["Body"], cell=0.22))
seeds = 0
for k in range(120):
    rr = 0.088 * math.sqrt(k + 1)
    ang = k * 2.39996
    u, v = DISC_U + math.cos(ang) * rr * 1.0, DISC_V + math.sin(ang) * rr * DISC_H / DISC_W
    if (u / (DISC_W / 2 - 0.1)) ** 2 + ((v - DISC_V) / (DISC_H / 2 - 0.1)) ** 2 > 1:
        continue
    if abs(v - 1.62) < 0.3 and 0.12 < abs(u) < 0.85:  # under the shades
        continue
    if v < 1.25 and abs(u) < 0.45:  # mouth
        continue
    parts.append(decal(f"Seed{k}", oval(u, v, 0.075, 0.075, n=4, rot=ang), SEED_D, FRONT, off=0.03, th=0.012, on=["Body"], step=0))
    seeds += 1

# ---- face: cool shades with a teal frame, cheeky grin
S = 1.2
f = Face(b, eye_v=1.65, eye_u=0.54, mouth_v=1.04, s=S)
for sd in (-1, 1):
    u, ev = sd * 0.54, 1.65
    lens = [(-0.3, 0.16), (0.3, 0.16), (0.27, -0.08), (0.12, -0.2), (-0.14, -0.2), (-0.28, -0.06)]
    cv = -0.02
    fr = [(u + x * S * 1.22, ev + cv + (y - cv) * S * 1.3) for x, y in lens]
    f.d(f"Frame{sd}", fr, FRAME, off=0.025, th=0.03)
f.d("FrameBridge", rect(0, 1.65 + 0.13 * S, 2 * 0.54 - 0.5 * S, 0.12), FRAME, off=0.025, th=0.03)
f.eyes("shades", color=hexc("1a1428"))
f.mouth("grin", w=0.85)
parts += f.parts

# ---- leaf arms: one down-out, one waving up
LL, LW = 1.55, 0.95
leaf = []
for k in range(9):
    t = k / 8
    leaf.append((t * LL, LW / 2 * math.sin(math.pi * t ** 0.75) ** 0.75))
leaf = leaf + [(x, -y) for x, y in reversed(leaf[1:-1])]
for sd, up in ((1, 0.1), (-1, 2.6)):
    root = b.point(math.radians(sd * 72), 0.95 if up < 1 else 1.1, -0.1)
    X = Vector((sd * 1.0, -0.25, up)).normalized()
    Y = X.cross(Vector((0, -1, 0.3))).normalized()
    N = X.cross(Y).normalized()
    if N.y > 0:
        N = -N
    parts.append(puffy_slab(f"Leaf{sd}", leaf, 0.14, tuple(root), tuple(X), tuple(Y),
                            along(LEAF_D, LEAF_L, root, root + X * LL), rows=2))
    vp = [root + X * (LL * t) + N * (0.085 - 0.03 * t) for t in (0.08, 0.5, 0.88)]
    parts.append(horn(f"Vein{sd}", [tuple(p) for p in vp], [0.045, 0.035, 0.015], LEAF_D, LEAF, segs=5))

# ---- little stem curl on top (Garden family)
st = [(0, 0.35, H - 0.1), (0, 0.45, H + 0.25), (0.08, 0.7, H + 0.45), (0.12, 0.92, H + 0.35)]
parts.append(horn("Stem", st, [0.11, 0.1, 0.08, 0.05], LEAF_D, LEAF, segs=6))

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_sunny", parts)
