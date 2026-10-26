# Goo Factory base, detailed design preview (not an asset): the mesh pieces from _factory_pieces placed by
# _factory_layout, with pads, vat, lock button and mascot.
# Env: FLOORS=1..4, CUT=1 (cut-away: storey walls, roof and roof kit lose their front half; the core wall goes
# see-through), COLLIDERS=1 (the layout's colliders in see-through orange over the floors, ramps and pads; walls and
# roof meshes hidden), THEME=classic|garden|crystal|starlight|candy|mushroom (tint-only pieces take the theme's role
# colour as MeshPart.Color would; themed pieces use the palette), LOCKED=1 (shutter down).
import os

import bpy

from lib import mix, rgb, shade
from models._base_concept_common import (CUT, FLOORS, add, avatar, glass, lock_button, mascot, ship, slime, stand,
                                         vat)
from models._base_design_common import build_colliders, floor_top, theme
import models._factory_layout as L
import models._factory_pieces as PC

TID = os.environ.get("THEME", "classic")
TH = theme(TID)
COLL = os.environ.get("COLLIDERS", "0") == "1"
LOCKED = os.environ.get("LOCKED", "0") == "1"
PLOT_COL = rgb(196, 166, 232)  # the per-plot colour on the stands' dish (fixed in every theme)


def tint(objs, col):
    for o in objs:
        ca = o.data.color_attributes.get("Col")
        if ca is None:
            continue
        # multiply in sRGB, as picked (the attribute stores sRGB bytes; .color would be linear), like MeshPart.Color
        for d in ca.data:
            c = d.color_srgb
            d.color_srgb = (c[0] * col[0], c[1] * col[1], c[2] * col[2], c[3])


def role_col(role):
    if role == "brick":
        return PC.wall_col(TID, TH)
    if role == "glass":
        return TH["glass"]
    return TH[role]


def place(name, dz, into=None, built=None):
    build, role = PC.PIECES[name]
    objs = built if built is not None else build(TID, TH)
    if role:
        tint(objs, role_col(role))
    for o in objs:
        o.location.z += dz
        add(o, into=into)
    return objs


SHELL = None if COLL else "shell"
F = FLOORS

# Plot foot (with the theme's door-zone and yard touches), yard silos
place("factory_foot", 1.0)
for (x, y) in L.SILOS:
    objs = PC.silo()
    tint(objs, TH["metal"])
    for o in objs:
        o.location.x += x
        o.location.y += y
        o.location.z += 1.0
        add(o)

for f in range(1, F + 1):
    z = floor_top(f)
    top = f == F
    sfx = "_1" if f == 1 else ""
    if not COLL:
        for nm in ("factory_storey", "factory_trim", "factory_windows", "factory_pipes"):
            place(nm + sfx, z, into="shell")
        if TID != "classic" and f > 1:
            place("factory_dress", z, into="shell")
        if top:
            place("factory_parapet", z, into="shell")
    place("factory_floor_1" if f == 1 else "factory_slab", z)
    core = PC.core()
    tint(core, TH["wood_d"])
    for o in core:
        o.location.z += z
        front = o.name.startswith(("CoreFront", "Port"))
        if COLL or (CUT and front):  # the cut-aways leave the core's front wall out so the switchback shows
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        add(o)
    if f > 1:
        place("factory_stair", floor_top(f - 1))
        place("factory_belt", z)
        place("factory_hatch", z, into=SHELL)
        for k in range(3):
            slime((L.BELT["x0"] + 6) + k * 12, L.BELT["y"], z + L.BELT["h"], k + f, r=1.0)
    if top:
        if f > 1:
            place("factory_core_cap", z)
            place(f"factory_chute_{f}", 1.0)
        if not COLL:
            place("factory_roof", z, into="shell")
            place("factory_roof_kit", z, into="shell")
            mascot(9.0, 4.0, z + L.FLOOR_H + 0.8 + 11.2, s=3.8 + 0.3 * F, crown=F == 4)
    for p in L.PADS:
        if p["floor"] == f:
            stand(f"Pad{p['j']}", p["x"], p["y"], z, PLOT_COL)

if not COLL:
    place("factory_sign", 1.0, into="shell")
# Floor-1 front: door frame, shutter, vat, lock button, players for scale
place("factory_door_frame", 1.0)
shut = PC.shutter(shut=LOCKED)
for o in shut:
    o.location.z += 1.0
    add(o)
vat(L.VAT["x"], L.VAT["y"], 1.0)
lock_button(L.LOCK_BUTTON["x"], L.LOCK_BUTTON["y"], 1.0)
avatar(L.SPAWN[0], L.SPAWN[1], 1.0)
avatar(3.0, -(L.HALF + 9), 1.0, rgb(230, 120, 90))

if COLL:
    build_colliders(type("Lf", (), {"COLLIDERS": [c for c in L.COLLIDERS if c.get("collide", True)
                                                   and c["name"] not in ("PlotFloor",) and c["floor"] <= F
                                                   and not (CUT and c["name"] == "CoreFront")
                                                   and not (c["role"] in ("roof",) and c["floor"] != F)]}),
                    lambda o: glass.append(o))

out = ship("_base_factory_design", turn=-25)


def see_through(o, t):
    """Give the glass mesh its own vertex-colour material mixed with a transparent BSDF (the default look ignores
    rbx_transparency; --look roblox still reads it)."""
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
    out_n = nt.nodes["Material Output"]
    nt.links.new(b.outputs["BSDF"], mx.inputs[1])
    nt.links.new(clear.outputs["BSDF"], mx.inputs[2])
    nt.links.new(mx.outputs["Shader"], out_n.inputs["Surface"])
    o.data.materials.clear()
    o.data.materials.append(m)
    o["rbx_transparency"] = t


for o in out:
    if o.name.endswith("_glass"):
        see_through(o, 0.35 if COLL else 0.6)
bpy.context.scene.cycles.transparent_max_bounces = 32
