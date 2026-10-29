# Design preview (not an asset): the Carousel Tent base assembled from its pieces (_carousel_pieces) at the numbers in
# _carousel_layout, placed the way CarouselMeshes.luau places them (shared pieces shifted up from their native floor).
# Tint pieces are value-only greys multiplied by their skin colour, the way MeshPart.Color does.
# Env:
#   FLOORS=1..4      floors standing (the top one wears the roof, roof gold, mascot and, floors 2-4, the slide)
#   THEME=classic|garden|crystal|...   (a BUILT_THEMES skin; palettes from _goo_jar_themes)
#   CUT=1            cut-away: the shell loses its front half (y < 0)
#   COLLIDERS=1      collider overlay instead of the meshes
#   FLOORS=4 python iterate.py models/_base_carousel_design.py --name _d_carousel_4 --look roblox --no-export --no-ref --res 640 --views 4,2
import math
import os

import bmesh
import bpy

from lib import apply_transforms, cylinder, rgb, vcol_material
import models._base_concept_common as C
from models._base_design_common import build_colliders, floor_top

FLOORS = int(os.environ.get("FLOORS", "4"))
os.environ["LAYOUT_FLOORS"] = str(FLOORS)  # before the layout loads: FLOORS decides which floor wears the roof
import models._carousel_layout as L  # noqa: E402
import models._carousel_pieces as PC  # noqa: E402

THEME = os.environ.get("THEME", "classic")
CUT = os.environ.get("CUT", "0") == "1"
COLL = os.environ.get("COLLIDERS", "0") == "1"
TURN = 0.0 if (CUT or COLL) else -25.0
ROLE = PC.roles(THEME)

objs, shell, glass_objs = [], [], []


def piece(name, up=0.0):
    """Build piece `name`, join it, move it up by `up`, tint it by its role, remember it."""
    parts = [p for p in PC.PIECES[name]() if p is not None]
    o = C.join(name, parts)
    apply_transforms(o)
    for v in o.data.vertices:
        v.co.z += up
    role = PC.TINT.get(name)
    if role is not None:
        t = ROLE[role]
        for d in o.data.color_attributes["Col"].data:
            c = d.color_srgb
            d.color_srgb = (c[0] * t[0], c[1] * t[1], c[2] * t[2], c[3])
    objs.append(o)
    shell.append(o)
    if name in PC.GLASS:
        glass_objs.append(o)
    return o


def shared(name, f):
    return piece(name, floor_top(f) - floor_top(PC.NATIVE[name]))


C.plot_foot(moat=True, door_r=L.room_out(1))
for f in range(1, FLOORS + 1):
    z = floor_top(f)
    top = f == FLOORS
    for p in L.PADS:
        if p["floor"] == f:
            C.stand(f"Pad{p['j']}", p["x"], p["y"], z)
    if COLL:
        continue
    if f == 1:
        piece("carousel_room_1")
        piece("carousel_glass_1")
        piece("carousel_gold_1")
    else:
        shared("carousel_room", f)
        shared("carousel_glass", f)
        shared("carousel_gold", f)
        shared("carousel_deck", f)
        shared("carousel_ramp", f)
    piece("carousel_stripes", floor_top(f) - floor_top(2))
    if top:
        piece(f"carousel_roof_cream_{f}")
        piece(f"carousel_roof_stripe_{f}")
        shared("carousel_roof_gold", f)
        C.mascot(0, 0, L.SPEC["MASCOT_Z"](f), s=3.4)
if not COLL:
    piece("carousel_horses")
    # stand-in for the jar's round door moved to this doorway (the game reuses goo_jar_door + goo_jar_door_ring)
    dy = -(L.room_out(1) - 0.5)
    C.add(cylinder("DoorRing", 6.45, 0.9, (0, dy, 6.4), rgb(214, 170, 116), segs=24, rot=(90, 0, 0)))
z1 = floor_top(1)
C.vat(L.VAT["x"], L.VAT["y"], z1)
C.lock_button(L.LOCK_BUTTON["x"], L.LOCK_BUTTON["y"], z1)
C.avatar(*L.SPAWN, z1)
C.avatar(4, -L.room_out(1) - 6, 1.0, rgb(230, 120, 90))
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
    for o in shell:
        bisect(o)
C.ship("_base_carousel_design", turn=0)
mat = vcol_material("carousel_vcol")
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
