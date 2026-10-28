# Moo (Rare): dozy dairy-cow slime. Wide, squat goo with black blotches, cream horns, floppy
# side ears, a big pink muzzle with nostrils and a gold nose ring, red collar with a gold bell.
from models._slimepool import *


# ---- local helper: big decals that follow the curve (the lib decal is one flat n-gon, so a
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
    return separate(keep(o, False), frame, on, off=off)


WH, BLK, PINK, PINK_D = hexc("fbfbff"), hexc("26222e"), hexc("ffa6bf"), hexc("d9587e")
HORN, HORN_D, RED, RED_D = hexc("fff0c8"), hexc("e0b878"), hexc("ef3b4a"), hexc("b81f33")

b = Body([(0, 1.36), (0.15, 1.62), (0.5, 1.72), (1.1, 1.62), (1.7, 1.3), (2.2, 0.82), (2.5, 0.3), (2.58, 0)],
         color=WH, segs=40)
parts = [b.obj]

# black blotches around the sides / back (face kept clear): wobbly patches that follow the curve
for k, (yaw, z, w, h, rot) in enumerate(((68, 1.3, 1.1, 0.9, 20), (122, 0.72, 0.9, 0.7, -10), (152, 1.8, 1.1, 0.8, 30),
                                         (205, 1.05, 1.25, 1.0, 0), (250, 1.7, 0.95, 0.8, -25), (292, 0.95, 1.0, 0.85, 15),
                                         (-40, 2.2, 0.55, 0.42, 10))):
    poly = blotch(k + 1, w, h, n=18)
    c, sn = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    poly = [(x * c - y * sn, x * sn + y * c) for x, y in poly]
    parts.append(grid_decal(f"Blotch{k}", poly, BLK, frame_at(yaw, z), off=0.006, th=0.01, on=["Body"], cell=min(0.24, w * 0.22)))

# horns + ears
for sd in (-1, 1):
    parts.append(horn(f"Horn{sd}", [(sd * 0.55, 0.05, 2.25), (sd * 0.82, 0.0, 2.6), (sd * 0.9, -0.05, 2.9)],
                      [0.15, 0.11, 0.05], HORN_D, HORN))
    ear = [(0, -0.24), (0.6, -0.34), (0.95, -0.06), (0.62, 0.26), (0, 0.22)]
    parts.append(puffy_slab(f"Ear{sd}", ear, 0.16, (sd * 1.1, -0.05, 1.98), (sd, -0.35, -0.3), (0, -0.2, 1), WH))
    parts.append(puffy_slab(f"EarIn{sd}", [(0.15, -0.15), (0.6, -0.22), (0.8, -0.05), (0.58, 0.14), (0.15, 0.1)], 0.05,
                            (sd * 1.1 - sd * 0.03, -0.14, 1.98), (sd, -0.35, -0.3), (0, -0.2, 1), PINK))

# muzzle: big soft pink pad on the lower face
mz = ball("Muzzle", 0.6, (0, -1.38, 0.92), lambda p, n: mix(PINK, hexc("ffc3d4"), smoothstep(0.6, 1.3, p.z)),
          squash=(1.45, 0.7, 0.85), subdiv=2)
register(mz)
parts.append(mz)
for sd in (-1, 1):
    parts.append(decal(f"Nostril{sd}", oval(sd * 0.3, 1.0, 0.16, 0.22, n=12, rot=math.radians(sd * -20)), PINK_D,
                       FRONT, off=0.008, th=0.012, on=["Muzzle"]))
parts.append(decal("MooMouth", arc(0, 0.86, 0.22, 205, 335, 0.055), PINK_D, FRONT, off=0.008, th=0.012, on=["Muzzle"]))
parts.append(torus("NoseRing", 0.2, 0.045, (0, -1.83, 0.8), (0, 1, 0), GOLD, segs=20, rsegs=6))

# red collar + gold bell at the front base
R = b.radius(0.42)
parts.append(torus("Collar", R + 0.02, 0.1, (0, 0, 0.42), (0, 0, 1), RED, segs=36, rsegs=6))
parts.append(lathe("Bell", [(0, 0), (0.0, 0.26), (0.12, 0.25), (0.3, 0.19), (0.4, 0.1), (0.44, 0)],
                   zgrad(GOLD_D, GOLD_L, 0.0, 0.5), pos=(0, -R - 0.18, 0.02), segs=14))
parts.append(ball("BellTop", 0.07, (0, -R - 0.18, 0.47), GOLD))

f = Face(b, eye_v=1.7, eye_u=0.6, s=1.25)
f.eyes("sleepy")
f.cheeks(color=hexc("ffb0c4"), u=1.0, v=1.45, w=0.32, h=0.16)
parts += f.parts
ship("slime_moo", parts)
