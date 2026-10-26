# Not an asset: writes games/steal-a-slime/src/visuals/shared/BaseShapeData/FactoryMeshes.luau, the Goo Factory's
# mesh slots for the game (BaseShapes):
#   boxes  every shipped mesh's bounding box round its build origin, in plot-local game axes (x right, y up, z back):
#          size and centre, like JarMeshes (themed meshes "<name>@<skin>" too, checked against the classic box);
#   slots  where each mesh stands: the floor (1 = static floor 1), the slot name, the mesh, the offset of its build
#          origin (x, y up, z), `show` ("top" = only while that floor is the top one, "covered" = only while a floor
#          stands on it, nil = always), the tint role (nil = the mesh keeps its own colours), `plot = true` for slots that
#          must be direct children of the plot (FootLook, StopperShut, StopperParked: the game finds them by name);
#   tints  per skin, per role, the MeshPart.Color the game sets on tint-only meshes (sRGB 0..255; Color multiplies the
#          meshes' value-grey vertex colours, checked in Studio).
# Run: python iterate.py models/_factory_meshes.py --quick --no-export
import os

import bpy

from models._base_design_common import floor_top, theme
from models._factory_pieces import PIECES, THEMED, wall_col
from models._goo_jar_themes import BUILT_THEMES
import models._factory_layout as L

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.environ.get("GAME_DIR", os.path.join(KIT, "..", "..", "games", "steal-a-slime"))
SKINS = ("classic",) + tuple(BUILT_THEMES)
FLOORS = 4


def measure(objs):
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
    # blender (x, y, z) -> game plot-local (x, y, z) = (x, z, y)
    c = [(lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2, (lo[1] + hi[1]) / 2]
    s = [hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]]
    return s, c


def role_col(tid, role):
    th = theme(tid)
    if role == "brick":
        return wall_col(tid, th)
    return th[role]


# ---- themed pieces share one box ----
# The game fits a skin's mesh into its slot (MeshSwap), so every skin's version of a themed piece must have the same
# box: the union of all of them. models/_factory_ship.py adds two tiny anchor tetrahedra at that union's corners.
import json


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


union = {}
for name in THEMED:
    build, _ = PIECES[name]
    lo, hi = [1e9] * 3, [-1e9] * 3
    for tid in SKINS:
        if name == "factory_dress" and tid == "classic":
            continue
        a, b = raw_box(build(tid, theme(tid)))
        lo = [min(lo[i], a[i]) for i in range(3)]
        hi = [max(hi[i], b[i]) for i in range(3)]
    union[name] = {"lo": [round(v, 3) for v in lo], "hi": [round(v, 3) for v in hi]}
with open(os.path.join(KIT, "inputs", "factory_theme_boxes.json"), "w", encoding="utf-8") as fh:
    json.dump(union, fh, indent=1)


# ---- boxes ----
boxes = {}
def union_box(name):
    lo, hi = union[name]["lo"], union[name]["hi"]
    c = [(lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2, (lo[1] + hi[1]) / 2]
    s = [hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]]
    return s, c


for name in sorted(PIECES):
    build, _ = PIECES[name]
    if name in THEMED:
        if name != "factory_dress":
            boxes[name] = union_box(name)
        for tid in BUILT_THEMES:
            boxes[f"{name}@{tid}"] = union_box(name)
        continue
    boxes[name] = measure(build("classic", theme("classic")))

# ---- slots ----
slots = []


def slot(floor, name, mesh, dx=0.0, dy=0.0, dz=0.0, show=None, plot=False):
    role = PIECES[mesh][1] if mesh in PIECES else None
    # plan offsets are kit (x, plot z, up): to game (x, up, z)
    slots.append({"floor": floor, "name": name, "mesh": mesh, "offset": [dx, dz, dy], "show": show, "role": role,
                  "plot": plot})


for f in range(1, FLOORS + 1):
    z = floor_top(f)
    sfx = "_1" if f == 1 else ""
    slot(f, "Storey", "factory_storey" + sfx, dz=z)
    slot(f, "Trim", "factory_trim" + sfx, dz=z)
    slot(f, "Windows", "factory_windows" + sfx, dz=z)
    slot(f, "Pipes", "factory_pipes" + sfx, dz=z)
    slot(f, "Parapet", "factory_parapet", dz=z, show=None if f == FLOORS else "top")
    slot(f, "FloorLook", "factory_floor_1" if f == 1 else "factory_slab", dz=z)
    slot(f, "CoreLook", "factory_core", dz=z)
    if f > 1:
        slot(f, "Dress", "factory_dress", dz=z)
        slot(f, "StairLook", "factory_stair", dz=floor_top(f - 1))
        slot(f, "BeltLook", "factory_belt", dz=z)
        slot(f, "HatchLook", "factory_hatch", dz=z)
        slot(f, "CoreCapLook", "factory_core_cap", dz=z, show=None if f == FLOORS else "top")
        slot(f, "ChuteLook", f"factory_chute_{f}", dz=1.0, show=None if f == FLOORS else "top")
    slot(f, "RoofLook", "factory_roof", dz=z, show=None if f == FLOORS else "top")
    slot(f, "RoofKit", "factory_roof_kit", dz=z, show=None if f == FLOORS else "top")
slot(1, "FootLook", "factory_foot", dz=1.0, plot=True)
for k, (x, y) in enumerate(L.SILOS):
    slot(1, f"SiloLook_{k}", "factory_silo", dx=x, dy=y, dz=1.0)
slot(1, "SignLook", "factory_sign", dz=1.0)
slot(1, "DoorFrame", "factory_door_frame", dz=1.0)
slot(1, "StopperShut", "factory_shutter_shut", dz=1.0, plot=True)
slot(1, "StopperParked", "factory_shutter", dz=1.0, plot=True)

# ---- tints ----
roles = sorted({s["role"] for s in slots if s["role"]})
tints = {tid: {r: [round(v * 255) for v in role_col(tid, r)[:3]] for r in roles} for tid in SKINS}


def lua_vec(v, nd=3):
    return "{ " + ", ".join(f"{x:.{nd}f}" for x in v) + " }"


lines = [
    "--!strict",
    "-- Generated by shared/modeling-kit/models/_factory_meshes.py: do not edit by hand. The Goo Factory's mesh slots",
    "-- (boxes in plot-local game axes, the slot plan per floor, the skin tints per role), see BaseShapes.",
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
    if s["show"]:
        extra += f', show = "{s["show"]}"'
    if s["role"]:
        extra += f', role = "{s["role"]}"'
    if s["plot"]:
        extra += ", plot = true"
    lines.append(f'\t\t{{ floor = {s["floor"]}, name = "{s["name"]}", mesh = "{s["mesh"]}", offset = '
                 f'{lua_vec(s["offset"])}{extra} }},')
lines.append("\t},")
lines.append("\ttints = {")
for tid in SKINS:
    row = ", ".join(f"{r} = {{ {', '.join(str(v) for v in tints[tid][r])} }}" for r in roles)
    lines.append(f"\t\t{tid} = {{ {row} }},")
lines.append("\t},")
lines.append("}")
path = os.path.join(GAME, "src", "visuals", "shared", "BaseShapeData", "FactoryMeshes.luau")
with open(path, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(lines) + "\n")
print(f"wrote {path}: {len(boxes)} boxes, {len(slots)} slots, {len(roles)} roles x {len(SKINS)} skins")
