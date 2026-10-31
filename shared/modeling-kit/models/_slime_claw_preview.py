# Preview only (not an asset): exclusive_slime_claw with three real Exclusive pet mounts (out/*.fbx) on its display
# spots, the way the game would seat them. CLAW_POSE=grab shows the arm reaching for the middle one.
import json, os, runpy
import bpy
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "out")
MOUNTS = ["pet_mount_ufo", "pet_mount_sunset_cloud", "pet_mount_magic_carpet"]

runpy.run_path(os.path.join(HERE, "exclusive_slime_claw.py"), run_name="__main__")
with open(os.path.join(OUT, "exclusive_slime_claw_layout.json")) as f:
    displays = json.load(f)["displays"]

for name, (x, y, z) in zip(MOUNTS, displays):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(OUT, name + ".fbx"), axis_forward="-Z", axis_up="Y")
    for o in set(bpy.data.objects) - before:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
            continue
        o.parent = None
        bpy.context.view_layer.update()
        o.data.transform(o.matrix_world)
        o.matrix_world.identity()
        vs = [v.co for v in o.data.vertices]
        cx = (min(v.x for v in vs) + max(v.x for v in vs)) / 2
        cy = (min(v.y for v in vs) + max(v.y for v in vs)) / 2
        z0 = min(v.z for v in vs)
        span = max(max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs))
        k = 3.3 / span if span > 20 else 1.0
        for v in o.data.vertices:
            v.co.x, v.co.y, v.co.z = (v.co.x - cx) * k, (v.co.y - cy) * k, (v.co.z - z0) * k
        o.location = (x, y, z)
