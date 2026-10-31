# Habitat combo preview (not an asset; always --no-export). Puts one full habitat on the cork stand the way the game
# draws it (Habitats.luau / HabitatFx): the rarity frame, the glow lip (tiers 7-9, shown white), the theme props moved
# back onto the dish centre by out/<theme>.deck.json, and the signature prop on the front of the rim (kit -Y) at
# PROP_RADIUS. Reads the exported FBXs in out/, so build those first.
#   HABITAT_COMBO=reef:5:captain_goo python iterate.py models/_habitat_combo.py --no-export --look roblox \
#       --sheet sheets/_wip/combo_captain_goo.png
import json
import os

import bpy
from lib import *
from models._goo_jar import D, cork_stand

DECK = D["padSeatY"]
PROP_RADIUS = 3.15  # Habitats.PROP_RADIUS
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out")

theme, tier, species = (os.environ.get("HABITAT_COMBO") or "reef:5:captain_goo").split(":")


def load(name, x=0.0, y=0.0):
    """Imports out/<name>.fbx with its bbox bottom-centre at (x, y, DECK)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(OUT, f"{name}.fbx"))
    objs = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    bpy.context.view_layer.update()
    vs = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    cx = (max(v.x for v in vs) + min(v.x for v in vs)) / 2
    cy = (max(v.y for v in vs) + min(v.y for v in vs)) / 2
    z0 = min(v.z for v in vs)
    for o in objs:
        o.location.x += x - cx
        o.location.y += y - cy
        o.location.z += DECK - z0
    return objs


parts = load(f"habitat_frame_{tier}")
if int(tier) >= 7:
    parts += load("habitat_frame_glow")
deck = json.load(open(os.path.join(OUT, f"habitat_theme_{theme}.deck.json")))
parts += load(f"habitat_theme_{theme}", *deck["centre"])
if species != "-":
    parts += load(f"habitat_prop_{species}", 0.0, -PROP_RADIUS)
for o in parts:  # imported meshes carry their own vcol material; give them the kit's so the sheet shows the colours
    ca = o.data.color_attributes
    if len(ca):
        mat = vcol_material("combo_vcol_" + ca[0].name)
        mat.node_tree.nodes["Color Attribute"].layer_name = ca[0].name
        o.data.materials.clear()
        o.data.materials.append(mat)
stand = cork_stand()
parts += stand
