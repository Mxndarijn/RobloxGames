# Design preview (not an asset): the Mushroom Pagoda base assembled from its pieces (_pagoda_pieces) at the numbers
# in _pagoda_layout. Tint pieces are value-only greys multiplied by their theme colour, the way MeshPart.Color would.
# Env:
#   FLOORS=1..4      floors standing (the top one wears the dome, turret top storey and cap, mascot, vine)
#   THEME=classic|garden|crystal|starlight|candy|mushroom   (palettes from _goo_jar_themes, never copied)
#   CUT=1            cut-away: rooms and caps lose their front half (y < 0), the turret its right half (x > 0)
#   COLLIDERS=1      collider overlay: the layout's COLLIDERS in orange + pads, door, vat and lock (with CUT=1: cut too)
#   python iterate.py models/_base_pagoda_design.py --name _d_pagoda_hero --no-export --no-ref --res 512 --views 4,2
import colorsys
import math
import os

import bmesh
import bpy

from lib import PALETTE, apply_transforms, mix, rgb, vcol_material
import models._base_concept_common as C
from models._base_design_common import build_colliders, floor_top, theme
import models._pagoda_layout as L
import models._pagoda_pieces as PC

FLOORS = int(os.environ.get("FLOORS", "4"))
THEME = os.environ.get("THEME", "classic")
CUT = os.environ.get("CUT", "0") == "1"
COLL = os.environ.get("COLLIDERS", "0") == "1"
TURN = 0.0 if (CUT or COLL) else -25.0
P = PALETTE
TH = theme(THEME)


def strong(col, sat=0.72, min_v=0.80):
    """A tint colour from a theme colour: same hue, saturation raised to `sat` (never lowered), value >= min_v.
    The theme palettes are pastel for big jar surfaces; mushroom caps want slime-strength colour."""
    h, s, v = colorsys.rgb_to_hsv(*col[:3])
    return colorsys.hsv_to_rgb(h, max(s, sat), max(v, min_v)) + (1.0,)


# Theme roles -> colours, by the theme's own palette keys (never copied values). Caps and dome go through strong().
# Classic follows the picked concept: red, purple and orange caps under a big red dome (ranch roof red, darker and
# browner than the lock button's red). Forest (skin id mushroom) gets earthy caps so it differs from classic.
THEME_KEYS = {  # (eave cap 1, 2, 3), dome; a key may name PALETTE ("P:...")
    "classic": (("P:ranch_roof", "lilac", "butter"), "P:ranch_roof"),
    "garden": (("cork", "goo", "cork"), "goo"),
    "crystal": (("metal", "lilac", "goo"), "goo"),
    "starlight": (("wood", "cork", "wood"), "cork"),
    "candy": (("goo", "metal", "butter"), "wood"),
    "mushroom": (("cork", "leaves", "wood"), "goo"),
}
SAT = {"classic": (0.70, 0.52, 0.76, 0.70)}.get(THEME, (0.55, 0.55, 0.55, 0.6))


def key(k):
    return P[k[2:]] if k.startswith("P:") else TH[k]


CAP_KEYS, DOME_KEY = THEME_KEYS[THEME]
ROLE = {
    "stalk": mix(TH["cream"], TH["wood"], 0.08),
    "wood": TH["wood"],
    "cap_1": strong(key(CAP_KEYS[0]), SAT[0]), "cap_2": strong(key(CAP_KEYS[1]), SAT[1]),
    "cap_3": strong(key(CAP_KEYS[2]), SAT[2]),
    "dome": strong(key(DOME_KEY), SAT[3]),
    "spots": rgb(255, 252, 246),
    "ramp": strong(TH["butter"], 0.6),
    "turret_cap": strong(key(CAP_KEYS[1]), SAT[1]),
    "glow": TH["goo_hi"],
    "vine": strong(TH["goo"], 0.5),
}
STAND_TRIM = C.LILAC          # the plot colour on the stands' dish: the same in every theme
EXTRA = PC.THEME_PIECES[THEME]
REPLACED = {rep for _, _, _, rep in EXTRA if rep}

objs = []                      # every object in the scene
shell_room, shell_turret = [], []


def piece(name, parts, role=None, shell=None):
    """Join a piece's parts into one object (one MeshPart), tint it, remember it for the cut."""
    parts = [p for p in parts if p is not None]
    if not parts:
        return None
    o = C.join(name, parts)
    apply_transforms(o)
    if role is not None:
        t = ROLE[role]
        # multiply in sRGB, as picked (the attribute stores sRGB bytes; .color would be linear)
        for d in o.data.color_attributes["Col"].data:
            c = d.color_srgb
            d.color_srgb = (c[0] * t[0], c[1] * t[1], c[2] * t[2], c[3])
    objs.append(o)
    if shell == "room":
        shell_room.append(o)
    elif shell == "turret":
        shell_turret.append(o)
    return o


def rescale(o, dz, k, z_about):
    """Move a mesh up by dz, then scale it uniformly by k about (0, 0, z_about), the way the game fits a slot."""
    for v in o.data.vertices:
        v.co.z += dz
        v.co.x *= k
        v.co.y *= k
        v.co.z = z_about + (v.co.z - z_about) * k


def on_cap(o, f, native=PC.CAP_NATIVE):
    """Fit a mesh built on cap `native` onto eave cap f (or the dome rim of top floor f)."""
    ze = floor_top(f) + L.CAP_UNDER + 0.8
    rescale(o, floor_top(f) - floor_top(native), L.eave_r(f) / L.eave_r(native), ze)


def on_dome(o, f):
    """Fit a mesh built on floor 4's dome onto top floor f's dome."""
    rescale(o, floor_top(f) - floor_top(PC.DOME_NATIVE_FLOOR), L.eave_r(f) / L.eave_r(PC.DOME_NATIVE_FLOOR),
            floor_top(f) + L.CAP_UNDER)


def bisect(o, co, no):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no, clear_outer=True)
    bm.to_mesh(o.data)
    bm.free()


# ---- ground: the plot floor, moat and bridge (stands in for the reused goo_jar_foot) ----
C.plot_foot(moat=True, door_r=L.room_out(1))
for f in range(1, FLOORS + 1):
    z = floor_top(f)
    top = f == FLOORS
    for p in L.PADS:
        if p["floor"] == f:
            C.stand(f"Pad{p['j']}", p["x"], p["y"], z, trim=STAND_TRIM)
    if COLL:
        continue
    piece(f"pagoda_room_{f}", PC.room(f), "stalk", shell="room")
    if f > 1:
        piece(f"pagoda_deck_{f}", PC.deck(f), "wood")
    piece(f"pagoda_lamps_{f}", PC.lamps(f), "glow")
    for name, kind, fn, rep in EXTRA:
        if kind == "climber":
            for a in PC.CLIMBER_ANGLES[f]:
                piece(f"{name}_{f}_{a:.0f}", fn(f, a), None, shell="room")
        elif kind == "rim":
            on_cap(piece(f"{name}_{f}", fn(), None, shell="room"), f)
    if not top:
        piece(f"pagoda_cap_{f}_mid", PC.cap_mid(f), f"cap_{f}", shell="room")
        if "pagoda_spots_mid" not in REPLACED:
            on_cap(piece(f"pagoda_spots_mid_{f}", PC.spots_mid(), "spots", shell="room"), f)
        for name, kind, fn, rep in EXTRA:
            if kind == "cap":
                on_cap(piece(f"{name}_{f}", fn(), None, shell="room"), f)
        piece(f"pagoda_turret_mid_{f}", PC.turret_storey(f, False), "stalk", shell="turret")
        piece(f"pagoda_ramp_{f}", PC.ramp(f), "ramp")
    else:
        on_dome(piece("pagoda_dome", PC.dome(), "dome", shell="room"), f)
        if "pagoda_dome_spots" not in REPLACED:
            on_dome(piece("pagoda_dome_spots", PC.dome_spots(), "spots", shell="room"), f)
        for name, kind, fn, rep in EXTRA:
            if kind == "dome":
                on_dome(piece(name, fn(), None, shell="room"), f)
        piece("pagoda_turret_top", PC.turret_storey(f, True), "stalk", shell="turret")
        piece("pagoda_turret_cap", PC.turret_cap(f), "turret_cap", shell="turret")
        k = L.eave_r(f) / L.eave_r(PC.DOME_NATIVE_FLOOR)
        crown = (PC.dome_top()[-1][1] - floor_top(PC.DOME_NATIVE_FLOOR) - L.CAP_UNDER) * k + floor_top(f) + L.CAP_UNDER
        C.mascot(0, 0, crown - 0.3, s=4.2)
        if f > 1:
            piece(f"pagoda_vine_{f}", PC.vine(f), "vine")

# ---- floor 1 front ----
z1 = floor_top(1)
if not COLL:
    piece("pagoda_door", PC.door(), "wood")
    piece("pagoda_door_ring", PC.door_ring(), None, shell="room")
    foot = [e for e in EXTRA if e[1] == "foot"]
    piece("pagoda_foot_decor", foot[0][2]() if foot else PC.foot_decor_classic(), None)
C.vat(L.VAT["x"], L.VAT["y"], z1)
C.lock_button(L.LOCK_BUTTON["x"], L.LOCK_BUTTON["y"], z1)
C.avatar(*L.SPAWN, z1)
C.avatar(4, -L.room_out(1) - 6, 1.0, rgb(230, 120, 90))
if COLL:
    coll = []
    build_colliders(L, coll.append)
    for i, (o, spec) in enumerate(zip(coll, L.COLLIDERS)):
        apply_transforms(o)
        if spec["role"] in ("deck", "landing"):
            # preview only: overlapping deck boxes share their top plane; nudge them apart so the render doesn't flicker
            dz = -0.03 * (i % 4) - (0.12 if spec["kind"] == "cyl" else 0.0)
            for v in o.data.vertices:
                v.co.z += dz
        if CUT and spec["role"] not in ("deck", "landing", "ramp", "turret post", "lock", "door"):
            xs = [v.co for v in o.data.vertices]
            cx = sum(v.x for v in xs) / len(xs)
            cy = sum(v.y for v in xs) / len(xs)
            if math.hypot(cx - L.TURRET_C[0], cy - L.TURRET_C[1]) < L.TURRET_OUT + 0.6:
                bisect(o, (0, L.TURRET_C[1], 0), (1, 0, 0))
            else:
                bisect(o, (0, 0, 0), (0, -1, 0))
        C.contents.append(o)

# ---- cut-away and ship ----
if CUT and not COLL:
    for o in shell_room:
        bisect(o, (0, 0, 0), (0, -1, 0))
    for o in shell_turret:
        bisect(o, (0, L.TURRET_C[1], 0), (1, 0, 0))
C.ship("_base_pagoda_design", turn=0)
mat = vcol_material("pagoda_vcol")
for o in objs:
    o.data.materials.clear()
    o.data.materials.append(mat)
    o.data.color_attributes.active_color = o.data.color_attributes["Col"]
for o in bpy.context.scene.objects:
    if o.type == "MESH" and TURN:
        o.rotation_euler.z += math.radians(TURN)
bpy.context.view_layer.update()
