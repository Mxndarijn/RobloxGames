"""Inside Blender: build a pool slime with its skinned rig (SLIME_RIG=1) and render an animation
preview of the motions the game could drive with Bone.Transform (CFrame only, no scale).

blender -b --factory-startup -P kit/bl_slime_anim.py -- --model models/pool/slime_x.py --out DIR
        [--res 384] [--samples 32] [--frames 96] [--fps 24] [--clip all|idle|hop|blink]
Writes DIR/frame_####.png.
"""
import argparse, math, os, runpy, sys
import bpy
from mathutils import Quaternion, Vector

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, KIT)


def args():
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--res", type=int, default=384)
    p.add_argument("--samples", type=int, default=32)
    p.add_argument("--frames", type=int, default=96)
    p.add_argument("--fps", type=int, default=24)
    p.add_argument("--view", default="hero", choices=["hero", "front", "side"])
    return p.parse_args(argv)


def smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def pose_at(t, T, H, R, share=1.0):
    """the motion script, t in seconds over a T-second loop. Returns per-bone (loc, axis, angle).
    Timeline: idle breathing all the time, blink at 0.7 s and 2.9 s, a hop at 1.4-2.3 s."""
    out = {}
    breathe = math.sin(t / T * math.tau * 2)  # 2 breaths per loop
    squash = 0.05 * H * breathe
    lift = 0.0
    tilt = 0.06 * math.sin(t / T * math.tau * 3 + 0.5)
    # hop: anticipation squash -> launch stretch -> air -> land squash -> settle
    h0, h1 = 1.4, 2.3
    if h0 <= t <= h1:
        u = (t - h0) / (h1 - h0)
        if u < 0.2:
            squash += 0.2 * H * smooth(u / 0.2)
        elif u < 0.75:
            k = (u - 0.2) / 0.55
            lift = 1.3 * math.sin(math.pi * k)
            squash += 0.2 * H * (1 - smooth(k / 0.15)) - 0.12 * H * math.sin(math.pi * min(1, k / 0.6))
        else:
            k = (u - 0.75) / 0.25
            squash += 0.18 * H * math.sin(math.pi * k) * (1 - k * 0.3)
        tilt += 0.1 * math.sin(u * math.tau)
    out["Root"] = (Vector((0, 0, lift)), Vector((1, 0, 0)), tilt * 0.4)
    out["Top"] = (Vector((0, 0, -squash)), Vector((1, 0, 0)), tilt)
    bulge = squash * 0.55
    for n, d in (("SideL", (1, 0)), ("SideR", (-1, 0)), ("SideF", (0, -1)), ("SideB", (0, 1))):
        out[n] = (Vector((d[0] * bulge, d[1] * bulge, -squash * 0.3)), Vector((0, 0, 1)), 0.0)
    # blink: eyes sink into the body, the hidden closed lids come out (0.13 s)
    blink = 0.0
    for b in (0.7, 2.9):
        if b <= t <= b + 0.13:
            blink = math.sin(math.pi * (t - b) / 0.13) ** 0.3
    # during the hop: excited closed ^^ eyes for the air time
    if h0 + 0.3 <= t <= h0 + 0.62:
        blink = 1.0
    out["Eyes"] = (Vector((0, 0.13 * blink / share, 0)), Vector((0, 0, 1)), 0.0)
    out["Lids"] = (Vector((0, -0.165 * blink / share, 0)), Vector((0, 0, 1)), 0.0)
    out["_t"] = (t, h0, h1)
    return out


def secondary(name, piv, cen, t, T, hop_u):
    """accessory motion presets by bone name (armature-space axis, angle)."""
    piv, cen = Vector(piv), Vector(cen)
    outward = Vector((piv.x, piv.y, 0))
    outward = outward.normalized() if outward.length > 1e-4 else Vector((0, 1, 0))
    tang = Vector((0, 0, 1)).cross(outward)
    ph = math.atan2(piv.y, piv.x)
    air = 1.0 if hop_u is not None and 0.2 < hop_u < 0.75 else 0.0
    if name.startswith("Wing"):
        return tang, math.radians(28 + 10 * air) * math.sin(t * math.tau * 4) * (1 if piv.x > 0 else -1)
    if name.startswith("Ear"):
        return tang, math.radians(10 + 14 * air) * math.sin(t * math.tau * 1.3 - 0.8) * (1 if piv.x > 0 else -1)
    if name.startswith("Ant"):
        return tang + Vector((0, 0.6, 0)), math.radians(14) * math.sin(t * math.tau * 2.0 + ph)
    if name.startswith("Tail"):
        return Vector((0, 0, 1)), math.radians(22) * math.sin(t * math.tau * 2.0)
    if name.startswith(("Fin", "Pec")):
        return tang, math.radians(12) * math.sin(t * math.tau * 1.6 + ph)
    if name.startswith(("Tent", "Ribbon", "Band", "Flame")):
        return tang, math.radians(16) * math.sin(t * math.tau * 1.5 + ph * 2)
    return Vector((0, 0, 1)), 0.0


def scene_setup(a, H):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    c = sc.cycles
    c.samples = a.samples
    c.use_denoising = True
    c.denoiser = "OPENIMAGEDENOISE"
    c.max_bounces = 4
    c.device = "CPU"
    if os.environ.get("KIT_GPU"):
        cp = bpy.context.preferences.addons["cycles"].preferences
        try:
            cp.compute_device_type = os.environ["KIT_GPU"]
            cp.get_devices()
            for dev in cp.devices:
                dev.use = dev.type != "CPU"
            c.device = "GPU"
        except TypeError:
            pass
    sc.render.resolution_x = sc.render.resolution_y = a.res
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.68, 0.8, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sc.world = w
    bpy.ops.mesh.primitive_plane_add(size=60)
    g = bpy.context.active_object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.36, 0.38, 0.42, 1)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    g.data.materials.append(gm)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    sc.collection.objects.link(sun)
    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
    key.data.energy = 120 * H
    key.data.size = 4
    key.location = (-4, -6, 5)
    key.rotation_euler = (math.radians(55), 0, math.radians(-35))
    sc.collection.objects.link(key)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 55
    sc.collection.objects.link(cam)
    sc.camera = cam
    d = {"hero": Vector((-0.5, -1.0, 0.34)), "front": Vector((0, -1, 0.15)), "side": Vector((1, 0, 0.12))}[a.view].normalized()
    target = Vector((0, 0, H * 0.62))
    cam.location = target + d * (H * 2.7 + 2.4)
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()


def main():
    a = args()
    os.environ["SLIME_PREVIEW"] = "1"
    os.environ["SLIME_RIG"] = "1"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    runpy.run_path(os.path.join(KIT, a.model) if not os.path.isabs(a.model) else a.model, run_name="__main__")
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.parent and o.parent.type == "ARMATURE"]
    o = meshes[0]
    ao = o.parent
    from models._slime import _smooth  # noqa: F401  (ensures models package import works)
    from lib.color import vcol_material  # noqa
    # material that shows vertex colours with a soft gloss
    m = bpy.data.materials.new("slime")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.35
    bsdf.inputs["Coat Weight"].default_value = 0.25
    o.data.materials.clear()
    o.data.materials.append(m)
    zs = [v.co.z for v in o.data.vertices]
    H = max(zs)
    R = max(math.hypot(v.co.x, v.co.y) for v in o.data.vertices)
    scene_setup(a, H)
    sc = bpy.context.scene
    sc.render.fps = a.fps
    T = a.frames / a.fps
    bones = ao.pose.bones
    rest = {b.name: b.bone.matrix_local.copy() for b in bones}
    os.makedirs(a.out, exist_ok=True)
    for fr in range(a.frames):
        t = fr / a.fps
        P = pose_at(t, T, H, R, ao.get("eye_share", 1.0))
        _, h0, h1 = P.pop("_t")
        hop_u = (t - h0) / (h1 - h0) if h0 <= t <= h1 else None
        for pb in bones:
            pb.rotation_mode = "QUATERNION"
            M = rest[pb.name].to_3x3()
            Minv = M.inverted()
            if pb.name in P:
                loc, axis, ang = P[pb.name]
            else:
                b = pb.bone
                axis, ang = secondary(pb.name, b.head_local, b.tail_local, t, T, hop_u)
                loc = Vector()
            pb.location = Minv @ loc
            pb.rotation_quaternion = Quaternion((Minv @ axis).normalized(), ang) if ang else Quaternion()
        bpy.context.view_layer.update()
        sc.render.filepath = os.path.join(a.out, f"frame_{fr:04d}.png")
        bpy.ops.render.render(write_still=True)
    print("ANIM_DONE", a.frames)


main()
