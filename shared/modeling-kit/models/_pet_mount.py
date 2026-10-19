# Shared builders for the pet_mount_* cosmetics (not an asset). Smooth, soft, rounded slime-cartoon style:
# metaball clouds (shared with pet_cloud: _pet_cloud.py) and "pillow" shells (rounded boxes pushed through a superellipsoid map),
# all smooth shaded with vertex colours painted per vertex normal/position.
# Size contract (same as pet_cloud): footprint 3.3 (x) x 2.4 (y) studs, <= ~1.3 high, origin bottom centre,
# front faces -Y, the pet sits on a flat-ish top at about z = 1.2 (SEAT_Z in the stats print is the measured one).
import math, os
import bmesh, bpy
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from lib import *

SIZE_X, SIZE_Y = 3.3, 2.4


def clamp(t, lo=0.0, hi=1.0):
    return max(lo, min(hi, t))


def sstep(a, b, t):
    t = clamp((t - a) / (b - a))
    return t * t * (3 - 2 * t)


def mixn(cols, t):
    """piecewise-linear colour ramp: cols = [(stop, colour), ...] ascending."""
    if t <= cols[0][0]:
        return cols[0][1]
    for (t0, c0), (t1, c1) in zip(cols, cols[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / (t1 - t0))
    return cols[-1][1]


def paint(o, fn, smooth=True):
    return paint_goo(o, fn, smooth)


# ------------------------------------------------------------------ pillow shell
def _S(t, p):
    return math.copysign(abs(t) ** p, t)


def pillow(name, a, b, c, pos=(0, 0, 0), nx=16, ny=12, nz=6, pxy=1.0, pz=1.0, wprof=None, bend=None):
    """Rounded slab with half sizes a,b,c. pxy/pz < 1 squares the plan/profile off (flat top, round rim).
    wprof(u) scales y along the length (leaf outline); bend(p) -> p warps the finished shell."""
    bm = bmesh.new()
    verts = {}

    def V(i, j, k):
        key = (i, j, k)
        if key not in verts:
            d = Vector((2 * i / nx - 1, 2 * j / ny - 1, 2 * k / nz - 1)).normalized()
            x, y, z = a * _S(d.x, pxy), b * _S(d.y, pxy), c * _S(d.z, pz)
            if wprof:
                y *= wprof(x / a)
            p = Vector((x + pos[0], y + pos[1], z + pos[2]))
            verts[key] = bm.verts.new(bend(p) if bend else p)
        return verts[key]

    for i in range(nx):
        for j in range(ny):
            for k in (0, nz):
                bm.faces.new((V(i, j, k), V(i + 1, j, k), V(i + 1, j + 1, k), V(i, j + 1, k)))
    for i in range(nx):
        for k in range(nz):
            for j in (0, ny):
                bm.faces.new((V(i, j, k), V(i + 1, j, k), V(i + 1, j, k + 1), V(i, j, k + 1)))
    for j in range(ny):
        for k in range(nz):
            for i in (0, nx):
                bm.faces.new((V(i, j, k), V(i, j + 1, k), V(i, j + 1, k + 1), V(i, j, k + 1)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def slab(name, outline, c, pos=(0, 0, 0), M=48, nt=8, nr=5, nb=4, e=0.08, bend=None):
    """Polar rounded slab (even vertex spread for painted patterns): outline(theta) -> (x, y) boundary point, half
    thickness c, plan rings from the centre out to the rim, a half-round rim profile (plan swell e, height c) and the
    underside back in. bend(p) -> p warps the finished shell."""
    bm = bmesh.new()
    B = [outline(k * math.tau / M) for k in range(M)]
    top = bm.verts.new(Vector((0, 0, c)) + Vector(pos))

    def P(x, y, z):
        v = Vector((x + pos[0], y + pos[1], z + pos[2]))
        return bm.verts.new(bend(v) if bend else v)
    rings = []
    for i in range(1, nt + 1):
        s = i / nt
        rings.append([P(bx * s, by * s, c) for bx, by in B])
    for j in range(1, nr):
        ph = math.pi * j / nr
        k = 1 + e * math.sin(ph)
        rings.append([P(bx * k, by * k, c * math.cos(ph)) for bx, by in B])
    for i in range(nb or nt, 0, -1):
        s = i / (nb or nt)
        rings.append([P(bx * s, by * s, -c) for bx, by in B])
    bot = bm.verts.new(bend(Vector((0, 0, -c)) + Vector(pos)) if bend else Vector((0, 0, -c)) + Vector(pos))
    if bend:
        top.co = bend(top.co.copy())
    for k in range(M):
        j = (k + 1) % M
        bm.faces.new((top, rings[0][j], rings[0][k]))
        bm.faces.new((bot, rings[-1][k], rings[-1][j]))
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(M):
            j = (k + 1) % M
            bm.faces.new((r0[k], r0[j], r1[j], r1[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def squircle(a, b, n=4.5):
    """outline(theta) of a rounded rectangle with half sizes a, b."""
    def f(t):
        ct, st = math.cos(t), math.sin(t)
        return (a * _S(ct, 2 / n), b * _S(st, 2 / n))
    return f


def sphere(name, r, pos, squash=(1, 1, 1), subdiv=3):
    return blob(name, r, pos, seed=0, subdiv=subdiv, squash=squash, jitter=0.0)


def extrude_poly(name, pts, depth, pos=(0, 0, 0), bevel_w=0.04):
    """Chunky rounded sign-like solid: polygon pts (x, z) extruded along y (centred), bevelled."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, -depth / 2, z)) for x, z in pts]
    f = bmesh.ops.contextual_create(bm, geom=vs)["faces"][0]
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    vv = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, depth, 0)), verts=vv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel_w, segments=2, profile=0.6, affect="EDGES")
    bmesh.ops.translate(bm, vec=Vector(pos), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def crystal(name, base, direction, length, r):
    """hex prism with a pointed tip, rounded by one bevel pass."""
    bm = bmesh.new()
    segs = 6
    ring0 = [bm.verts.new((math.cos(k * math.tau / segs) * r, math.sin(k * math.tau / segs) * r, 0)) for k in range(segs)]
    ring1 = [bm.verts.new((math.cos(k * math.tau / segs) * r * 0.92, math.sin(k * math.tau / segs) * r * 0.92, length * 0.72)) for k in range(segs)]
    tip = bm.verts.new((0, 0, length))
    for k in range(segs):
        j = (k + 1) % segs
        bm.faces.new((ring0[k], ring0[j], ring1[j], ring1[k]))
        bm.faces.new((ring1[k], ring1[j], tip))
    bm.faces.new(list(reversed(ring0)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=r * 0.14, segments=1, affect="EDGES")
    q = Vector(direction).normalized().to_track_quat("Z", "Y")
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(base)) @ q.to_matrix().to_4x4(), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def soft_tube(name, points, radii, segs=8):
    """tapered smooth tube with round ends (caps pulled into a point by a final ring)."""
    return tube(name, points, radii, segs=segs)


# ------------------------------------------------------------------ clouds
# The cloud mounts do not build their own cloud: they call models/_pet_cloud.py cloud_parts() (the pet_cloud builder)
# with extra puffs / a colour function, so every cloud shares one shape, one smooth pass and one footprint fit.
from models._pet_cloud import cloud_parts  # noqa: E402,F401


# ------------------------------------------------------------------ ring slab with per-face colours
def ring_slab(name, top_rings, c, colour, nr=3, e=0.05, bottom=(0.7, 0.35), bend=None):
    """Slab from explicit top rings (each a list of M (x, y) points, centre outwards; the last is the rim line), so a
    pattern can have exact edges: every face gets ONE colour from colour(zone, i, k, centroid) (zone 'top' / 'rim' /
    'bot', ring index i, segment k), which keeps hard colour steps on a smooth-shaded mesh. Half thickness c, a
    half-round rim (plan swell e), then the underside back in over the `bottom` scales. bend(p) -> p warps it."""
    M = len(top_rings[0])
    bm = bmesh.new()

    def P(x, y, z):
        v = Vector((x, y, z))
        return bm.verts.new(bend(v) if bend else v)
    top = P(0, 0, c)
    rings = [[P(x, y, c) for x, y in r] for r in top_rings]
    last = top_rings[-1]
    for j in range(1, nr):
        ph = math.pi * j / nr
        k = 1 + e * math.sin(ph)
        rings.append([P(x * k, y * k, c * math.cos(ph)) for x, y in last])
    for s in bottom:
        rings.append([P(x * s, y * s, -c) for x, y in last])
    bot = P(0, 0, -c)
    ntop = len(top_rings)
    faces = []
    for k in range(M):
        j = (k + 1) % M
        faces.append((bm.faces.new((top, rings[0][j], rings[0][k])), "top", 0, k))
        faces.append((bm.faces.new((bot, rings[-1][k], rings[-1][j])), "bot", len(rings) - 1, k))
    for i, (r0, r1) in enumerate(zip(rings, rings[1:])):
        zone = "top" if i + 1 < ntop else ("rim" if i + 1 < ntop + nr else "bot")
        for k in range(M):
            j = (k + 1) % M
            faces.append((bm.faces.new((r0[k], r0[j], r1[j], r1[k])), zone, i + 1, k))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = bm.loops.layers.color.new("Col")
    sm = bm.faces.layers.int.new("keep_smooth")
    bm.faces.ensure_lookup_table()
    for fi, (_, zone, i, k) in enumerate(faces):  # (the face refs die in recalc: look them up by creation index)
        f = bm.faces[fi]
        f.smooth = True
        f[sm] = 1
        cc = colour(zone, i, k, f.calc_center_median())
        for lp in f.loops:
            lp[col] = cc
    return obj_from_bm(name, bm, smooth=True)


# ------------------------------------------------------------------ fit + ship
def bbox(objs):
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in objs:
        mw = o.matrix_world
        for v in o.data.vertices:
            w = mw @ v.co
            for i in range(3):
                lo[i], hi[i] = min(lo[i], w[i]), max(hi[i], w[i])
    return lo, hi


def fit_xy(parts, sx=SIZE_X, sy=SIZE_Y):
    """scale the whole set in x/y so the footprint is exactly the cloud's 3.3 x 2.4."""
    lo, hi = bbox(parts)
    kx, ky = sx / (hi.x - lo.x), sy / (hi.y - lo.y)
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
    for o in parts:
        for v in o.data.vertices:
            v.co.x = (v.co.x - cx) * kx
            v.co.y = (v.co.y - cy) * ky
        o.data.update()


def ship(name, parts, fit=True):
    """fit footprint -> finish() (join, bottom-centre) -> restore smooth flags, FBX smooth normals."""
    print("PET_MOUNT_PARTS " + name + " " + " ".join("%s=%d" % (o.name, sum(len(p.vertices) - 2 for p in o.data.polygons)) for o in parts))
    for o in parts:
        bpy.context.view_layer.update()
        o.data.transform(o.matrix_world)  # bake any rotation/scale into the vertices
        o.matrix_world = Matrix.Identity(4)
        if "keep_smooth" not in o.data.attributes:
            paint_attr_smooth(o, True)
    if fit:
        fit_xy(parts)
    o = finish(name, parts)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    o["smooth_normals"] = 1
    lo, hi = bbox([o])
    print("PET_MOUNT " + name + " size=%.2f x %.2f x %.2f seat_z=%.2f" % (hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, seat_z(o)))
    return o


def paint_attr_smooth(o, on):
    a = o.data.attributes.new("keep_smooth", "INT", "FACE")
    for d in a.data:
        d.value = int(on)


def seat_z(o, x=0.0, y=0.0):
    """height of the top surface under (x, y) (ray down from above) in object space."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    t = BVHTree.FromBMesh(bm)
    hit = t.ray_cast(Vector((x, y, 9.0)), Vector((0, 0, -1)))
    bm.free()
    return hit[0].z if hit[0] else 0.0
