"""Merging goo from metaballs (headless-safe): elements -> polygonised mesh -> decimate -> closed,
painted, smooth-flagged mesh object. Metaball fields add up, so drips, collars and drops fuse
into one rounded skin with no booleans or sculpting.

    els = [Ball((0, 0, 1), 1.2), Ball((0, 0, 2.5), (1.6, 1.0, 0.5), rot=quat)]
    o = metaball_mesh("Goo", els, resolution=0.3, tris=600)
    paint_goo(o, lambda co, n: GOO)

Ball sizes are the SURFACE semi-axes of the lone element (threshold 0.6, stiffness 2: the
surface sits at 0.574 x the field radius); merged elements bulge out a little more.
"""
import bmesh, bpy
from mathutils import Quaternion, Vector

SURF = 0.574  # lone-ball surface radius / field radius at threshold 0.6, stiffness 2


class Ball:
    def __init__(self, co, size, rot=None, kind="ELLIPSOID"):
        self.co = Vector(co)
        s = size if isinstance(size, (tuple, list)) else (size, size, size)
        self.size = Vector(s)
        self.rot = rot or Quaternion()
        self.kind = kind


def frame_quat(x, y, z):
    """rotation whose local x/y/z axes are the given (orthonormal) world vectors."""
    from mathutils import Matrix
    return Matrix((x, y, z)).transposed().to_quaternion()


def nonmanifold(bm):
    return sum(1 for e in bm.edges if not e.is_manifold)


def metaball_mesh(name, balls, resolution=0.3, tris=None, smooth=0, clamp_z=None):
    """name must not contain '.': metaball objects merge by name family (text before the dot).
    tris = decimate (COLLAPSE) target; clamp_z flattens everything below that height (keeps it closed)."""
    assert "." not in name
    mb = bpy.data.metaballs.new(name)
    mb.resolution = mb.render_resolution = resolution
    mb.threshold = 0.6
    ob = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(ob)
    for b in balls:
        e = mb.elements.new()
        e.type = b.kind
        e.co = b.co
        r = max(b.size) / SURF
        e.radius = r
        e.size_x, e.size_y, e.size_z = (b.size / max(b.size))[:]
        e.rotation = b.rot
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(ob)
    bpy.data.metaballs.remove(mb)
    me.name = name
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if smooth:
        m = o.modifiers.new("Smooth", "SMOOTH")
        m.iterations = smooth
        m.factor = 0.5
    if tris:
        n = sum(len(p.vertices) - 2 for p in me.polygons)
        if n > tris:
            m = o.modifiers.new("Decimate", "DECIMATE")
            m.ratio = tris / n
            m.use_collapse_triangulate = True
    if o.modifiers:
        dg = bpy.context.evaluated_depsgraph_get()
        me2 = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        o.modifiers.clear()
        o.data = me2
        bpy.data.meshes.remove(me)
        me = me2
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=bm.edges)
    if nonmanifold(bm):  # decimate can leave a pinched edge/hole: close it
        bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=8)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    if clamp_z is not None:
        for v in bm.verts:
            v.co.z = max(v.co.z, clamp_z)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o["nm"] = nonmanifold(bm)
    bm.to_mesh(me)
    bm.free()
    return o


def paint_goo(o, color_fn, smooth=True):
    """Add 'Col' (corner) + keep_smooth=1 per face; color_fn(world co, vertex normal) -> RGBA."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.normal_update()
    col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    sm = bm.faces.layers.int.get("keep_smooth") or bm.faces.layers.int.new("keep_smooth")
    mw = o.matrix_world
    for f in bm.faces:
        f.smooth = smooth
        f[sm] = int(smooth)
        for lp in f.loops:
            lp[col] = color_fn(mw @ lp.vert.co, (mw.to_3x3() @ lp.vert.normal).normalized())
    bm.to_mesh(o.data)
    bm.free()
    return o
