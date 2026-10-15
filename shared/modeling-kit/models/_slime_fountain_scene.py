# Preview (not an asset): the shipped slime_fountain FBX in its hub setting, with slimes riding the
# slide into the plaza. Loads out/slime_fountain.fbx (+ out/slime_base.fbx if present).
#   python3 iterate.py models/_slime_fountain_scene.py --look roblox --ground 120,196,108 --no-export \
#       --no-ref --views 3,0,2 --res 512 --sheet sheets/fountain/slime_fountain_scene_robloxlook.png
# Hub sizes (FOUNTAIN_SIZES.md): plaza disc r 55 (ranch_plaza), wild landing ring r 34..62
# (ranch_path), silo axis at the hub centre. finish() centres the mesh on its bbox, so the FBX is
# moved back by the silo-axis offset, measured from the model's own build().
import math, os
import bmesh, bpy
from mathutils import Vector
from lib import PALETTE, box, cylinder, mix, obj_from_bm, rgb, shade, vcol_material
from lib.color import srgb_to_linear
from models._slime import radius as slime_radius, TIP as SLIME_TIP
import models.slime_fountain as sf

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = PALETTE

# silo-axis offset: build the model's parts once, take their bbox, throw them away
parts, PTS = sf.build()
lo, hi = sf.bbox_xy(parts)
for o in parts:
    bpy.data.objects.remove(o, do_unlink=True)
C = (lo + hi) / 2
FR = sf.frames(PTS)


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


fountain = import_fbx("slime_fountain")
fountain.location = (C.x, C.y, 0.0)


def annulus(name, r0, r1, z, color, segs=72):
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


cylinder("Plaza", 55, 0.12, (0, 0, 0), P["ranch_plaza"], segs=72)
annulus("LandingRing", 34, 62, 0.16, P["ranch_path"])

# slimes: game genome colours (MeshPart.Color tints the light-grey body, assumed multiply)
SLIME_RGB = [(255, 120, 170), (120, 200, 255), (255, 200, 70), (170, 110, 255), (120, 230, 140), (255, 140, 80),
             (90, 220, 210), (250, 110, 120)]
have_slime = os.path.exists(os.path.join(KIT, "out", "slime_base.fbx"))
_src = import_fbx("slime_base") if have_slime else None
if _src:
    _src.hide_render = True
    _src.hide_set(True)


def slime(name, pos, yaw_deg, rgb255, scale=1.0, pitch=0.0):
    """slime at pos (bottom centre), face pointing yaw_deg (0 = -Y, kit front)."""
    t = [srgb_to_linear(c / 255) for c in rgb255]
    if _src:
        o = _src.copy()
        o.data = _src.data.copy()
        bpy.context.scene.collection.objects.link(o)
        o.hide_render = False
        o.hide_set(False)
        for d in o.data.color_attributes[0].data:
            c = d.color
            d.color = (c[0] * t[0], c[1] * t[1], c[2] * t[2], c[3])
        # the shipped slime faces Roblox -Z = kit +Y; turn it so the face looks along yaw
        o.rotation_euler = (math.radians(pitch), 0, math.radians(yaw_deg + 180))
        o.scale = (scale,) * 3
        o.location = pos
        return o
    # fallback: gumdrop blob
    bm = bmesh.new()
    zs = [0.0, 0.35, 1.0, 1.7, 2.35, 2.8]
    rings = [[bm.verts.new((math.cos(k * math.tau / 12) * slime_radius(z), math.sin(k * math.tau / 12) * slime_radius(z), z))
              for k in range(12)] for z in zs]
    top, bot = bm.verts.new((0, 0, SLIME_TIP)), bm.verts.new((0, 0, 0))
    for a, b in zip(rings, rings[1:]):
        for k in range(12):
            bm.faces.new((a[k], a[(k + 1) % 12], b[(k + 1) % 12], b[k]))
    for k in range(12):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % 12], top))
        bm.faces.new((rings[0][(k + 1) % 12], rings[0][k], bot))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, rgb(*rgb255))
    o.rotation_euler = (math.radians(pitch), 0, math.radians(yaw_deg))
    o.scale = (scale,) * 3
    o.location = pos
    return o


# 6 slimes riding the slide (on the goo floor, facing downhill), spread along the run
for n, t in enumerate((0.12, 0.3, 0.46, 0.62, 0.78, 0.93)):
    i = min(int(t * (len(PTS) - 1)), len(PTS) - 2)
    p, lat, up = FR[i]
    d = (PTS[i + 1] - PTS[i - 1]).normalized()
    yaw = math.degrees(math.atan2(d.x, -d.y))
    pitch = -math.degrees(math.asin(max(-1, min(1, d.z))))
    slime(f"Rider{n}", p + lat * (0.6 if n % 2 else -0.6) + up * 0.05, yaw, SLIME_RGB[n], scale=1.0, pitch=0)
# 2 slimes already landed, hopping across the landing ring
end = PTS[-1]
slime("Landed0", (end.x - 6, end.y - 6, 0.16), 200, SLIME_RGB[6], 1.0)
slime("Landed1", (-30, -38, 0.16), 140, SLIME_RGB[7], 1.0)

# grey 5-stud avatar block watching the landing
box("Avatar", (2.0, 1.0, 5.0), (end.x + 9, end.y - 4, 2.5 + 0.16), rgb(150, 150, 150))
