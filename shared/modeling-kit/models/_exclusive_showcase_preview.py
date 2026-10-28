# Preview only (not an asset): ranch_exclusive_shop with real Exclusive pet mounts (out/*.fbx) on its display spots,
# the way the game would place them. PREVIEW_SIBLINGS=1 also puts the Item Shop and Upgrade Shop either side.
import math, os, runpy
import bpy
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "out")
MOUNTS = ["pet_mount_magic_carpet", "pet_mount_ice_cloud", "pet_mount_crescent_moon", "pet_mount_star_cushion",
          "pet_mount_royal_cushion", "pet_mount_sunset_cloud"]

g = runpy.run_path(os.path.join(HERE, "ranch_exclusive_shop.py"), run_name="__main__")
displays = g["DISPLAYS"]

for name, (x, y, z, yaw) in zip(MOUNTS, displays):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(OUT, name + ".fbx"), axis_forward="-Z", axis_up="Y")
    new = [o for o in set(bpy.data.objects) - before if o.type == "MESH"]
    for o in set(bpy.data.objects) - before:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    for o in new:
        o.parent = None
        bpy.context.view_layer.update()
        o.data.transform(o.matrix_world)
        o.matrix_world.identity()
        vs = [v.co for v in o.data.vertices]
        cx = (min(v.x for v in vs) + max(v.x for v in vs)) / 2
        cy = (min(v.y for v in vs) + max(v.y for v in vs)) / 2
        z0 = min(v.z for v in vs)
        span = max(max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs))
        k = 3.3 / span if span > 20 else 1.0          # FBX unit scale guard (cm import): back to ~3.3 studs
        for v in o.data.vertices:
            v.co.x, v.co.y, v.co.z = (v.co.x - cx) * k, (v.co.y - cy) * k, (v.co.z - z0) * k
        o.rotation_euler = (0, 0, math.radians(yaw))
        o.location = (x, y, z)
        for m in o.data.materials:
            pass

if os.environ.get("PREVIEW_SIBLINGS"):
    for fname, dx in (("ranch_item_shop.py", -21.0), ("ranch_upgrade_cabinet.py", 21.0)):
        before = set(bpy.data.objects)
        runpy.run_path(os.path.join(HERE, fname), run_name="__main__")
        for o in set(bpy.data.objects) - before:
            if o.type == "MESH":
                o.location.x += dx
