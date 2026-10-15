# Preview (not an asset): the new props side by side at true scale (studs) for the overview.
import os
import bpy
from lib import vcol_material

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROW = [("rock_b", -16.5, -3), ("rock_a", -11, -3), ("rock_c", -5.5, -3), ("pad_trim", 2.5, -4), ("slime_base", 9.5, -4),
       ("tree_pine", -22, 10), ("tree_oak", -12, 8), ("tree_blossom", 0, 8), ("plot_building", 20, 10)]
for name, x, y in ROW:
    bpy.ops.import_scene.fbx(filepath=os.path.join(KIT, "out", name + ".fbx"))
    for o in bpy.context.selected_objects:
        ca = o.data.color_attributes
        mat = vcol_material("ov_" + ca[0].name)
        mat.node_tree.nodes["Color Attribute"].layer_name = ca[0].name
        o.data.materials.clear()
        o.data.materials.append(mat)
        o.location.x += x
        o.location.y += y
        if name == "slime_base":
            o.rotation_euler.z += 3.14159  # shipped facing Roblox -Z; turn back towards the camera
