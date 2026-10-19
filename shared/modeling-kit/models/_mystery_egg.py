# Mystery Egg helpers (not an asset). One analytic egg shell shared by every tier, so the
# game can swap meshes at one size: H 2.2 tall, max width 2*R = 1.7, bottom pole on z=0.
# Decorations hug the same analytic surface:
#   decal()  closed slab projected onto the shell (spots, stars, gem facets, studs)
#   ribbon() raised band swept round the shell (closed loop or open tapered swirl)
# ship() joins, restores smooth shading on the shell (decals stay flat) and exports smooth normals.
import math
import bmesh
from mathutils import Vector
from lib import *
from lib.shapes import obj_from_bm

H = 2.2      # egg height (studs)
R = 0.85     # max radius (width 1.7)
K = 0.13     # asymmetry: >0 = fatter bottom, pointier top


def _raw_r(t):
    return math.sin(t) * (1 + K * math.cos(t))


_RMAX = max(_raw_r(i * math.pi / 2000) for i in range(2001))


def surf(t, th, off=0.0):
    """Shell point at meridian angle t (0 = bottom pole, pi = top pole) and azimuth th,
    pushed `off` studs along the normal."""
    r = R * _raw_r(t) / _RMAX
    z = H / 2 * (1 - math.cos(t))
    p = Vector((r * math.cos(th), r * math.sin(th), z))
    if off:
        p += normal(t, th) * off
    return p


def normal(t, th):
    e = 1e-4
    t = min(max(t, 2e-4), math.pi - 2e-4)
    dt = surf(t + e, th) - surf(t - e, th)
    dth = surf(t, th + e) - surf(t, th - e)
    n = dth.cross(dt)
    if n.length < 1e-9:
        return Vector((0, 0, 1 if t > 1.5 else -1))
    n.normalize()
    # outward: away from the axis point at the same height
    c = surf(t, th)
    if n.dot(Vector((c.x, c.y, 0)) + Vector((0, 0, (c.z - H / 2) * 0.2))) < 0:
        n = -n
    return n


def t_of_z(z):
    return math.acos(max(-1.0, min(1.0, 1 - 2 * z / H)))


def radius_at_z(z):
    return R * _raw_r(t_of_z(z)) / _RMAX


def tangents(t, th):
    """(u along the azimuth, v up the meridian, n) at a shell point."""
    n = normal(t, th)
    v = (surf(min(t + 1e-3, math.pi), th) - surf(max(t - 1e-3, 0), th)).normalized()
    u = v.cross(n).normalized()
    v = n.cross(u).normalized()
    return u, v, n


def project(p, off):
    """Closest-ish shell point to p (same azimuth and height), pushed off along the normal."""
    t = t_of_z(min(max(p.z, 1e-4), H - 1e-4))
    th = math.atan2(p.y, p.x)
    return surf(t, th, off)


def shell(name, color_fn, segs=24, rows=18, smooth=True, per_vertex=False):
    """The egg body. color_fn(s, th, t) -> RGBA per face, s = face centre height / H.
    per_vertex=True evaluates color_fn at each vertex instead (soft gradients/highlights)."""
    bm = bmesh.new()
    rings = []
    for i in range(rows + 1):
        t = math.pi * i / rows
        if i == 0 or i == rows:
            rings.append([bm.verts.new(surf(t, 0))])
        else:
            rings.append([bm.verts.new(surf(t, k * math.tau / segs)) for k in range(segs)])
    info = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segs):
            k1 = (k + 1) % segs
            if len(a) == 1:
                vs = (a[0], b[k1], b[k])
            elif len(b) == 1:
                vs = (a[k], a[k1], b[0])
            else:
                vs = (a[k], a[k1], b[k1], b[k])
            bm.faces.new(vs)
            info.append((i, k))
    bm.faces.ensure_lookup_table()
    col = bm.loops.layers.color.new("Col")
    sm = bm.faces.layers.int.new("keep_smooth")
    for fi, (i, k) in enumerate(info):
        f = bm.faces[fi]
        c = f.calc_center_median()
        tc = math.pi * (i + 0.5) / rows
        thc = (k + 0.5) * math.tau / segs
        rgba = color_fn(c.z / H, thc, tc)
        for lp in f.loops:
            if per_vertex:
                vc = lp.vert.co
                vt = t_of_z(min(max(vc.z, 0.0), H))
                rgba = color_fn(vc.z / H, math.atan2(vc.y, vc.x) if (vc.x or vc.y) else thc, vt)
            lp[col] = (*rgba[:3], 1.0)
        f[sm] = int(smooth)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def _flat_attr(bm):
    return bm.faces.layers.int.get("keep_smooth") or bm.faces.layers.int.new("keep_smooth")


def decal(name, t, th, poly, lift=0.02, lift_c=None, sink=0.05, color_fn=None, color=None, spin=0.0):
    """Closed slab hugging the shell at (t, th). poly = 2D outline [(x, y)] in studs around the
    centre (x along the azimuth, y up the meridian), star-shaped about (0, 0). lift = rim height
    above the shell, lift_c = centre height (> lift makes a pyramid / faceted gem).
    color_fn(kind, k, face) -> RGBA with kind 'top' (k = rim index) or 'side'."""
    lift_c = lift if lift_c is None else lift_c
    c0 = surf(t, th)
    u, v, n = tangents(t, th)
    cs, sn = math.cos(spin), math.sin(spin)
    bm = bmesh.new()
    top, bot = [], []
    for x, y in poly:
        x, y = x * cs - y * sn, x * sn + y * cs
        p = c0 + u * x + v * y
        top.append(bm.verts.new(project(p, lift)))
        bot.append(bm.verts.new(project(p, -sink)))
    ct = bm.verts.new(surf(t, th, lift_c))
    cb = bm.verts.new(surf(t, th, -sink))
    m = len(poly)
    faces = []
    for k in range(m):
        k1 = (k + 1) % m
        faces.append(("top", k, bm.faces.new((ct, top[k], top[k1]))))
        faces.append(("bot", k, bm.faces.new((cb, bot[k1], bot[k]))))
        faces.append(("side", k, bm.faces.new((top[k], bot[k], bot[k1], top[k1]))))
    bm.faces.index_update()
    faces = [(kind, k, f.index) for kind, k, f in faces]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    bm.normal_update()
    colr = bm.loops.layers.color.new("Col")
    sm = _flat_attr(bm)
    for kind, k, fi in faces:
        f = bm.faces[fi]
        rgba = color_fn(kind, k, f) if color_fn else color
        for lp in f.loops:
            lp[colr] = (*rgba[:3], 1.0)
        f[sm] = 0
    return obj_from_bm(name, bm)


def ribbon(name, samples, closed=True, section=((-1, 0.02), (-0.5, 1.0), (0.5, 1.0), (1, 0.02)),
           lift=0.07, sink=0.05, color_fn=None, smooth=False):
    """Raised band on the shell. samples = [(th, z_centre, half_width)] along the band.
    section = [(across -1..1, lift fraction)] for the outer surface; the inner side sits `sink`
    under the shell. color_fn(j, i, f) -> RGBA (j = sample index, i = section face index).
    Open ribbons get end caps."""
    bm = bmesh.new()
    rows = []
    for th, zc, hw in samples:
        ring = []
        for a, lf in section:
            z = zc + a * hw
            ring.append(bm.verts.new(surf(t_of_z(z), th, lift * lf)))
        for a in (section[-1][0], section[0][0]):  # inner side: just the two edges
            z = zc + a * hw
            ring.append(bm.verts.new(surf(t_of_z(z), th, -sink)))
        rows.append(ring)
    n = len(rows[0])
    pairs = list(zip(rows, rows[1:])) + ([(rows[-1], rows[0])] if closed else [])
    faces = []
    for j, (a, b) in enumerate(pairs):
        for i in range(n):
            i1 = (i + 1) % n
            faces.append((j, i, bm.faces.new((a[i], a[i1], b[i1], b[i]))))
    if not closed:
        faces.append((0, -1, bm.faces.new(list(reversed(rows[0])))))
        faces.append((len(rows) - 1, -1, bm.faces.new(rows[-1])))
    bm.faces.index_update()
    faces = [(j, i, f.index) for j, i, f in faces]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    bm.normal_update()
    colr = bm.loops.layers.color.new("Col")
    sm = _flat_attr(bm)
    for j, i, fi in faces:
        f = bm.faces[fi]
        rgba = color_fn(j, i, f)
        for lp in f.loops:
            lp[colr] = (*rgba[:3], 1.0)
        f[sm] = int(smooth)
    return obj_from_bm(name, bm)


# --- 2D outlines -----------------------------------------------------------------------
def circle(r, n=8, wobble=0.0, seed=0, sx=1.0, sy=1.0):
    rr = rng(seed)
    return [(r * sx * math.cos(k * math.tau / n) * (1 + wobble * (rr.random() * 2 - 1)),
             r * sy * math.sin(k * math.tau / n) * (1 + wobble * (rr.random() * 2 - 1))) for k in range(n)]


def star(r, points=5, inner=0.45):
    out = []
    for k in range(points * 2):
        a = math.pi / 2 + k * math.pi / points
        rr = r if k % 2 == 0 else r * inner
        out.append((rr * math.cos(a), rr * math.sin(a)))
    return out


def diamond(w, h):
    return [(0, h), (-w, 0), (0, -h), (w, 0)]


def facet_shade(f, lo, hi):
    """Per-facet light/dark by how a face points toward the kit's front-left-top light."""
    L = Vector((-0.45, -0.6, 0.66)).normalized()
    d = max(0.0, min(1.0, 0.5 + 0.5 * f.normal.dot(L)))
    return mix(lo, hi, d)


def ship(name, parts):
    print("EGG_PARTS " + name + " " + " ".join("%s=%d" % (o.name, sum(len(p.vertices) - 2 for p in o.data.polygons)) for o in parts))
    o = finish(name, parts)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    o["smooth_normals"] = 1
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    zs = [v.co.z for v in o.data.vertices]
    print("EGG %s size=%.2f x %.2f x %.2f" % (name, max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)))
    return o
