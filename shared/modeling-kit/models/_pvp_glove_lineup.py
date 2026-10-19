# Preview scene (not an asset): the five Knockback gloves side by side, rank 1 -> 5 left to right, to check that the
# tiers escalate in size, detail and flash. Render:
#   python iterate.py models/_pvp_glove_lineup.py --no-export --views 0 --res 640 --sheet sheets/pvp_knock_glove_lineup.png
import os
import bpy

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for i in range(1, 6):
    path = os.path.join(KIT, "models", "pvp_knock_glove_%d.py" % i)
    before = set(bpy.data.objects.keys())
    exec(compile(open(path).read(), path, "exec"), {"__name__": "__model__", "__file__": path})
    new = [bpy.data.objects[n] for n in bpy.data.objects.keys() if n not in before and bpy.data.objects[n].type == "MESH"]
    new[-1].location.x = (i - 3) * 2.7
