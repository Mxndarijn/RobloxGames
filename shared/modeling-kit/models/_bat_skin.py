"""Shared bits for the Bat skins (models/bat_skin_<id>.py, Steal a Slime Exclusive Shop, contract §10).

A Bat skin is another mesh on the same Tool Handle as ranch_bat, held with the SAME Tool.Grip
(CFrame.new(0, -1.345, 0)): so every skin keeps ranch_bat's frame:
  * long axis Z, hand end (pommel) on z = 0, total height HEIGHT = 5.09 (ranch_bat's bbox height),
  * grip point (hand) GRIP = (0, 0, 1.2): centre of a ~0.27-radius round grip from z 0.8 to 1.8,
  * bbox centred on the grip axis in X and Y (symmetric extents), so the mesh centre sits on the axis.
`ship_skin()` checks the height and prints the Roblox grip offset; it must read (0.00, -1.35, 0.00).
Builders (lathe, rings_shell, torus, sweep, ico, box_part, place, ship) come from models/_pvp_fun.py.
"""
import bmesh
from mathutils import Vector

from lib.shapes import obj_from_bm
from models._pvp_fun import *  # noqa: F401,F403  (builders + palette names)
from models._pvp_fun import _paint, ship

HEIGHT = 5.09  # ranch_bat bbox height (pommel bottom to goo-cap top)
GRIP = (0, 0, 1.2)  # ranch_bat grip: red wrap centre above the pommel bottom
WRAP = (0.8, 1.8)  # z range of the grip wrap on every skin


def slab(name, outline, thick, colour, y=0.0, smooth=False, bevel_w=0.0):
    """A flat closed plate: a 2D outline in the XZ plane [(x, z)] (counter-clockwise seen from -Y,
    concave allowed) extruded `thick` studs along Y, centred on `y`. colour: RGBA or colour(0, 0, centre)."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y - thick / 2, z)) for x, z in outline]
    face = bm.faces.new(front)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.y += thick
    if bevel_w > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel_w, segments=1, affect="EDGES", profile=0.5)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _paint(bm, [(0, 0)] * len(bm.faces), colour, smooth)
    return obj_from_bm(name, bm, smooth=smooth)


def bounds(parts):
    import bpy
    bpy.context.view_layer.update()
    lo = Vector((min(min((o.matrix_world @ v.co)[i] for v in o.data.vertices) for o in parts) for i in range(3)))
    hi = Vector((max(max((o.matrix_world @ v.co)[i] for v in o.data.vertices) for o in parts) for i in range(3)))
    return lo, hi


def ship_skin(name, parts):
    """Checks the ranch_bat frame (height, axis-centred bbox), then ship() with the shared grip."""
    lo, hi = bounds(parts)
    print("SKIN_FRAME %s z=%.3f..%.3f x=%.3f..%.3f y=%.3f..%.3f" % (name, lo.z, hi.z, lo.x, hi.x, lo.y, hi.y))
    assert abs(lo.z) < 0.006 and abs(hi.z - HEIGHT) < 0.006, "skin must span z 0..%.2f like ranch_bat" % HEIGHT
    assert abs(lo.x + hi.x) < 0.04 and abs(lo.y + hi.y) < 0.04, "bbox must be centred on the grip axis"
    return ship(name, parts, GRIP)


def rbox(name, size, colour, pos=(0, 0, 0), bevel_w=0.15, segments=2):
    """Rounded box (flat shaded, `segments` bevel rows on every edge) at pos. colour: RGBA or colour(0, 0, centre)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel_w, segments=segments, affect="EDGES", profile=0.5)
    bmesh.ops.translate(bm, vec=Vector(pos), verts=bm.verts)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    _paint(bm, [(0, 0)] * len(bm.faces), colour, True)
    return obj_from_bm(name, bm, smooth=True)
