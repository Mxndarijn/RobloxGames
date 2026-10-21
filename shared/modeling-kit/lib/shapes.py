"""Low-poly primitives. Every builder returns a new mesh object linked to the scene,
flat-shaded, painted with one vertex colour. Units: 1 Blender unit = 1 stud, Z up,
model standing on z=0 (see lib.units)."""
import math, random
import bmesh, bpy
from mathutils import Euler, Matrix, Vector, noise

from .color import gradient_bm, paint_bm


def rng(seed):
    return seed if isinstance(seed, random.Random) else random.Random(seed)


def obj_from_bm(name, bm, color=None, smooth=False):
    if color is not None:
        paint_bm(bm, color)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def _place(bm, pos=(0, 0, 0), rot=(0, 0, 0)):
    m = Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)


def jitter_bm(bm, amount, seed, keep_bottom=False):
    """Random radial wobble per vertex (amount = fraction of distance from the axis)."""
    r = rng(seed)
    for v in bm.verts:
        if keep_bottom and v.co.z <= 1e-4:
            continue
        k = 1 + (r.random() * 2 - 1) * amount
        v.co.x *= k
        v.co.y *= k
        if not keep_bottom:
            v.co.z *= 1 + (r.random() * 2 - 1) * amount * 0.5


def noise_bm(bm, amount, scale=1.0, seed=0):
    """Smooth (Perlin) displacement along the vertex normal: organic lumps, no spikes."""
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    bm.normal_update()
    for v in bm.verts:
        n = noise.noise(v.co * scale + off)
        v.co += v.normal * n * amount


def box(name, size, pos=(0, 0, 0), color=None, rot=(0, 0, 0)):
    """Centred box of size (x, y, z)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm, color)


def cylinder(name, r, h, pos=(0, 0, 0), color=None, segs=8, r_top=None, rot=(0, 0, 0), jitter=0.0, seed=0, cap=True):
    """Cylinder/frustum standing on pos (base at pos.z), r_top=0 makes a cone."""
    bm = bmesh.new()
    rt = r if r_top is None else r_top
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segs, radius1=r, radius2=max(rt, 0.0), depth=h)
    bmesh.ops.translate(bm, vec=Vector((0, 0, h / 2)), verts=bm.verts)
    if rt <= 0:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    if jitter:
        jitter_bm(bm, jitter, seed, keep_bottom=True)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm, color)


def cone(name, r, h, pos=(0, 0, 0), color=None, segs=8, **kw):
    return cylinder(name, r, h, pos, color, segs, r_top=0.0, **kw)


def blob(name, radius, pos=(0, 0, 0), color=None, seed=0, subdiv=1, squash=(1, 1, 1), jitter=0.12, lumps=0.0, lump_scale=1.0, rot=(0, 0, 0)):
    """Icosphere blob: subdiv 1 = 20 tris (spiky), 2 = 80 (puffy low-poly), 3 = 320. squash scales x,y,z.
    jitter = random per-vertex radius change, lumps = smooth noise displacement."""
    r = rng(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    for v in bm.verts:
        v.co *= 1 + (r.random() * 2 - 1) * jitter
    if lumps:
        noise_bm(bm, lumps * radius, lump_scale / radius, r.randint(0, 999))
    bmesh.ops.scale(bm, vec=Vector(squash), verts=bm.verts)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm, color)


def tube(name, points, radii, color=None, segs=6, seed=0, jitter=0.0, twist_free=False):
    """Tapered tube along a polyline (branches, roots, horns). points: list of (x,y,z);
    radii: one per point. Capped at both ends, rings oriented along the path.
    twist_free: carry each ring's orientation on from the last (parallel transport) instead of re-aiming it per
    point; to_track_quat can roll a ring up to 180 degrees where a long path bends (e.g. vertical to sloped), which
    pinches the tube into an X there."""
    r = rng(seed)
    pts = [Vector(p) for p in points]
    bm = bmesh.new()
    rings = []
    q, prev = None, None
    for i, (p, rad) in enumerate(zip(pts, radii)):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if twist_free and q is not None:
            q = prev.rotation_difference(d) @ q
        else:
            q = d.to_track_quat("Z", "Y")
        prev = d
        ring = []
        for k in range(segs):
            a = k * math.tau / segs
            j = 1 + (r.random() * 2 - 1) * jitter
            ring.append(bm.verts.new(p + q @ Vector((math.cos(a) * rad * j, math.sin(a) * rad * j, 0))))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, color)


def gradient(o, bottom, top, z0=None, z1=None):
    """Repaint an existing object with a vertical gradient (object-space z)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    if z0 is not None or z1 is not None:
        mw = o.matrix_world
        zs = [(mw @ v.co).z for v in bm.verts]
        z0 = min(zs) if z0 is None else z0
        z1 = max(zs) if z1 is None else z1
        # convert world z range into local z (objects from these builders have identity matrices)
        z0 -= mw.translation.z
        z1 -= mw.translation.z
    gradient_bm(bm, bottom, top, z0, z1)
    bm.to_mesh(o.data)
    bm.free()
    return o
