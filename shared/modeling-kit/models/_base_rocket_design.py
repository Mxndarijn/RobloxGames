# Design preview (not an asset): the Space Rocket base assembled from its game pieces (_rocket_pieces) at the numbers
# in _rocket_layout, placed the way BaseShapeData/RocketMeshes.luau places them (the nose, its trim, the cockpit and
# the mascot built on floor 4 and scaled to the top floor). Tint pieces are value-only greys multiplied by their skin
# colour in sRGB, the way MeshPart.Color does.
# Env:
#   FLOORS=1..4      floors standing (the top one wears the nose, cockpit, mascot and the escape chute)
#   THEME=classic|garden|crystal|...   (BUILT_THEMES)
#   CUT=1            cut-away: the hull, glass and rings lose their front half (y < 0)
#   python iterate.py models/_base_rocket_design.py --name _d_rocket --look roblox --no-export --no-ref --res 640 --views 4,2
import math
import os

import bmesh
import bpy

from lib import apply_transforms, rgb, tube, vcol_material
import models._base_concept_common as C
from models._base_design_common import floor_top
import models._rocket_layout as L
import models._rocket_pieces as PC

FLOORS = int(os.environ.get("FLOORS", "4"))
THEME = os.environ.get("THEME", "classic")
CUT = os.environ.get("CUT", "0") == "1"
TURN = 0.0 if CUT else -25.0
ROLE = PC.roles(THEME)

objs, shell, glass_objs = [], [], []


def piece(name, parts, role=None, is_shell=False, is_glass=False):
    parts = [p for p in parts if p is not None]
    o = C.join(name, parts)
    apply_transforms(o)
    if role is not None:
        t = ROLE[role]
        for d in o.data.color_attributes["Col"].data:
            c = d.color_srgb
            d.color_srgb = (c[0] * t[0], c[1] * t[1], c[2] * t[2], c[3])
    objs.append(o)
    if is_shell:
        shell.append(o)
    if is_glass:
        glass_objs.append(o)
    return o


def on_top(o, f):
    """Fit a mesh built on floor 4's nose onto top floor f's: scale by nose_k(f) about its rim (as RocketMeshes)."""
    k = L.nose_k(f)
    zt4, ztf = PC._zt(4), PC._zt(f)
    for v in o.data.vertices:
        v.co.x *= k
        v.co.y *= k
        v.co.z = ztf + (v.co.z - zt4) * k


def bisect(o, co, no):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no, clear_outer=True)
    bm.to_mesh(o.data)
    bm.free()


C.plot_foot(moat=True, door_r=L.room_out(1))
for f in range(1, FLOORS + 1):
    z = floor_top(f)
    top = f == FLOORS
    for p in L.PADS:
        if p["floor"] == f:
            C.stand(f"Pad{p['j']}", p["x"], p["y"], z)
    piece(f"rocket_hull_{f}", PC.hull(f), f"stage_{f}", is_shell=True)
    piece(f"rocket_glass_{f}", PC.hull_glass(f), "glass", is_shell=True, is_glass=True)
    piece(f"rocket_ring_{f}", PC.joint_ring(f), "joint", is_shell=True)
    piece(f"rocket_deck_{f}" if f > 1 else "rocket_post", PC.deck(f), "deck")
    if not top:
        o = piece(f"rocket_ramp_{f}", PC.ramp(1), "ramp")
        for v in o.data.vertices:
            v.co.z += floor_top(f) - floor_top(1)
    else:
        on_top(piece("rocket_nose", PC.nose(), "nose", is_shell=True), f)
        on_top(piece("rocket_nose_trim", PC.nose_trim(), "trim", is_shell=True), f)
        on_top(piece("rocket_cockpit", PC.cockpit(), "glass", is_glass=True), f)
        C.mascot(0, 0, L.MASCOT_Z(f) + 0.1, s=3.0)
        if f > 1:
            piece(f"rocket_chute_{f}", PC.chute(f), "trim")
piece("rocket_fins", PC.fins(), "fin")
piece("rocket_boosters", PC.boosters(), "trim")
z1 = floor_top(1)
C.vat(L.VAT["x"], L.VAT["y"], z1)
C.lock_button(L.LOCK_BUTTON["x"], L.LOCK_BUTTON["y"], z1)
C.avatar(*L.SPAWN, z1)
C.avatar(4, -L.room_out(1) - 6, 1.0)
# the jar's round door ring (the game moves it to this doorway), a stand-in torus for scale
_ry = -L.room_out(1) - 0.3
_ring = [(5.9 * math.cos(math.radians(a)), _ry, z1 + 5.6 + 5.9 * math.sin(math.radians(a))) for a in range(-90, 271, 15)]
C.add(tube("JarDoorRing", _ring, [0.55] * len(_ring), rgb(158, 108, 68), segs=8))

if CUT:
    for o in shell:
        bisect(o, (0, 0, 0), (0, -1, 0))
C.ship("_base_rocket_design", turn=0)
mat = vcol_material("rocket_vcol")
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
