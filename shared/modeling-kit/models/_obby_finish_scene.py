# Preview only (not shipped): an obby finish option in place on the game's 12 x 24 finish slab, with the course
# leading up to it and stand-in runners, rendered in the kit's approximate Roblox look from where a runner sees it.
# Runs inside Blender (the host side is models/_obby_finish_sheet.py, which starts it and builds the sheet):
#   blender -b --factory-startup -P models/_obby_finish_scene.py -- --model models/obby_finish_a.py --out DIR
import argparse, ast, math, os, runpy, sys

import bmesh, bpy
from mathutils import Vector

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, KIT)
os.chdir(KIT)

import lib
import lib.mesh

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("--model", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--res", default="640x360")
ap.add_argument("--samples", type=int, default=12)
ap.add_argument("--views", default="")
a = ap.parse_args(argv)

# The kit's Roblox look values, read from kit/bl_iterate.py (one source of truth).
src = open(os.path.join(KIT, "kit", "bl_iterate.py"), encoding="utf-8").read()
tree = ast.parse(src)
RBX = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign)
           and getattr(n.targets[0], "id", "") == "RBX")

bpy.ops.wm.read_factory_settings(use_empty=True)


# Keep the set in slab coordinates: finish() without the re-centre.
def _finish(name, parts, merge=0.0):
    o = lib.mesh.join(name, parts)
    lib.mesh.apply_transforms(o)
    lib.mesh.cleanup(o, merge)
    return o


lib.finish = lib.mesh.finish = _finish
runpy.run_path(a.model, run_name="__main__")
sets = [o for o in bpy.context.scene.objects if o.type == "MESH"]

from lib import rgb, box, mix
from models._obby_finish_parts import SLAB, LANE, SLAB_Y

env = []
SLAB_T = 1.0
env.append(box("_slab", (2 * LANE, 2 * SLAB_Y, SLAB_T), (0, 0, -SLAB_T / 2), SLAB))
# the course leading up: a jelly link, then platforms of the three jelly tones, a few steps up and down
JELLY = [rgb(185, 140, 255), rgb(120, 220, 120), rgb(110, 170, 255)]
env.append(box("_link", (8, 4, SLAB_T), (0, -SLAB_Y - 2, -SLAB_T / 2), JELLY[0]))
y = -SLAB_Y - 4
k = 0
for (w, d, dz, x, gap) in ((12, 8, 0, 0, 3), (6, 6, 1.5, -5, 4), (6, 6, 0, 4, 4), (24, 10, -1, 0, 3),
                           (5, 5, 1, -7, 5), (5, 5, 2, 0, 4), (5, 5, 1, 7, 4), (14, 8, 0, 0, 3),
                           (8, 8, 0, 0, 4), (24, 12, 0, 0, 3)):
    y -= gap
    env.append(box(f"_plat{k}", (w, d, SLAB_T), (x, y - d / 2, dz - SLAB_T / 2), JELLY[k % 3]))
    y -= d
    k += 1


def avatar(name, pos, yaw=0.0, col=(0.2, 0.62, 0.95, 1)):
    """Blocky R15-ish stand-in, 5 studs tall: legs, torso, head, arms."""
    bm = bmesh.new()
    for sx, sy, sz, x, z in ((0.9, 0.9, 2.0, -0.5, 1.0), (0.9, 0.9, 2.0, 0.5, 1.0), (2.0, 1.0, 1.9, 0, 2.95),
                             (0.9, 0.9, 1.9, -1.45, 2.95), (0.9, 0.9, 1.9, 1.45, 2.95), (1.2, 1.2, 1.15, 0, 4.48)):
        r = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=r["verts"])
        bmesh.ops.translate(bm, vec=(x, 0, z), verts=r["verts"])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = pos
    o.rotation_euler = (0, 0, math.radians(yaw))
    o["flat"] = col
    return o


env.append(avatar("_runA", (2.0, -2.0, 0), col=(0.26, 0.6, 0.95, 1)))     # on the slab, under/after the gate
env.append(avatar("_runB", (-1.0, -24.0, 0), col=(0.95, 0.55, 0.2, 1)))   # coming up the course
env.append(avatar("_runC", (6.0, 3.5, 0), yaw=200, col=(0.5, 0.85, 0.4, 1)))

# ---- render setup: the kit's Roblox look (sun + occluded sky + flat ambient, SmoothPlastic-ish)
sc = bpy.context.scene
w, h = (int(v) for v in a.res.split("x"))
r = sc.render
r.resolution_x, r.resolution_y, r.resolution_percentage = w, h, 100
r.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = a.samples
sc.cycles.use_adaptive_sampling = False
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 3
sc.cycles.diffuse_bounces = 0
sc.cycles.glossy_bounces = 1
sc.cycles.transmission_bounces = 0
r.use_persistent_data = True
r.threads_mode = "FIXED"
r.threads = 6  # the box is shared: don't take every core
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.view_settings.exposure = RBX["exposure"]
wd = bpy.data.worlds.new("_world")
wd.use_nodes = True
nt = wd.node_tree
out, bg = nt.nodes["World Output"], nt.nodes["Background"]
bg.inputs["Color"].default_value = RBX["outdoor"] + (1,)
sky = nt.nodes.new("ShaderNodeBackground")
sky.inputs["Color"].default_value = RBX["sky_bg"] + (1,)
lp = nt.nodes.new("ShaderNodeLightPath")
mx = nt.nodes.new("ShaderNodeMixShader")
nt.links.new(lp.outputs["Is Camera Ray"], mx.inputs["Fac"])
nt.links.new(bg.outputs["Background"], mx.inputs[1])
nt.links.new(sky.outputs["Background"], mx.inputs[2])
nt.links.new(mx.outputs["Shader"], out.inputs["Surface"])
sc.world = wd


def material(name, attr=None, color=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    t = m.node_tree
    b = t.nodes["Principled BSDF"]
    o = t.nodes["Material Output"]
    if attr:
        c = t.nodes.new("ShaderNodeVertexColor")
        c.layer_name = attr
        col = c.outputs["Color"]
    else:
        n = t.nodes.new("ShaderNodeRGB")
        n.outputs[0].default_value = color
        col = n.outputs[0]
    t.links.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = RBX["roughness"]
    b.inputs["Specular IOR Level"].default_value = RBX["specular"]
    mul = t.nodes.new("ShaderNodeMix")
    mul.data_type, mul.blend_type = "RGBA", "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    t.links.new(col, mul.inputs["A"])
    mul.inputs["B"].default_value = RBX["ambient"] + (1,)
    em = t.nodes.new("ShaderNodeEmission")
    t.links.new(mul.outputs["Result"], em.inputs["Color"])
    ad = t.nodes.new("ShaderNodeAddShader")
    t.links.new(b.outputs["BSDF"], ad.inputs[0])
    t.links.new(em.outputs["Emission"], ad.inputs[1])
    t.links.new(ad.outputs["Shader"], o.inputs["Surface"])
    return m


for o in sets + env:
    me = o.data
    o.data.materials.clear()
    if "flat" in o:
        me.materials.append(material("_m" + o.name, color=tuple(o["flat"])))
    else:
        ca = me.color_attributes.active_color or (me.color_attributes[0] if len(me.color_attributes) else None)
        me.materials.append(material("_m" + o.name, attr=ca.name if ca else None,
                                     color=(0.64, 0.64, 0.64, 1)))

sl = bpy.data.lights.new("_sun", "SUN")
sl.energy = RBX["sun_strength"]
sl.angle = math.radians(RBX["sun_angle"])
sl.color = RBX["sun_color"]
so = bpy.data.objects.new("_sun", sl)
sc.collection.objects.link(so)
so.rotation_euler = (-Vector(RBX["sun_dir"])).normalized().to_track_quat("-Z", "Y").to_euler()

cam = bpy.data.objects.new("_cam", bpy.data.cameras.new("_cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.sensor_fit = "VERTICAL"
cam.data.angle = math.radians(70)  # Roblox's default vertical FieldOfView
cam.data.clip_end = 1000

# (label, camera position, look-at): runner views use Roblox's FOV from where a runner's camera would be
VIEWS = [
    ("approach 95 studs", (0, -95, 13), (0, 0, 7)),
    ("approach 60 studs", (-3, -60, 11), (0, 0, 6)),
    ("runner cam, 20 studs out", (-2, -26, 8.5), (0, 0, 6)),
    ("close 3/4", (-27, -27, 10), (0, 0, 7)),
    ("from behind / side", (26, 20, 12), (0, -1, 6)),
    ("top", (0, -30, 48), (0, -2, 0)),
]
os.makedirs(a.out, exist_ok=True)
stem = os.path.splitext(os.path.basename(a.model))[0]
pick = [int(v) for v in a.views.split(",")] if a.views else range(len(VIEWS))
for i in pick:
    label, p, t = VIEWS[i]
    cam.location = p
    cam.rotation_euler = (Vector(t) - Vector(p)).normalized().to_track_quat("-Z", "Y").to_euler()
    if label == "top":
        cam.data.angle = math.radians(50)
    r.filepath = os.path.join(a.out, f"{stem}_scene{i}.png")
    bpy.ops.render.render(write_still=True)
    cam.data.angle = math.radians(70)
print("SCENE done", [VIEWS[i][0] for i in pick])
