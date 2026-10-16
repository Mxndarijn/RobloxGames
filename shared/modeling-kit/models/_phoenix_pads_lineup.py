# Preview (not an asset): all Phoenix slime pads side by side (shipped FBXs from out/), each with a
# 3-stud slime standing on its slime-standing top, to check that the variants swap into one slot.
import math, os
import bpy
from mathutils import Matrix, Vector
from lib import *
from models._slime import body

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in dir() else os.getcwd()
# (pad, z the slime stands on): crate mat, goo surface, hay hollow, stool cushion, new three
PADS = [("phoenix_pad_crate", 2.61), ("phoenix_pad_goo", 1.6), ("phoenix_pad_hay", 1.15), ("phoenix_pad_stool", 3.17),
        ("phoenix_pad_barrel_top", 2.25), ("phoenix_pad_flower_bed", 2.4), ("phoenix_pad_mushroom", 3.0)]
PITCH = 9.5
TINTS = [(170, 220, 170), (90, 200, 255), (255, 190, 40), (180, 80, 255), (255, 120, 170), (120, 150, 255), (255, 170, 60)]


def import_fbx(name):
    bpy.ops.import_scene.fbx(filepath=os.path.join(KIT, "out", name + ".fbx"))
    o = bpy.context.selected_objects[0]
    ca = o.data.color_attributes
    mat = vcol_material("scene_" + name)
    mat.node_tree.nodes["Color Attribute"].layer_name = ca[0].name
    o.data.materials.clear()
    o.data.materials.append(mat)
    bpy.context.view_layer.update()
    return o


for i, ((name, top), tint) in enumerate(zip(PADS, TINTS)):
    x = (i - (len(PADS) - 1) / 2) * PITCH
    o = import_fbx(name)
    o.matrix_world = Matrix.Translation((x, 0, 0)) @ o.matrix_world
    s = body(f"Slime{i}")
    t = [c / 255 for c in tint]
    for d in s.data.color_attributes["Col"].data:
        c = d.color
        d.color = (c[0] * t[0], c[1] * t[1], c[2] * t[2], 1.0)
    s.data.materials.clear()
    s.data.materials.append(vcol_material(f"slime{i}"))
    s.matrix_world = Matrix.Translation((x, 0, top))
