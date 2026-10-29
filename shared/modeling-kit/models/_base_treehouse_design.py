# Design preview (not an asset): the Tree House base assembled from its game pieces (_treehouse_pieces) through the
# same slot plan the game gets (_treehouse_pieces.slot_plan: offset + uniform scale per slot, show top/covered), at the
# numbers in _treehouse_layout. Tint pieces are value-only greys multiplied by their skin colour, as MeshPart.Color does.
# Env:
#   FLOORS=1..4   floors standing (the top one wears the canopy, nest, mascot and the slide)
#   THEME=classic|garden|crystal|starlight|candy|mushroom|fairground|haunted|beach|space|winter
#   CUT=1         cut-away: everything loses its front half (y < 0) so the inside reads
#   COLLIDERS=1   the layout's colliders in orange instead of the meshes (pads, vat, lock stay)
#   FLOORS=4 python iterate.py models/_base_treehouse_design.py --name _d_treehouse_4f --look roblox --no-export \
#       --no-ref --res 640 --views 4,2
import math
import os

import bmesh
import bpy

from lib import apply_transforms, rgb, vcol_material
import models._base_concept_common as C
from models._base_design_common import build_colliders, floor_top
import models._treehouse_layout as L
import models._treehouse_pieces as PC

FLOORS = int(os.environ.get("FLOORS", "4"))
THEME = os.environ.get("THEME", "classic")
CUT = os.environ.get("CUT", "0") == "1"
COLL = os.environ.get("COLLIDERS", "0") == "1"
TURN = 0.0 if (CUT or COLL) else -25.0
ROLE = PC.roles(THEME)

objs, glass_objs = [], []


def bisect(o, co, no):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no, clear_outer=True)
    bm.to_mesh(o.data)
    bm.free()


def shown(s):
    f = s["floor"]
    if f > FLOORS:
        return False
    return s["show"] is None or (s["show"] == "top") == (f == FLOORS)


# ---- ground, pads, floor-1 front ----
C.plot_foot(moat=True, door_r=L.room_out(1))
for p in L.PADS:
    if p["floor"] <= FLOORS:
        C.stand(f"Pad{p['j']}", p["x"], p["y"], floor_top(p["floor"]), trim=C.LILAC)
z1 = floor_top(1)
C.vat(L.VAT["x"], L.VAT["y"], z1)
C.lock_button(L.LOCK_BUTTON["x"], L.LOCK_BUTTON["y"], z1)
C.avatar(*L.SPAWN, z1)
C.avatar(4, -L.room_out(1) - 6, 1.0, rgb(230, 120, 90))

if COLL:
    coll = []
    build_colliders(L, coll.append)
    for o, spec in zip(coll, L.COLLIDERS):
        if spec["floor"] > FLOORS:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        apply_transforms(o)
        C.contents.append(o)
else:
    built = {}
    for name, fn in PC.PIECES.items():
        built[name] = fn()
    for s in PC.slot_plan():
        if not shown(s):
            continue
        if s["mesh"] == "goo_jar_mascot":
            C.mascot(0, 0, s["up"] + 0.3, s=4.0)
            continue
        parts = [o.copy() for o in built[s["mesh"]]]
        for o in parts:
            o.data = o.data.copy()
            bpy.context.scene.collection.objects.link(o)
        o = C.join(f"{s['name']}_{s['floor']}", parts)
        apply_transforms(o)
        k = s["scale"]
        for v in o.data.vertices:
            v.co.x *= k
            v.co.y *= k
            v.co.z = s["up"] + v.co.z * k
        if s["role"]:
            t = ROLE[s["role"]]
            for d in o.data.color_attributes["Col"].data:
                c = d.color_srgb
                d.color_srgb = (c[0] * t[0], c[1] * t[1], c[2] * t[2], c[3])
        objs.append(o)
        if s["glass"]:
            glass_objs.append(o)
    for lst in built.values():
        for o in lst:
            bpy.data.objects.remove(o, do_unlink=True)
    if CUT:
        for o in objs:
            bisect(o, (0, 0, 0), (0, -1, 0))

C.ship("_base_treehouse_design", turn=0)
mat = vcol_material("treehouse_vcol")
for o in objs:
    o.data.materials.clear()
    o.data.materials.append(mat)
    o.data.color_attributes.active_color = o.data.color_attributes["Col"]


def see_through(o, t):
    """The glass band's preview look: its vertex colour mixed with a transparent BSDF (the game shows it see-through)."""
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
