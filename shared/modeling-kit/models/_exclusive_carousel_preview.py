# Preview only (not an asset): ranch_exclusive_carousel with real Exclusive pet mounts riding its poles, the way the
# game would place them (each rider faces along the turn). PREVIEW_SIBLINGS=1 adds the Item Shop and Upgrade Shop.
import math, os, runpy
import bpy
from mathutils import Matrix
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "out")
MOUNTS = ["pet_mount_royal_cushion", "pet_mount_ufo", "pet_mount_magic_carpet", "pet_mount_sunset_cloud",
          "pet_mount_crescent_moon", "pet_mount_ice_cloud", "pet_mount_star_cushion", "pet_mount_flame_cloud"]

g = runpy.run_path(os.path.join(HERE, "ranch_exclusive_carousel.py"), run_name="__main__")
cx, cy, _ = g["CAROUSEL_CENTRE"]
for name, (x, y, z, _yaw) in zip(MOUNTS, g["CAROUSEL_SPOTS"]):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(OUT, name + ".fbx"), axis_forward="-Z", axis_up="Y")
    for o in set(bpy.data.objects) - before:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
            continue
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        o.parent = None
        bpy.context.view_layer.update()
        o.data.transform(o.matrix_world)
        o.matrix_world.identity()
        vs = [v.co for v in o.data.vertices]
        mx = (min(v.x for v in vs) + max(v.x for v in vs)) / 2
        my = (min(v.y for v in vs) + max(v.y for v in vs)) / 2
        z0 = min(v.z for v in vs)
        span = max(max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs))
        k = 4.4 / span   # riders shown a bit larger than the 3.3-stud seat; the game sets their scale
        # long axis (x) along the tangent of the turn, so riders look like they ride round
        tang = math.atan2(y - cy, x - cx) + math.pi / 2
        o.data.transform(Matrix.Translation((x, y, z)) @ Matrix.Rotation(tang, 4, "Z") @ Matrix.Scale(k, 4) @ Matrix.Translation((-mx, -my, -z0)))

if os.environ.get("PREVIEW_SIBLINGS"):
    for fname, dx in (("ranch_item_shop.py", -21.0), ("ranch_upgrade_cabinet.py", 21.0)):
        before = set(bpy.data.objects)
        runpy.run_path(os.path.join(HERE, fname), run_name="__main__")
        for o in set(bpy.data.objects) - before:
            if o.type == "MESH":
                o.location.x += dx
