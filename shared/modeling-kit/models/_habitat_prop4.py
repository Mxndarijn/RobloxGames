# _habitat_prop4: small helpers for the habitat signature props (habitat_prop_<species>.py):
# lathe, torus, flat 2D-outline slabs (bolts, flags), per-face paint and the contract check.
import math
import bmesh, bpy
from mathutils import Euler, Matrix, Vector
from lib import *
from lib.shapes import obj_from_bm, _place

W_MAX, D_MAX, H_MIN, H_MAX = 1.9, 1.15, 0.5, 1.4


def lathe(name, prof, segs=12, pos=(0, 0, 0), rot=(0, 0, 0), color=None, squash=(1, 1, 1), phase=0.0):
    """Surface of revolution round local Z. prof: [(r, z), ...] bottom to top; r == 0 ends close to a point."""
    bm = bmesh.new()
    rings = []
    for r, z in prof:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((math.cos(phase + k * math.tau / segs) * r, math.sin(phase + k * math.tau / segs) * r, z))
                          for k in range(segs)])
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        for k in range(segs):
            if len(a) == 1:
                bm.faces.new((a[0], b[k], b[(k + 1) % segs]))
            elif len(b) == 1:
                bm.faces.new((a[k], a[(k + 1) % segs], b[0]))
            else:
                bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    if len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.scale(bm, vec=Vector(squash), verts=bm.verts)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm, color)


def torus(name, R, r, seg=16, seg2=6, pos=(0, 0, 0), rot=(0, 0, 0), color=None, arc=None):
    """Torus in local XY round Z (ring radius R, tube radius r). arc=(a0, a1) radians makes an open, capped arc."""
    bm = bmesh.new()
    closed = arc is None
    a0, a1 = (0.0, math.tau) if closed else arc
    n = seg if closed else seg + 1
    rings = []
    for i in range(n):
        a = a0 + (a1 - a0) * i / seg
        c, s = math.cos(a), math.sin(a)
        rings.append([bm.verts.new(((R + r * math.cos(b)) * c, (R + r * math.cos(b)) * s, r * math.sin(b)))
                      for b in (j * math.tau / seg2 for j in range(seg2))])
    pairs = list(zip(rings, rings[1:])) + ([(rings[-1], rings[0])] if closed else [])
    for p, q in pairs:
        for j in range(seg2):
            bm.faces.new((p[j], p[(j + 1) % seg2], q[(j + 1) % seg2], q[j]))
    if not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm, color)


def slab(name, pts, depth, pos=(0, 0, 0), rot=(0, 0, 0), color=None):
    """Flat outline (2D points in local X/Z, any shape, counter-clockwise) extruded `depth` along Y, centred."""
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in pts]
    back = [bm.verts.new((x, depth / 2, z)) for x, z in pts]
    n = len(pts)
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for k in range(n):
        bm.faces.new((front[k], back[k], back[(k + 1) % n], front[(k + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    _place(bm, pos, rot)
    return obj_from_bm(name, bm, color)


def paint(o, fn):
    """Per-face colour: fn(centre: Vector, normal: Vector) -> colour (world space; builders have identity matrices)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        c = fn(f.calc_center_median(), f.normal)
        for lp in f.loops:
            lp[layer] = c
    bm.to_mesh(o.data)
    bm.free()
    return o


def move(o, pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Bake a transform into the mesh (keeps identity object matrices, which paint()/gradient() assume)."""
    m = Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4() @ \
        Matrix.Diagonal(Vector(scale)).to_4x4()
    o.data.transform(m)
    return o


def floor(o, z=0.0):
    for v in o.data.vertices:
        v.co.z = max(v.co.z, z)
    return o


def prop_finish(name, parts):
    o = finish(name, parts)
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    zs = [v.co.z for v in o.data.vertices]
    w, d, h = max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)
    ok = w <= W_MAX + 1e-3 and d <= D_MAX + 1e-3 and H_MIN <= h <= H_MAX + 1e-3
    print(f"PROPCHECK {name}: w={w:.2f} d={d:.2f} h={h:.2f} {'OK' if ok else 'OUT OF CONTRACT'}")
    return o


def ribbon(name, pts, widths, thick=0.04, up=(0, 0, 1), color=None):
    """Flat strip swept along a polyline; the width runs along `up` (made square to the path), thickness across it."""
    P = [Vector(p) for p in pts]
    U = Vector(up)
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(P):
        t = (P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized()
        s = (U - t * U.dot(t)).normalized()
        n = t.cross(s).normalized()
        w = widths[i] if isinstance(widths, (list, tuple)) else widths
        rings.append([bm.verts.new(p + s * w / 2 * a + n * thick / 2 * b) for a, b in ((1, 1), (-1, 1), (-1, -1), (1, -1))])
    for a, b in zip(rings, rings[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, color)


def scallop(name, R, spread=160, ribs=7, cup=0.14, thick=0.05, nu=4, rib_h=0.035, color_fn=None, per_rib=2):
    """Ribbed scallop shell half: a fan opening toward +Y from a hinge at the origin, cupped up (+Z), with a
    scalloped edge. color_fn(rib_index_parity, u) -> colour per face (u 0 hinge .. 1 edge)."""
    sp = math.radians(spread)
    nv = ribs * per_rib
    bm = bmesh.new()
    top, bot = [], []
    for i in range(nu + 1):
        u = 0.14 + 0.86 * i / nu
        rt, rb = [], []
        for j in range(nv + 1):
            v = -sp / 2 + sp * j / nv
            ph = math.cos(ribs * math.tau * j / nv / 2 * 2)  # +1 on a rib, -1 in a groove
            rr = R * u * (1 + 0.05 * ph * u)
            x, y = math.sin(v) * rr, math.cos(v) * rr
            z = cup * u * u + rib_h * u * (0.5 + 0.5 * ph)
            rt.append(bm.verts.new((x, y, z)))
            rb.append(bm.verts.new((x, y, z - thick)))
        top.append(rt)
        bot.append(rb)
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((top[i][j], top[i][j + 1], top[i + 1][j + 1], top[i + 1][j]))
            bm.faces.new((bot[i][j], bot[i + 1][j], bot[i + 1][j + 1], bot[i][j + 1]))
    for j in range(nv):  # hinge and outer edge
        bm.faces.new((top[0][j + 1], top[0][j], bot[0][j], bot[0][j + 1]))
        bm.faces.new((top[nu][j], top[nu][j + 1], bot[nu][j + 1], bot[nu][j]))
    for i in range(nu):  # the two straight sides
        bm.faces.new((top[i][0], top[i + 1][0], bot[i + 1][0], bot[i][0]))
        bm.faces.new((top[i + 1][nv], top[i][nv], bot[i][nv], bot[i + 1][nv]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        c = f.calc_center_median()
        u = min(1.0, c.length / R)
        j = (math.atan2(c.x, c.y) + sp / 2) / sp * nv
        par = int((j + 1) / 2) % 2
        col = color_fn(par, u) if color_fn else (1, 1, 1, 1)
        for lp in f.loops:
            lp[layer] = col
    return obj_from_bm(name, bm)
