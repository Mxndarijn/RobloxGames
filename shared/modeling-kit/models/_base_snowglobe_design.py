# Design preview (not an asset): the Snow Globe base assembled from its pieces (_snowglobe_pieces) the way the game
# places them (_snowglobe_meshes.SLOTS: the same floors, offsets and show flags). Tint pieces are value-only greys
# multiplied by their skin colour, the way MeshPart.Color would; glass slots are see-through.
# Env:
#   LAYOUT_FLOORS=1..4  floors standing (the top one wears its top variants: dome, crown, mascot, chute, pines)
#   THEME=classic|winter|...   (palettes from _goo_jar_themes, never copied)
#   CUT=1               cut-away: everything round loses its front half (y < 0)
#   python iterate.py models/_base_snowglobe_design.py --name _d_snowglobe --look roblox --no-export --no-ref \
#       --res 640 --views 4,2
import math
import os

import bmesh
import bpy

from lib import apply_transforms, rgb, vcol_material
import models._base_concept_common as C
from models._base_design_common import floor_top
import models._snowglobe_layout as L
import models._snowglobe_pieces as PC


FLOORS = int(os.environ.get("LAYOUT_FLOORS", os.environ.get("FLOORS", "4")))
THEME = os.environ.get("THEME", "classic")
CUT = os.environ.get("CUT", "0") == "1"
TURN = 0.0 if CUT else -25.0
ROLE = PC.roles(THEME)

objs, glass_objs, cuttable = [], [], []


def piece(name, parts, role=None):
    parts = [p for p in parts if p is not None]
    if not parts:
        return None
    o = C.join(name, parts)
    apply_transforms(o)
    if role is not None:
        t = ROLE[role]
        for d in o.data.color_attributes["Col"].data:
            c = d.color_srgb
            d.color_srgb = (c[0] * t[0], c[1] * t[1], c[2] * t[2], c[3])
    objs.append(o)
    return o


def place(o, up, k):
    """The game's slot fit: scale k about the plot origin, then up."""
    for v in o.data.vertices:
        v.co *= k
        v.co.z += up


C.plot_foot(moat=True, ground=rgb(120, 196, 108), door_r=L.room_out(1))
for p in L.PADS:
    if p["floor"] <= FLOORS:
        C.stand(f"Pad{p['j']}", p["x"], p["y"], floor_top(p["floor"]), trim=C.LILAC)
for s in PC.slots_for(FLOORS):
    if s["mesh"] == "goo_jar_mascot":
        C.mascot(0, 0, s["offset"][1], s=4.0)
        continue
    o = piece(f"{s['name']}_{s['floor']}", PC.PIECES[s["mesh"]](), s["role"])
    place(o, s["offset"][1], s["scale"])
    if s["glass"]:
        glass_objs.append(o)
    if s["mesh"] not in ("snowglobe_core", "snowglobe_post", "snowglobe_pine", "snowglobe_decor"):
        cuttable.append(o)
z1 = floor_top(1)
C.vat(L.VAT["x"], L.VAT["y"], z1)
C.lock_button(L.LOCK_BUTTON["x"], L.LOCK_BUTTON["y"], z1)
C.avatar(*L.SPAWN, z1)
C.avatar(4, -L.room_out(1) - 6, 1.0, rgb(230, 120, 90))

if CUT:
    for o in cuttable:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0),
                               plane_no=(0, -1, 0), clear_outer=True)
        bm.to_mesh(o.data)
        bm.free()
C.ship("_base_snowglobe_design", turn=0)
mat = vcol_material("snowglobe_vcol")
for o in objs:
    o.data.materials.clear()
    o.data.materials.append(mat)
    o.data.color_attributes.active_color = o.data.color_attributes["Col"]


def see_through(o, t):
    m = bpy.data.materials.new(o.name + "_see")
    m.use_nodes = True
    nt = m.node_tree
    c = nt.nodes.new("ShaderNodeVertexColor")
    c.layer_name = "Col"
    b = nt.nodes["Principled BSDF"]
    nt.links.new(c.outputs["Color"], b.inputs["Base Color"])
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mx = nt.nodes.new("ShaderNodeMixShader")
    # Roblox culls back faces: a closed glass shell shows one face per wall crossing, not two (Backfacing -> clear)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    mxv = nt.nodes.new("ShaderNodeMath")
    mxv.operation = "MAXIMUM"
    mxv.inputs[1].default_value = t
    nt.links.new(geo.outputs["Backfacing"], mxv.inputs[0])
    nt.links.new(mxv.outputs["Value"], mx.inputs["Fac"])
    nt.links.new(b.outputs["BSDF"], mx.inputs[1])
    nt.links.new(clear.outputs["BSDF"], mx.inputs[2])
    nt.links.new(mx.outputs["Shader"], nt.nodes["Material Output"].inputs["Surface"])
    o.data.materials.clear()
    o.data.materials.append(m)
    o["rbx_transparency"] = t


for o in glass_objs:
    see_through(o, 0.8)
    o.visible_shadow = False      # the game's glass slots have MeshCastShadow off
bpy.context.scene.cycles.transparent_max_bounces = 48
for o in bpy.context.scene.objects:
    if o.type == "MESH" and TURN:
        o.rotation_euler.z += math.radians(TURN)
bpy.context.view_layer.update()
