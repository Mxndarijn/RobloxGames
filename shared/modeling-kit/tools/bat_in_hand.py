"""Render the ranch_bat held in a blocky R15 right hand, at the Tool.Grip point (a stand-in, not a Studio render).

    blender -b --factory-startup --python tools/bat_in_hand.py -- --out /path/bat_in_hand.png [--res 900] [--samples 48]

Roblox maths (Tool.Grip): HandleCF = RightHand * RightGripAttachment * Grip:Inverse(), with the R15
RightGripAttachment = CFrame.new(0, -0.1, 0) * Angles(-90 deg, 0, 0) (hand-local Y runs up the forearm).
So the Handle's +Y (the bat's long axis, pommel -> tip) is the hand's -Z; with the arm raised forward in
the Tool pose that is straight up. Grip = CFrame.new(0, -1.345, 0) puts the red wrap centre (1.2 above the
pommel; mesh centre = bbox centre, 2.545 up) in the palm. Blender: Z up, the character faces -Y.
"""
import math, os, sys
import bpy
from mathutils import Vector

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, KIT)
sys.path.insert(0, os.path.join(KIT, "tools", "icons"))
from lib import box, bevel, rgb, gradient  # noqa: E402
import helpers as H  # noqa: E402

GRIP_Y = 1.2  # grip point above the pommel bottom (studs)
SKIN, SHIRT, PANTS, SHOE = rgb(245, 205, 48), rgb(13, 105, 172), rgb(75, 151, 75), rgb(88, 88, 92)


def arg(name, default):
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return a[a.index(name) + 1] if name in a else default


def part(name, size, pos, color, bev=0.08):
    o = box(name, size, pos, color)
    bevel(o, bev)
    return o


def main():
    out, res, samples = arg("--out", "bat_in_hand.png"), int(arg("--res", "900")), int(arg("--samples", "48"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    # blocky R15 body (sizes ~ R15 default), facing -Y; the right arm is drawn at +X
    objs = []
    for s in (-1, 1):
        objs.append(part(f"Leg{s}", (0.95, 0.95, 2.0), (s * 0.5, 0, 1.0), PANTS))
        objs.append(part(f"Shoe{s}", (0.98, 1.1, 0.35), (s * 0.5, -0.08, 0.18), SHOE, 0.06))
    objs.append(part("Torso", (2.0, 1.0, 2.0), (0, 0, 3.0), SHIRT, 0.12))
    objs.append(part("Head", (1.2, 1.2, 1.2), (0, 0, 4.6), SKIN, 0.2))
    sh = Vector((1.5, 0, 3.7))  # right shoulder
    # arm raised straight forward (-Y): upper arm 1.17, lower arm 1.05, hand 0.3 long (R15 proportions)
    objs.append(part("UpperArm", (1.0, 1.17, 1.0), sh + Vector((0, -0.585, 0)), SKIN, 0.1))
    objs.append(part("LowerArm", (1.0, 1.05, 1.0), sh + Vector((0, -1.17 - 0.525, 0)), SKIN, 0.1))
    hand_c = sh + Vector((0, -1.17 - 1.05 - 0.15, 0))
    objs.append(part("Hand", (1.0, 0.3, 1.0), hand_c, rgb(236, 190, 40), 0.06))
    # RightGripAttachment: 0.1 down the hand (toward the fingers = -Y here); the bat's grip point goes there
    att = hand_c + Vector((0, -0.1, 0))
    # fingers wrapped round the bat: a short curled block in front of the palm
    objs.append(part("Fingers", (1.04, 0.34, 0.5), att + Vector((0, -0.05, 0.0)), rgb(250, 214, 70), 0.1))
    bat = H.run_model("ranch_bat", (att.x, att.y, att.z - GRIP_Y), (0, 0, 0), 1.0)
    objs.append(bat)
    objs.append(box("Floor", (30, 30, 0.2), (0, 0, -0.1), rgb(120, 196, 108)))

    for o in H.meshes_of(objs):
        if "Col" not in o.data.color_attributes:
            H.paint(o, H.C["grey"])
        o.data.color_attributes.active_color = o.data.color_attributes["Col"]
        o.data.materials.clear()
        o.data.materials.append(H.vcol_material("vc"))

    focus = Vector((0.6, -1.6, 4.1))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 55
    sc.collection.objects.link(cam)
    cam.location = focus + Vector((13.0, -9.0, 1.2))
    cam.rotation_euler = (focus - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    for name, e, d, col in (("key", 3.2, (-0.5, -0.6, 0.8), (1, 0.96, 0.9)), ("fill", 0.8, (0.8, -0.2, 0.3), (0.85, 0.92, 1))):
        l = bpy.data.lights.new(name, "SUN")
        l.energy, l.color, l.angle = e, col, math.radians(20)
        lo = bpy.data.objects.new(name, l)
        sc.collection.objects.link(lo)
        lo.rotation_euler = (-Vector(d)).to_track_quat("-Z", "Y").to_euler()
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.78, 0.86, 0.97, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sc.world = w
    sc.render.engine = "CYCLES"
    sc.cycles.device, sc.cycles.samples, sc.cycles.use_denoising = "CPU", samples, True
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.exposure = 0.1
    sc.render.filepath = out
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    print("wrote", out)


main()
