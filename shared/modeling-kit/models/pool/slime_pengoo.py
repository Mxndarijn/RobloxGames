# Pengoo (Rare): dapper penguin slime. Tall navy goo with a white heart-shaped face/bib, orange
# beak, flipper wings, orange feet, red bow tie. Proud chest-out pose (leans back a little).
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
    return keep(o, False)


NAVY, NAVY_D, NAVY_L = hexc("27346e"), hexc("161d45"), hexc("3f55a8")
WH, ORG, ORG_D, RED, RED_D = hexc("fbfdff"), hexc("ffa225"), hexc("e8641a"), hexc("ee2b45"), hexc("a8142e")



b = Body([(0, 1.02), (0.15, 1.3), (0.6, 1.44), (1.4, 1.36), (2.25, 1.06), (2.85, 0.64), (3.22, 0.2), (3.32, 0)],
         paint=lambda a, z, p: mix(NAVY, NAVY_L, 0.45 * smoothstep(1.8, 3.2, z)),
         lean=lambda z: 0.1 * (z / 3.3) ** 2, segs=44)
parts = [b.obj]

# white bib: heart-topped face mask, a neck pinch, then a round belly; projected from the front
right = [(0.0, 2.36), (0.22, 2.6), (0.5, 2.68), (0.78, 2.56), (0.92, 2.3), (0.86, 1.98), (0.8, 1.78),
         (0.92, 1.45), (1.0, 1.05), (0.9, 0.62), (0.62, 0.3), (0.3, 0.2), (0.0, 0.18)]
right = catmull(right, 4)
bib = right + [(-u, v) for u, v in reversed(right[1:-1])]
parts.append(grid_decal("Bib", list(reversed(bib)), WH, FRONT, off=0.006, th=0.006, on=["Body"], cell=0.14))

# beak, flippers, feet
parts.append(lathe("Beak", [(0, 0.28), (0.25, 0.24), (0.5, 0.12), (0.64, 0)], zgrad(ORG_D, ORG, 1.75, 2.0),
                   pos=(0, -1.12, 1.9), axis=(0, -1, -0.12), sx=1.25, sy=0.75, segs=12))
for sd in (-1, 1):
    fl = [(0, -0.3), (0.4, -0.36), (1.1, -0.26), (1.42, 0), (1.15, 0.24), (0.4, 0.34), (0, 0.3)]
    parts.append(puffy_slab(f"Flipper{sd}", fl, 0.2, (sd * 1.22, 0.0, 1.6), (sd * 0.75, -0.1, -0.65), (0, 1, 0),
                            along(NAVY, NAVY_D, (sd * 1.3, 0, 1.45), (sd * 1.9, 0, 0.6))))
    foot = [(-0.3, 0), (0.3, 0), (0.42, 0.42), (0.2, 0.55), (0.0, 0.42), (-0.2, 0.55), (-0.42, 0.42)]
    parts.append(puffy_slab(f"Foot{sd}", foot, 0.16, (sd * 0.55, -0.85, 0.09), (1, 0, 0), (sd * 0.15, -1, 0), ORG))

# bow tie under the beak
for sd in (-1, 1):
    wing = [(0.05, 0), (0.42, 0.2), (0.48, 0), (0.42, -0.2)]
    parts.append(puffy_slab(f"Bow{sd}", wing, 0.14, (0, -1.4, 1.22), (sd, -0.15, 0), (0, 0, 1), zgrad(RED_D, RED, 1.0, 1.42)))
parts.append(ball("Knot", 0.11, (0, -1.47, 1.22), RED, squash=(1, 0.8, 1.1)))

hat_axis = Vector((0.32, 0.05, 1)).normalized()
hp = Vector((0.22, 0.12, 3.02))
parts.append(lathe("HatBrim", [(0, 0.0), (0, 0.66), (0.08, 0.66), (0.08, 0)], NAVY_D, pos=hp, axis=hat_axis, segs=20))
parts.append(lathe("HatTop", [(0.05, 0), (0.05, 0.4), (0.78, 0.44), (0.78, 0)], hexc("1c1a28"), pos=hp, axis=hat_axis, segs=20))
parts.append(lathe("HatBand", [(0.1, 0), (0.1, 0.415), (0.27, 0.418), (0.27, 0)], RED, pos=hp, axis=hat_axis, segs=20))
f = Face(b, eye_v=2.2, eye_u=0.46)
f.eyes("round", w=0.36, h=0.48, look=(0, 0.02))
f.brows("raised", w=0.3, th=0.07, lift=-0.06, color=NAVY_D)
f.cheeks(color=hexc("ff9fb8"), u=0.78, v=1.86, w=0.26, h=0.13)
parts += f.parts
ship("slime_pengoo", parts)
