# Preview only: exclusive_cloud_nine with three real Exclusive pet seats on its floating puffs.
import math, os, runpy
import bpy
from mathutils import Matrix
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "out")
g = runpy.run_path(os.path.join(HERE, "exclusive_cloud_nine.py"), run_name="__main__")
for name, (x, y, z) in zip(("pet_mount_ufo", "pet_mount_royal_cushion", "pet_mount_magic_carpet"), g["DISPLAYS"]):
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
        span = max(max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs))
        z0 = min(v.z for v in vs)
        k = 3.0 / span
        o.data.transform(Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(-15), 4, "Z") @ Matrix.Scale(k, 4) @ Matrix.Translation((-mx, -my, -z0)))
