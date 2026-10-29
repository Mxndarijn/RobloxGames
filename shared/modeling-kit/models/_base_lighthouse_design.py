# Design preview (not an asset): the Lighthouse base assembled from its game pieces (_lighthouse_pieces) by the same
# slot plan the game reads (_lighthouse_pieces.slot_plan, written out by _lighthouse_meshes.py). Tint pieces are
# value-only greys multiplied by the skin's colour, the way MeshPart.Color would; glass slots are see-through.
# Env:
#   FLOORS=1..4   floors standing (the top one wears the gallery, lantern, cap, mascot and drop exit)
#   THEME=classic|garden|crystal|starlight|candy|mushroom|fairground|haunted|beach|space|winter
#   CUT=1         cut-away: everything loses its front half (y < 0)
#   COLLIDERS=1   collider overlay: the layout's COLLIDERS (at FLOORS) in orange, no meshes
#   FLOORS=4 python iterate.py models/_base_lighthouse_design.py --name _d_lighthouse_4 --look roblox --no-export --no-ref --res 640 --views 4,2
import math
import os

os.environ.setdefault("LAYOUT_FLOORS", os.environ.get("FLOORS", "4"))

import bmesh
import bpy

from lib import apply_transforms, vcol_material
import models._base_concept_common as C
from models._base_design_common import build_colliders, floor_top
import models._lighthouse_layout as L
import models._lighthouse_pieces as PC

FLOORS = int(os.environ.get("FLOORS", "4"))
THEME = os.environ.get("THEME", "classic")
CUT = os.environ.get("CUT", "0") == "1"
COLL = os.environ.get("COLLIDERS", "0") == "1"
TURN = 0.0 if (CUT or COLL) else -25.0
ROLE = PC.roles(THEME)

objs, glass_objs = [], []


def piece(name, parts, role, up):
    o = C.join(name, [p for p in parts if p is not None])
    apply_transforms(o)
    for v in o.data.vertices:
        v.co.z += up
    if role is not None:
        t = ROLE[role]
        for d in o.data.color_attributes["Col"].data:
            c = d.color_srgb
            d.color_srgb = (c[0] * t[0], c[1] * t[1], c[2] * t[2], c[3])
    objs.append(o)
    return o


def visible(s):
    if s["floor"] > FLOORS:
        return False
    top = s["floor"] == FLOORS
    if s["show"] == "top":
        return top
    if s["show"] == "covered":
        return not top
    return True


C.plot_foot(moat=True, moat_col=C.rgb(80, 170, 230), door_r=L.room_out(1), bridge_len=10.0)
for p in L.PADS:
    if p["floor"] <= FLOORS:
        C.stand(f"Pad{p['j']}", p["x"], p["y"], floor_top(p["floor"]))
if not COLL:
    for s in PC.slot_plan():
        if not visible(s):
            continue
        if s["mesh"] == "goo_jar_mascot":
            C.mascot(0, 0, s["up"], s=4.2)
            continue
        o = piece(f"{s['name']}_{s['floor']}", PC.PIECES[s["mesh"]](), s["role"], s["up"])
        if s["glass"]:
            glass_objs.append(o)
z1 = floor_top(1)
C.vat(L.VAT["x"], L.VAT["y"], z1)
C.lock_button(L.LOCK_BUTTON["x"], L.LOCK_BUTTON["y"], z1)
C.avatar(*L.SPAWN, z1)
C.avatar(4, -L.room_out(1) - 6, 1.0, C.rgb(230, 120, 90))
# the jar's round door stands in the doorway in the game (jarDoor): a stand-in disc here
C.add(C.cylinder("DoorStandIn", 4.2, 1.0, (0, -L.room_out(1) + 0.3, z1 + 4.4), C.rgb(196, 138, 86), segs=20,
                 rot=(90, 0, 0)))
if COLL:
    coll = []
    build_colliders(L, coll.append)
    for o in coll:
        apply_transforms(o)
        C.contents.append(o)


def bisect(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0), plane_no=(0, -1, 0),
                           clear_outer=True)
    bm.to_mesh(o.data)
    bm.free()


if CUT:
    for o in objs:
        bisect(o)
C.ship("_base_lighthouse_design", turn=0)
mat = vcol_material("lighthouse_vcol")
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
    mx.inputs["Fac"].default_value = t
    nt.links.new(b.outputs["BSDF"], mx.inputs[1])
    nt.links.new(clear.outputs["BSDF"], mx.inputs[2])
    nt.links.new(mx.outputs["Shader"], nt.nodes["Material Output"].inputs["Surface"])
    o.data.materials.clear()
    o.data.materials.append(m)
    o["rbx_transparency"] = t


for o in glass_objs:
    see_through(o, 0.8)
bpy.context.scene.cycles.transparent_max_bounces = 32
for o in bpy.context.scene.objects:
    if o.type == "MESH" and TURN:
        o.rotation_euler.z += math.radians(TURN)
bpy.context.view_layer.update()
