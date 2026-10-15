"""Scene / mesh operations: bevel, join, cleanup, apply, origin, counting."""
import bmesh, bpy
from mathutils import Vector

from .color import vcol_material


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def bevel(o, width=0.1, segments=1, angle=40, apply=True):
    """Angle-limited bevel: catches the light on hard edges (one segment = chamfer).
    Costs tris: about +2 per beveled edge per segment."""
    m = o.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = __import__("math").radians(angle)
    m.harden_normals = False
    if apply:
        apply_modifiers(o)
    return o


def apply_modifiers(o):
    select_only([o])
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def apply_transforms(o):
    select_only([o])
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return o


def decimate(o, ratio):
    m = o.modifiers.new("Decimate", "DECIMATE")
    m.ratio = ratio
    return apply_modifiers(o)


def join(name, objs):
    """Join parts into one mesh object (one MeshPart in Roblox)."""
    objs = [o for o in objs if o is not None]
    for o in objs:
        if o.modifiers:
            apply_modifiers(o)
    select_only(objs)
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


def cleanup(o, merge=0.0):
    """Recalc outward normals, delete loose verts/degenerate faces; merge=0 keeps parts
    separate (overlapping closed shells are fine for Roblox and keep colours exact)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    if merge > 0:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    for p in o.data.polygons:
        p.use_smooth = False
    return o


def origin_bottom_center(o):
    """Move geometry so the bbox bottom-centre sits at the object origin, origin at 0,0,0."""
    me = o.data
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    off = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)))
    for v in me.vertices:
        v.co -= off
    o.location = (0, 0, 0)
    me.update()
    return o


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def finish(name, parts, merge=0.0):
    """The usual last step of a model script: join -> cleanup -> origin bottom-centre ->
    one vertex-colour material. Returns the single shipping object."""
    o = join(name, parts)
    apply_transforms(o)
    cleanup(o, merge)
    origin_bottom_center(o)
    o.data.materials.clear()
    o.data.materials.append(vcol_material(name + "_vcol"))
    if "Col" in o.data.color_attributes:
        o.data.color_attributes.active_color = o.data.color_attributes["Col"]
    return o
