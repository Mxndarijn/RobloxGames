# Preview (not an asset): the goo-parade lane assembled round the hub from the SHIPPED FBXs:
# out/slime_fountain.fbx at the hub centre (silo-axis offset), 7 x parade_lane_arc45 + 1 x
# parade_lane_gate rotated k * 45 deg about the hub, parade_lane_countdown_ring in the gate's basin,
# plaza disc r 55, landing ring r 34..62, ring path r 74..82, slimes riding the lane at r 68, one
# shrinking in the gate basin, a 5-stud avatar block. PL_SCENE=gate crops a close window on the gate.
#   python3 iterate.py models/_parade_lane_scene.py --look roblox --ground 120,196,108 --no-export \
#       --no-ref --views 3,2 --res 512 --name pl_scene
#   PL_SCENE=gate python3 iterate.py models/_parade_lane_scene.py ... --views 3,2 --res 512 --name pl_scene_gate
import math, os
import bmesh, bpy
from mathutils import Matrix, Vector
from lib import PALETTE, box, cylinder, join, obj_from_bm, rgb, shade, vcol_material
from lib.color import srgb_to_linear
import models._parade_lane as pl

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = PALETTE
CLOSE = os.environ.get("PL_SCENE", "all") == "gate"
GATE_DEG = -90.0  # the gate at k = 0 (kit front); arcs at k = 1..7


def parts_bbox(script):
    """hub offset of a lane piece: run its model script without finish(), take the parts' bbox."""
    src = open(os.path.join(KIT, "models", script)).read().replace("finish(", "_noop(")
    g = {"__name__": "__main__", "_noop": lambda *a: None}
    exec(compile(src, script, "exec"), g)
    lo, hi = pl.bbox(g["parts"])
    for o in g["parts"]:
        bpy.data.objects.remove(o, do_unlink=True)
    return Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))


def import_fbx(name):
    bpy.ops.import_scene.fbx(filepath=os.path.join(KIT, "out", name + ".fbx"))
    o = bpy.context.selected_objects[0]
    ca = o.data.color_attributes
    mat = vcol_material("scene_" + name)
    mat.node_tree.nodes["Color Attribute"].layer_name = ca[0].name
    o.data.materials.clear()
    o.data.materials.append(mat)
    bpy.context.view_layer.update()
    return o


def place(o, offset, deg):
    """mesh centred on its bbox-bottom-centre -> hub frame: translate by offset, rotate about the hub."""
    o.matrix_world = Matrix.Rotation(math.radians(deg), 4, "Z") @ Matrix.Translation(offset) @ o.matrix_world
    bpy.context.view_layer.update()


# ------------------------------------------------------------------ the lane (shipped FBXs)
C_ARC = parts_bbox("parade_lane_arc45.py")
C_GATE = parts_bbox("parade_lane_gate.py")
gate = import_fbx("parade_lane_gate")
place(gate, C_GATE, GATE_DEG + 90)
ring = import_fbx("parade_lane_countdown_ring")
place(ring, Vector((0, -pl.R_C, 0.20)), GATE_DEG + 90)
lane = [gate, ring]
for k in range(1, 8):
    o = import_fbx("parade_lane_arc45")
    place(o, C_ARC, GATE_DEG + 90 + k * 45)
    lane.append(o)

# ------------------------------------------------------------------ hub
fountain = None
if not CLOSE:
    import models.slime_fountain as sf
    fparts, _ = sf.build()
    lo, hi = sf.bbox_xy(fparts)
    for o in fparts:
        bpy.data.objects.remove(o, do_unlink=True)
    fountain = import_fbx("slime_fountain")
    c = (lo + hi) / 2
    fountain.location = (c.x, c.y, 0.0)


def annulus(name, r0, r1, z, color, segs=96):
    bm = bmesh.new()
    rings = []
    for r in (r0, r1):
        for zz in (z - 0.2, z):
            rings.append([bm.verts.new((math.cos(k * math.tau / segs) * r, math.sin(k * math.tau / segs) * r, zz))
                          for k in range(segs)])
    ib, it, ob, ot = rings
    for k in range(segs):
        j = (k + 1) % segs
        bm.faces.new((it[k], it[j], ot[j], ot[k]))
        bm.faces.new((ob[k], ob[j], ib[j], ib[k]))
        bm.faces.new((ot[k], ot[j], ob[j], ob[k]))
        bm.faces.new((ib[k], ib[j], it[j], it[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, color)


hub = [cylinder("Plaza", 55, 0.12, (0, 0, 0), P["ranch_plaza"], segs=96),
       annulus("LandingRing", 34, 62, 0.16, P["ranch_path"]),
       annulus("RingPath", 74, 82, 0.16, shade(P["ranch_path"], 0.96))]

# ------------------------------------------------------------------ slimes (genome colours tint the grey body)
SLIME_RGB = [(255, 120, 170), (120, 200, 255), (255, 200, 70), (170, 110, 255), (120, 230, 140), (255, 140, 80),
             (90, 220, 210), (250, 110, 120)]
_src = import_fbx("slime_base")
_src.hide_render = True
_src.hide_set(True)
slimes = []


def slime(pos, yaw_deg, rgb255, scale=1.0):
    t = [srgb_to_linear(c / 255) for c in rgb255]
    o = _src.copy()
    o.data = _src.data.copy()
    bpy.context.scene.collection.objects.link(o)
    o.hide_render = False
    o.hide_set(False)
    for d in o.data.color_attributes[0].data:
        c = d.color
        d.color = (c[0] * t[0], c[1] * t[1], c[2] * t[2], c[3])
    o.rotation_euler = (0, 0, math.radians(yaw_deg + 180))  # shipped slime faces kit +Y
    o.scale = (scale,) * 3
    o.location = pos
    slimes.append(o)
    return o


def on_lane(deg, d=0.0):
    a = math.radians(deg)
    r = pl.R_C + d
    return (r * math.cos(a), r * math.sin(a), pl.GOO_C - 0.02), deg + 180  # facing the CCW travel direction


# riders travelling counter-clockwise (towards larger angles), spread round the ring
for n, deg in enumerate((-128, -60, -10, 35, 80, 140, 200)):
    p, a = on_lane(deg, 0.3 if n % 2 else -0.3)
    slime(p, a, SLIME_RGB[n])
# the next in line, just before the gate, and one shrinking in the basin inside the countdown ring
p, a = on_lane(GATE_DEG - 9.5)
slime(p, a, SLIME_RGB[7])
slime((0.0, -pl.R_C, 0.08), GATE_DEG + 180, SLIME_RGB[3], scale=0.45)

# grey 5-stud avatar block on the ring path, watching the gate
box("Avatar", (2.0, 1.0, 5.0), (6.5, -77.5, 2.5 + 0.16), rgb(150, 150, 150))

# ------------------------------------------------------------------ gate close-up: crop everything to a window
if CLOSE:
    keep_x, y0, y1 = 17.0, -85.0, -56.0
    for o in [x for x in bpy.context.scene.objects if x.type == "MESH" and x.visible_get()]:
        bpy.context.view_layer.update()
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.transform(bm, matrix=o.matrix_world, verts=bm.verts)
        for co, no in (((keep_x, 0, 0), (1, 0, 0)), ((-keep_x, 0, 0), (-1, 0, 0)), ((0, y0, 0), (0, -1, 0)),
                       ((0, y1, 0), (0, 1, 0))):
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no,
                                   clear_outer=True)
        if not bm.verts:
            bm.free()
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        bm.to_mesh(o.data)
        bm.free()
        o.matrix_world = Matrix.Identity(4)
