# Preview (not an asset): the hay bale + feed trough set side by side, from the SHIPPED FBXs
# (out/ranch_feed_trough.fbx, out/ranch_hay_bale.fbx), the way a ranch corner would place them:
# trough along X, one bale at its right end turned a little.
#   python3 iterate.py models/_ranch_haybale_trough_set.py --look roblox --ground 120,196,108 \
#       --no-export --res 512 --name ranch_haybale_trough_set
import math, os
import bpy
from mathutils import Matrix
from lib import vcol_material

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def import_fbx(name):
    bpy.ops.import_scene.fbx(filepath=os.path.join(KIT, "out", name + ".fbx"))
    o = bpy.context.selected_objects[0]
    mat = vcol_material("set_" + name)
    mat.node_tree.nodes["Color Attribute"].layer_name = o.data.color_attributes[0].name
    o.data.materials.clear()
    o.data.materials.append(mat)
    bpy.context.view_layer.update()
    return o


def place(o, x, y, deg):
    o.matrix_world = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(deg), 4, "Z") @ o.matrix_world
    bpy.context.view_layer.update()


place(import_fbx("ranch_feed_trough"), -2.0, 0.0, 0)
place(import_fbx("ranch_hay_bale"), 3.6, 0.6, 72)
