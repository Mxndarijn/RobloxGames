# Preview helper (not an asset): build another model, then multiply its "Col" by a tint, the way
# the game's MeshPart.Color is assumed to tint vertex colours (Detail.luau tints the cottage and
# pad_trim, SlimeMesh sets mesh.Color = genome colour).
#   TINT_MODEL=models/plot_building.py TINT_RGB=120,200,255 python3 iterate.py models/_tinted.py --no-export --name x
import os, runpy
import bpy

runpy.run_path(os.environ["TINT_MODEL"], run_name="__main__")
t = [int(c) / 255 for c in os.environ.get("TINT_RGB", "255,255,255").split(",")]
for o in bpy.context.scene.objects:
    if o.type == "MESH" and "Col" in o.data.color_attributes:
        ca = o.data.color_attributes["Col"]
        for d in ca.data:
            c = d.color
            d.color = (c[0] * t[0], c[1] * t[1], c[2] * t[2], c[3])
