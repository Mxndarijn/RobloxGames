"""Runs INSIDE Blender: aimed renders of the fountain silo for the split-seam hole check (Roblox look, back faces culled like
Roblox culls them, so an open or flipped face shows as the pale sky behind it).

  blender -b --factory-startup -P tools/fountain_silo_render.py -- --src pieces|whole --out PREFIX [--az 0,45,...]
        [--target x,y,z] [--dist 30] [--elev 10] [--res 800] [--samples 24] [--pieces silo,eave,...]

`pieces` imports out/fountain_split_<name>.fbx for every piece (all share the whole mesh's frame, so no offsets), `whole`
imports out/slime_fountain.fbx. The silo axis is (-6.463, 8.288) in kit axes (fitted from the plinth; see LESSONS.md)."""
import argparse, math, os, sys

import bpy
from mathutils import Vector

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_src = open(os.path.join(KIT, "kit", "bl_iterate.py")).read()
B = type(sys)("bl_iterate_funcs")  # the helpers above `def main()` (importing the file would run its own main)
B.__dict__["__file__"] = os.path.join(KIT, "kit", "bl_iterate.py")
exec(compile(_src[:_src.index("\ndef main():")], B.__file__, "exec"), B.__dict__)

AXIS = (-6.463, 8.288)


def args():
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--src", default="pieces", choices=["pieces", "whole"])
    p.add_argument("--out", required=True)
    p.add_argument("--az", default="0,45,90,135,180,225,270,315")
    p.add_argument("--target", default="")
    p.add_argument("--dist", type=float, default=0)
    p.add_argument("--elev", type=float, default=8)
    p.add_argument("--res", type=int, default=800)
    p.add_argument("--samples", type=int, default=24)
    p.add_argument("--fov", type=float, default=40)
    p.add_argument("--pieces", default="basin,dome,eave,silo,slide")
    p.add_argument("--fbx", default="", help="use this FBX dir instead of out/ for the pieces")
    return p.parse_args(argv)


def cull(m):
    """Roblox draws no back faces: mix a transparent BSDF in where the face is seen from behind."""
    nt = m.node_tree
    out = nt.nodes["Material Output"]
    src = out.inputs["Surface"].links[0].from_socket
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(geo.outputs["Backfacing"], mix.inputs["Fac"])
    nt.links.new(src, mix.inputs[1])
    nt.links.new(tr.outputs["BSDF"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])


def main():
    a = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    d = a.fbx or os.path.join(KIT, "out")
    paths = [os.path.join(d, "slime_fountain.fbx")] if a.src == "whole" else [
        os.path.join(d, f"fountain_split_{n}.fbx") for n in a.pieces.split(",")]
    for p in paths:
        bpy.ops.import_scene.fbx(filepath=p)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    B.apply_roblox_materials(objs)
    for o in objs:
        for m in o.data.materials:
            cull(m)
    sc = bpy.context.scene
    ns = type("A", (), dict(res=a.res, quick=False, look="roblox", engine="cycles", samples=a.samples))
    B.setup_render(ns)
    col = sc.collection
    B.sun(col, "sun", B.RBX["sun_strength"], B.RBX["sun_angle"]).rotation_euler = Vector(
        B.RBX["sun_dir"]).normalized().to_track_quat("-Z", "Y").to_euler()
    ground = bpy.data.objects.new("ground", bpy.data.meshes.new("ground"))
    me = ground.data
    me.from_pydata([(-200, -200, 0), (200, -200, 0), (200, 200, 0), (-200, 200, 0)], [], [(0, 1, 2, 3)])
    gm = bpy.data.materials.new("g")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = B.RBX["ground"]
    me.materials.append(gm)
    col.objects.link(ground)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.angle = math.radians(a.fov)
    col.objects.link(cam)
    sc.camera = cam
    tgt = Vector(tuple(float(x) for x in a.target.split(","))) if a.target else Vector((AXIS[0], AXIS[1], 18))
    dist = a.dist or 70
    for az in [float(x) for x in a.az.split(",")]:
        # az 0 = the model's front (-Y side), turning counter-clockwise seen from above
        ang = math.radians(az)
        dirv = Vector((math.sin(ang) * math.cos(math.radians(a.elev)), -math.cos(ang) * math.cos(math.radians(a.elev)),
                       math.sin(math.radians(a.elev))))
        cam.location = tgt + dirv * dist
        cam.rotation_euler = (-dirv).to_track_quat("-Z", "Y").to_euler()
        cam.data.clip_start, cam.data.clip_end = 0.1, 600
        sc.render.filepath = f"{a.out}_{int(az):03d}.png"
        bpy.ops.render.render(write_still=True)
        print("wrote", sc.render.filepath)


main()
