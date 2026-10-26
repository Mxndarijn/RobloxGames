# Not an asset: writes games/steal-a-slime/src/visuals/shared/BaseShapeData/PagodaMeshes.luau, the Mushroom Pagoda's
# mesh slots for the game (BaseShapes), in the same shape as FactoryMeshes (see models/_factory_meshes.py):
#   boxes  every shipped mesh's box round its build origin (plot-local game axes), the goo_jar_mascot's from JarMeshes;
#   slots  floor, name, mesh, offset (x, up, z) of the build origin after scaling, `scale` (a piece built for one floor
#          and fitted onto another: the dome onto the top floor, spots and a skin's cap extras onto each cap, the same
#          way models/_base_pagoda_design.py places them), show ("top" / "covered" / nil), tint role, plot = true;
#   tints  per skin, per role, MeshPart.Color (sRGB 0..255).
# Writes inputs/pagoda_theme_boxes.json too: the union box each shared slot's skins are anchored to (_pagoda_ship.py).
# Run: python iterate.py models/_pagoda_meshes.py --quick --no-export
import json
import os
import re

import bpy

from models._base_design_common import floor_top
from models._goo_jar_themes import BUILT_THEMES
import models._pagoda_layout as L
import models._pagoda_pieces as PC

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.environ.get("GAME_DIR", os.path.join(KIT, "..", "..", "games", "steal-a-slime"))
SKINS = ("classic",) + tuple(BUILT_THEMES)
FLOORS = 4


def raw_box(objs):
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    return lo, hi


def game_box(lo, hi):
    # blender (x, y, z) -> game plot-local (x, y, z) = (x, z, y)
    return [hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]], [(lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2, (lo[1] + hi[1]) / 2]


# ---- boxes (shared slots: the union over their skins) ----
raw = {name: raw_box(fn()) for name, fn in PC.SHIP.items()}
union = {}
for slot in PC.SHARED_SLOTS:
    names = [n for n in raw if n == slot or n.startswith(slot + "@")]
    lo = [min(raw[n][0][i] for n in names) for i in range(3)]
    hi = [max(raw[n][1][i] for n in names) for i in range(3)]
    union[slot] = {"lo": [round(v, 3) for v in lo], "hi": [round(v, 3) for v in hi]}
    for n in names:
        raw[n] = (union[slot]["lo"], union[slot]["hi"])
with open(os.path.join(KIT, "inputs", "pagoda_theme_boxes.json"), "w", encoding="utf-8") as fh:
    json.dump(union, fh, indent=1)
boxes = {name: game_box(*raw[name]) for name in raw}
# the jar's mascot rides the dome (its JarMeshes box: native size round its bottom anchor)
jar_meshes = open(os.path.join(GAME, "src", "visuals", "shared", "JarMeshes.luau"), encoding="utf-8").read()
m = re.search(r"goo_jar_mascot = \{ size = \{ ([^}]*) \}, centre = \{ ([^}]*) \} \}", jar_meshes)
boxes["goo_jar_mascot"] = ([float(v) for v in m.group(1).split(",")], [float(v) for v in m.group(2).split(",")])

# ---- slots ----
slots = []


def slot(floor, name, mesh, up=0.0, scale=1.0, show=None, role=None, plot=False, glass=False):
    slots.append({"floor": floor, "name": name, "mesh": mesh, "offset": [0.0, up, 0.0], "scale": scale, "show": show,
                  "role": role, "plot": plot, "glass": glass})


def on_cap(f, native=PC.CAP_NATIVE):
    """(offset up, scale) that fit a piece built on cap `native` onto cap f (the scene's on_cap)."""
    dz = floor_top(f) - floor_top(native)
    k = L.eave_r(f) / L.eave_r(native)
    ze = floor_top(f) + L.CAP_UNDER + 0.8
    return ze + (dz - ze) * k, k


def on_dome(f):
    dz = floor_top(f) - floor_top(PC.DOME_NATIVE_FLOOR)
    k = L.eave_r(f) / L.eave_r(PC.DOME_NATIVE_FLOOR)
    zc = floor_top(f) + L.CAP_UNDER
    return zc + (dz - zc) * k, k


for f in range(1, FLOORS + 1):
    covered = None if f == FLOORS else "covered"
    top = None if f == FLOORS else "top"
    slot(f, "Room", f"pagoda_room_{f}", role="stalk")
    slot(f, "Glass", f"pagoda_glass_{f}", role="glass", glass=True)
    if f > 1:
        slot(f, "Deck", f"pagoda_deck_{f}", role="wood")
    slot(f, "Lamps", "pagoda_lamps", up=floor_top(f) - floor_top(2), role="glow")
    up, k = on_cap(f)
    slot(f, "RimExtra", "pagoda_rim_extra", up=up, scale=k)
    if f < FLOORS:
        slot(f, "Cap", f"pagoda_cap_{f}_mid", show=covered, role=f"cap_{f}")
        slot(f, "Spots", "pagoda_spots_mid", up=up, scale=k, show=covered, role="spots")
        slot(f, "CapExtra", "pagoda_cap_extra", up=up, scale=k, show=covered)
        slot(f, "Turret", "pagoda_turret_mid", up=floor_top(f) - floor_top(2), show=covered, role="stalk")
        slot(f, "RampLook", "pagoda_ramp", up=floor_top(f) - floor_top(1), show=covered, role="ramp")
    up, k = on_dome(f)
    slot(f, "Dome", "pagoda_dome", up=up, scale=k, show=top, role="dome")
    slot(f, "DomeSpots", "pagoda_dome_spots", up=up, scale=k, show=top, role="spots")
    slot(f, "DomeExtra", "pagoda_dome_extra", up=up, scale=k, show=top)
    slot(f, "TurretTop", "pagoda_turret_top", up=floor_top(f) - floor_top(4), show=top, role="stalk")
    slot(f, "TurretCap", "pagoda_turret_cap", up=floor_top(f) - floor_top(4), show=top, role="turret_cap")
    crown = (PC.dome_top()[-1][1] - floor_top(PC.DOME_NATIVE_FLOOR) - L.CAP_UNDER) * k + floor_top(f) + L.CAP_UNDER
    slot(f, "MascotLook", "goo_jar_mascot", up=crown - 0.3, scale=3.8, show=top)
    if f > 1:
        slot(f, "Vine", f"pagoda_vine_{f}", show=top, role="vine")
slot(1, "FootDecor", "pagoda_foot_decor")
slot(1, "DoorFrame", "pagoda_door_ring")

# ---- tints ----
roles = sorted({s["role"] for s in slots if s["role"]})
tints = {}
for tid in SKINS:
    r = PC.roles(tid)
    tints[tid] = {role: [round(v * 255) for v in r[role][:3]] for role in roles}


def lua_vec(v, nd=3):
    return "{ " + ", ".join(f"{x:.{nd}f}" for x in v) + " }"


lines = [
    "--!strict",
    "-- Generated by shared/modeling-kit/models/_pagoda_meshes.py: do not edit by hand. The Mushroom Pagoda's mesh",
    "-- slots (boxes in plot-local game axes, the slot plan per floor with scales, the skin tints per role), see",
    "-- BaseShapes.",
    "return {",
    "\tboxes = {",
]
for name in sorted(boxes):
    s, c = boxes[name]
    key = name if "@" not in name else f'["{name}"]'
    lines.append(f"\t\t{key} = {{ size = {lua_vec(s)}, centre = {lua_vec(c)} }},")
lines.append("\t},")
lines.append("\tslots = {")
for s in slots:
    extra = ""
    if s["scale"] != 1.0:
        extra += f', scale = {s["scale"]:.5f}'
    if s["show"]:
        extra += f', show = "{s["show"]}"'
    if s["role"]:
        extra += f', role = "{s["role"]}"'
    if s["plot"]:
        extra += ", plot = true"
    if s["glass"]:
        extra += ", glass = true"
    lines.append(f'\t\t{{ floor = {s["floor"]}, name = "{s["name"]}", mesh = "{s["mesh"]}", offset = '
                 f'{lua_vec(s["offset"])}{extra} }},')
lines.append("\t},")
lines.append("\ttints = {")
for tid in SKINS:
    row = ", ".join(f"{r} = {{ {', '.join(str(v) for v in tints[tid][r])} }}" for r in roles)
    lines.append(f"\t\t{tid} = {{ {row} }},")
lines.append("\t},")
lines.append("}")
path = os.path.join(GAME, "src", "visuals", "shared", "BaseShapeData", "PagodaMeshes.luau")
with open(path, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(lines) + "\n")
print(f"wrote {path}: {len(boxes)} boxes, {len(slots)} slots, {len(roles)} roles x {len(SKINS)} skins")
