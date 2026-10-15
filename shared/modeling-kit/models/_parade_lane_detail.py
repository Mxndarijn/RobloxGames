# Preview (not an asset): close-up of the parade lane, for judging what the full-segment sheet
# shows too small. Builds the pieces in hub space (no finish() re-centring), tiles a second copy
# rotated +45 deg about the hub, crops a window and drops a 3-stud slime on the goo for scale.
#   PL_PIECE=arc|gate  PL_FOCUS=<deg about the hub, -67.5 = arc/arc joint>  PL_WIN=<half window studs>
#   python3 iterate.py models/_parade_lane_detail.py --look roblox --ground 120,196,108 --no-export ...
import math, os, runpy
import bmesh, bpy
from mathutils import Matrix, Vector
from lib import *
import models._parade_lane as pl

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
piece = os.environ.get("PL_PIECE", "arc")
focus = math.radians(float(os.environ.get("PL_FOCUS", "-67.5")))
win = float(os.environ.get("PL_WIN", "9"))


def build(script):
    """run a model script but stop before finish(): collect its parts from the scene."""
    src = open(os.path.join(KIT, "models", script)).read()
    src = src.replace("finish(", "_noop_finish(")
    g = {"__name__": "__main__", "_noop_finish": lambda name, parts: None}
    exec(compile(src, script, "exec"), g)
    return join(script[:-3], [o for o in g["parts"]])


objs = [build("parade_lane_arc45.py")]
if piece == "gate":
    objs.append(build("parade_lane_gate.py"))
    objs[-1].matrix_world = Matrix.Rotation(math.radians(45), 4, "Z") @ objs[-1].matrix_world
    ring = build("parade_lane_countdown_ring.py")  # built at the origin: move to the basin centre
    ring.matrix_world = Matrix.Rotation(math.radians(45), 4, "Z") @ Matrix.Translation((0, -pl.R_C, 0.20))
    objs.append(ring)
else:
    o2 = objs[0].copy()
    o2.data = objs[0].data.copy()
    bpy.context.scene.collection.objects.link(o2)
    o2.matrix_world = Matrix.Rotation(math.radians(45), 4, "Z")
    objs.append(o2)

# crop: keep a square window round the focus point on the centreline
fc = Vector((pl.R_C * math.cos(focus), pl.R_C * math.sin(focus), 0))
tang = Vector((-math.sin(focus), math.cos(focus), 0))
rad = Vector((math.cos(focus), math.sin(focus), 0))
for o in objs:
    bpy.context.view_layer.update()
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.transform(bm, matrix=o.matrix_world, verts=bm.verts)
    for n, w in ((tang, win), (-tang, win), (rad, 6.0), (-rad, 6.0)):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=fc + n * w,
                               plane_no=n, clear_outer=True)
    bmesh.ops.translate(bm, vec=-fc, verts=bm.verts)
    # turn so the lane runs along X and the hub is at +Y (camera front = outside of the ring)
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(-focus - math.pi / 2, 3, "Z"), verts=bm.verts)
    bm.to_mesh(o.data)
    bm.free()
    o.matrix_world = Matrix.Identity(4)

# a 3-stud slime riding the goo (shipped base mesh, tinted pink) for scale
sp = os.path.join(KIT, "out", "slime_base.fbx")
if os.path.exists(sp) and os.environ.get("PL_SLIME", "1") == "1":
    bpy.ops.import_scene.fbx(filepath=sp)
    s = bpy.context.selected_objects[0]
    ca = s.data.color_attributes
    for d in ca[0].data:
        c = d.color
        d.color = (c[0] * 1.0, c[1] * 0.19, c[2] * 0.42, c[3])
    mat = vcol_material("slime_prev")
    mat.node_tree.nodes["Color Attribute"].layer_name = ca[0].name
    s.data.materials.clear()
    s.data.materials.append(mat)
    sc = float(os.environ.get("PL_SLIME_S", "1"))
    s.matrix_world = Matrix.Translation((float(os.environ.get("PL_SLIME_X", "-4")), 0, float(os.environ.get("PL_SLIME_Z", pl.GOO_C)))) @ \
        Matrix.Scale(sc, 4) @ \
        Matrix.Rotation(math.radians(90), 4, "Z") @ s.matrix_world
