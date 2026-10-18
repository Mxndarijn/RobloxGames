# Moo-shroom (Epic hybrid: moo + mushie + sprout): a toadstool cow. Squat glossy red goo (moo's wide
# body in mushie's cap red) with big white toadstool spots, a cream mushroom-stem foot, cow horns and
# floppy ears, a big pink muzzle with a gold nose ring, a mossy patch on its back growing a little
# mushroom family, a sprout on its head, a leafy collar with a bell, and a dopey tongue-out grin.
from models._slimepool import *

# ---- local helper (copied from slime_moo.py): big decals that follow the curve (the lib decal is one flat n-gon, so a
# large one cuts chords through the body and only its rim shows). Triangulated with interior
# grid points (Delaunay), every vertex projected onto the surface, closed slab.
def _inside(pt, poly):
    x, y = pt
    c = False
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            c = not c
    return c


def grid_decal(name, poly, color, frame=FRONT, off=0.008, th=0.012, on=None, step=0.08, cell=0.12):
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
    return keep(o, False)

RED, RED_D, RED_L = hexc("f22a36"), hexc("b0142a"), hexc("ff6e5e")
SPOT, STEM, STEM_D = hexc("fffaf0"), hexc("fff0d6"), hexc("ecc898")
HORN, HORN_D = hexc("fff0c8"), hexc("d8a868")
PINK, PINK_L, PINK_D = hexc("ffa6bf"), hexc("ffc8d6"), hexc("d9587e")
MOSS, MOSS_L, MOSS_D = hexc("4cc23a"), hexc("a8ec60"), hexc("2f8a2a")
LEAF, LEAF_L = hexc("3fb83a"), hexc("8ff05a")
BROWN, BROWN_L = hexc("b8682e"), hexc("e8a060")

FOOT = 0.42


def paint(a, z, p):
    c = mix(RED_D, RED, smoothstep(0.4, 1.3, z))
    c = mix(c, RED_L, 0.35 * smoothstep(1.6, 2.4, z))
    return mix(STEM_D, c, smoothstep(FOOT - 0.06, FOOT + 0.06, z)) if z < FOOT + 0.1 else c


PROF = [(0, 1.36), (0.15, 1.6), (0.5, 1.7), (1.1, 1.62), (1.7, 1.32), (2.2, 0.86), (2.5, 0.34), (2.58, 0)]
b = Body(PROF, paint=paint, segs=36, sub=2, gloss=0.75)
parts = [b.obj]

# ---- white toadstool spots that follow the curve (face kept clear)
for k, (yaw, z, w, h, rot) in enumerate(((72, 1.25, 0.72, 0.62, 10), (118, 0.85, 0.55, 0.48, -10), (138, 1.75, 0.6, 0.52, 20),
                                         (200, 1.15, 0.78, 0.66, 0), (238, 1.75, 0.5, 0.44, -20), (288, 1.1, 0.66, 0.58, 15),
                                         (-62, 1.95, 0.42, 0.36, 10), (55, 2.05, 0.4, 0.34, -15))):
    poly = blotch(k + 3, w, h, n=16, wobble=0.12)
    c, sn = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    poly = [(x * c - y * sn, x * sn + y * c) for x, y in poly]
    parts.append(grid_decal(f"Spot{k}", poly, SPOT, frame_at(yaw, z), off=0.006, th=0.012, on=["Body"], cell=min(0.3, w * 0.4)))

# ---- horns + floppy cow ears (moo)
for sd in (-1, 1):
    parts.append(horn(f"Horn{sd}", [(sd * 0.62, 0.0, 2.22), (sd * 0.95, -0.02, 2.5), (sd * 1.08, -0.06, 2.85)],
                      [0.16, 0.12, 0.05], HORN_D, HORN))
    ear = [(0, -0.22)] + [(0.5 + 0.46 * math.cos(t), 0.3 * math.sin(t)) for t in [-math.pi * 0.75 + k * math.pi * 1.5 / 10 for k in range(11)]] + [(0, 0.2)]
    parts.append(puffy_slab(f"Ear{sd}", ear, 0.16, (sd * 1.12, -0.05, 1.95), (sd, -0.35, -0.3), (0, -0.2, 1), RED, rows=2))
    parts.append(slab(f"EarIn{sd}", [(0.5 + 0.3 * math.cos(t), 0.17 * math.sin(t)) for t in [k * math.tau / 12 for k in range(12)]], 0.05,
                            (sd * 1.12 - sd * 0.03, -0.14, 1.95), (sd, -0.35, -0.3), (0, -0.2, 1), PINK, smooth=True))

# ---- muzzle with nostrils, gold nose ring, tongue-out grin
mz = ball("Muzzle", 0.6, (0, -1.4, 0.95), lambda p, n: mix(PINK, PINK_L, smoothstep(0.6, 1.35, p.z)),
          squash=(1.45, 0.7, 0.85), subdiv=2)
register(mz)
parts.append(mz)
for sd in (-1, 1):
    parts.append(decal(f"Nostril{sd}", oval(sd * 0.3, 1.05, 0.16, 0.22, n=12, rot=math.radians(sd * -20)), PINK_D,
                       FRONT, off=0.008, th=0.012, on=["Muzzle"]))
parts.append(decal("Mouth", arc(0, 0.9, 0.26, 200, 340, 0.06), PINK_D, FRONT, off=0.008, th=0.012, on=["Muzzle"]))
parts.append(decal("Tongue", half_oval(0.1, 0.7, 0.2, 0.17), hexc("ff6f8e"), FRONT, off=0.012, th=0.02, on=["Muzzle", "Body"]))
parts.append(torus("NoseRing", 0.2, 0.045, (0, -1.85, 0.82), (0, 1, 0), GOLD, segs=16, rsegs=5))

# ---- mossy patch on the back with a little mushroom family + a sprout on the head (sprout)
def moss_col(p, n):
    t = noise.noise(Vector((p.x * 3, p.y * 3, p.z * 3)))
    return mix(MOSS, MOSS_L, 0.7 * max(0.0, t)) if t > 0 else mix(MOSS, MOSS_D, -0.8 * t)


moss = grid_decal("Moss", blotch(11, 1.3, 1.0, n=18, wobble=0.2), moss_col, frame_at(180, 1.85, 34), off=0.004, th=0.05, on=["Body"], cell=0.3)
parts.append(moss)


def mini_shroom(name, base, h, cap_r, cap_c, cap_cd, spots_c=None, lean=(0, 0)):
    B = Vector(base)
    top = B + Vector((lean[0], lean[1], h))
    out = [horn(f"{name}Stem", [tuple(B - Vector((0, 0, 0.1))), tuple(B + (top - B) * 0.5), tuple(top)], [cap_r * 0.42, cap_r * 0.36, cap_r * 0.34], STEM_D, STEM, segs=8)]
    axis = (top - B).normalized()

    def cc(p, n):
        if (p - top).dot(axis) < 0.04 * cap_r:
            return STEM_D
        return mix(cap_cd, cap_c, smoothstep(0.0, cap_r * 0.8, (p - top).dot(axis)))
    cap = lathe(f"{name}Cap", [(-0.02, 0.0), (0.0, cap_r), (cap_r * 0.3, cap_r * 0.96), (cap_r * 0.62, cap_r * 0.66), (cap_r * 0.78, 0.0)],
                cc, pos=tuple(top), axis=tuple(axis), segs=14, sub=1)
    out.append(cap)
    if spots_c:
        register(cap, f"{name}Cap")
        for k, (yaw, tilt) in enumerate(((20, 60), (140, 40), (260, 45), (0, 88))):
            a = math.radians(yaw)
            el = math.radians(tilt)
            c = top + Vector((math.sin(a) * math.cos(el) * cap_r * 0.7, -math.cos(a) * math.cos(el) * cap_r * 0.7, math.sin(el) * cap_r * 0.55))
            out.append(decal(f"{name}Dot{k}", oval(0, 0, cap_r * 0.42, cap_r * 0.38, n=8), spots_c, frame_at(yaw, c.z, tilt, c.x, c.y),
                             off=0.008, th=0.02, on=[f"{name}Cap"]))
    return out


back = lambda yaw, z: b.point(math.radians(yaw), z, -0.02)
parts += mini_shroom("ShroomA", back(176, 1.95), 0.95, 0.52, RED, RED_D, SPOT, lean=(0.04, 0.12))
parts += mini_shroom("ShroomB", back(212, 1.7), 0.5, 0.32, BROWN_L, BROWN, None, lean=(-0.12, 0.1))
parts += mini_shroom("ShroomC", back(142, 1.68), 0.4, 0.24, SPOT, STEM_D, None, lean=(0.12, 0.08))

tip = (0.05, 0.0, 3.05)
parts.append(horn("SproutStem", [(0, 0, 2.5), (0.02, 0, 2.8), tip], [0.08, 0.07, 0.06], hexc("3f9a36"), hexc("3f9a36"), segs=6))
leaf = [(0, 0)] + [(0.36 + 0.4 * math.cos(t), 0.3 * math.sin(t) * (1 - 0.35 * math.cos(t))) for t in [math.pi - k * math.tau / 14 for k in range(1, 14)]]
for sd in (-1, 1):
    X = Vector((sd, 0, 0.55)).normalized()
    parts.append(puffy_slab(f"Leaf{sd}", leaf, 0.1, tip, X, (0, math.cos(math.radians(40)), math.sin(math.radians(40))), along(LEAF, LEAF_L, tip, Vector(tip) + X * 0.75), rows=2))

# ---- leafy vine collar with a gold bell
R = b.radius(0.5)
parts.append(torus("Collar", R + 0.02, 0.09, (0, 0, 0.5), (0, 0, 1), MOSS_D, segs=28, rsegs=5))
for k in range(9):
    a = math.radians(-120 + k * 30) if k < 9 else 0
    if abs(math.degrees(a)) < 16:
        continue
    p = Vector((math.sin(a) * (R + 0.1), -math.cos(a) * (R + 0.1), 0.52))
    X = Vector((math.cos(a), math.sin(a), 0.3)).normalized()
    parts.append(slab(f"CLeaf{k}", [(0, 0), (0.16, 0.11), (0.34, 0.0), (0.16, -0.11)], 0.05, tuple(p), tuple(X),
                      (math.sin(a) * 0.3, -math.cos(a) * 0.3, 1), along(MOSS_D, LEAF_L, p, p + X * 0.34)))
parts.append(lathe("Bell", [(0, 0), (0.0, 0.24), (0.11, 0.23), (0.28, 0.17), (0.37, 0.09), (0.41, 0)],
                   zgrad(GOLD_D, GOLD_L, 0.1, 0.55), pos=(0, -R - 0.16, 0.1), segs=12))
parts.append(ball("BellTop", 0.07, (0, -R - 0.16, 0.52), GOLD))

# ---- face: big dopey eyes with lashes looking up, blush
f = Face(b, eye_v=1.72, eye_u=0.6, s=1.15)
f.eyes("round", w=0.46, h=0.6, iris=hexc("6ad84a"), look=(0, 0.02))
for sd in (-1, 1):  # three lashes fanning out from the top-outer edge of each eye
    for j, ang in enumerate((55, 75, 95)):
        aa = math.radians(90 - (90 - ang) * sd)
        u = sd * f.eu + math.cos(aa) * 0.3
        f.d(f"Lash{sd}{j}", rect(u, f.ev + math.sin(aa) * 0.4, 0.055, 0.16, aa - math.pi / 2), INK)
f.cheeks(color=hexc("ff9ab4"), u=1.02, v=1.45, w=0.3, h=0.15)
parts += f.parts
ship("slime_moo_shroom", parts)
