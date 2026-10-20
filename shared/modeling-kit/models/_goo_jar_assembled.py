# Preview (not an asset): the goo jar tower as the GAME will show it, at version JAR_V (1..4), open or locked
# (JAR_LOCKED=1). Every piece is the same builder as its game mesh (models/_goo_jar.py), placed at the game's own
# coordinates from inputs/goo_jar_dims.json, on the plot's square Base. Compare with models/_goo_jar_tower_scene.py
# (the approved design). The glass previews as a transparent part (rbx_transparency = the game's glass transparency).
import math
import os
import random

import bpy

from models._goo_jar import *

V = int(os.environ.get("JAR_V", "4"))
LOCKED = os.environ.get("JAR_LOCKED", "0") == "1"
SLIME_COLS = [PINK, LILAC, BUTTER, GOO, rgb(120, 190, 250), rgb(250, 160, 90)]
R = random.Random(5)
solid, glass = [], []


def place(objs, dx=0.0, dy=0.0, dz=0.0, rz=0.0, scale=1.0, into=None):
    for o in objs:
        o.scale = (scale, scale, scale)
        o.rotation_euler.z += math.radians(rz)
        c, s = math.cos(math.radians(rz)), math.sin(math.radians(rz))
        o.location = (dx, dy, dz)
        (solid if into is None else into).append(o)
        if rz:
            # parts are built round the origin: turn their placement offset with them
            o.location = (dx, dy, dz)
    return objs


def top(f):
    return D["floors"][f - 1]["top"]


# The plot's square Base (80 x 80, top at the plot floor), sand coloured like the plaza.
half = D["plotSize"] / 2
place([painted(box("Base", (2 * half, 2 * half, 1.0), (0, 0, 0.5), P["ranch_plaza"]), shade(P["ranch_plaza"], 0.92), P["ranch_plaza"])])
place(jar_foot(), dz=top(1))
# the bridge over the moat to the door
bw = D["bridgeWidth"]
m = D["moat"]
place([painted(box("Bridge", (bw, m["outer"] - radius(1) + 2.0, 0.6), (0, -(radius(1) + m["outer"]) / 2 - 0.5, top(1) + 0.3), WOOD), shade(WOOD, 0.88), WOOD)])

for f in range(1, V + 1):
    is_top = f == V
    place(jar_glass(f, is_top), dz=top(f), into=glass)
    place(jar_trim(f, is_top, crown=is_top and V >= FLOORS), dz=top(f))
    if f >= 2:
        place(jar_deck(f), dz=top(f))
    if f < V:
        rz = D["floors"][f - 1]["treads"][0] - D["floors"][0]["treads"][0]
        place(jar_stair(), dz=top(f), rz=rz)
    for k, pad in enumerate(D["floors"][f - 1]["pads"]):
        place(cork_stand(), dx=pad["x"], dy=pad["z"], dz=top(f), rz=90 - pad["angle"])
        if R.random() < 0.85:
            col = SLIME_COLS[(f * 8 + k) % len(SLIME_COLS)]
            place([painted(blob(f"Slime{f}{k}", 1.7, (pad["x"], pad["z"], top(f) + D["padSeatY"] + 1.33), col, subdiv=2,
                                squash=(1, 1, 0.78), jitter=0.02), shade(col, 0.82), col)])

# door, lock ring, stopper (plugged while locked, parked beside the door while open), lock button in the back bay
place(jar_door(), dz=top(1))
ring = jar_door_ring()
for o in ring:
    gradient(o, RED if LOCKED else METAL, RED if LOCKED else METAL)
place(ring, dz=top(1))
cx, cy, cz = door_center()
if LOCKED:
    place(jar_stopper(), dx=0, dy=cy + 0.3, dz=top(1) + cz - 4.6)
else:
    place(jar_stopper(), dx=8.5, dy=cy - 3.2, dz=top(1))
bx, bz = D["lockButtonSpot"]
place(lock_button(), dx=bx, dy=bz, dz=top(1))

# merge vat (its own kit mesh in the game; a stand-in barrel here)
va = math.radians(D["vatSpot"]["angle"])
vr = D["vatSpot"]["radius"]
place([painted(cylinder("Vat", 4.5, 3.6, (vr * math.cos(va), vr * math.sin(va), top(1)), WOOD, segs=20), shade(WOOD, 0.85), WOOD)])
if V >= 2:
    place(drop_tube_glass(V), dz=top(1) - 1.0, into=glass)
    place(drop_tube_goo(V), dz=top(1) - 1.0)

# the mascot on the top lid, crowned at the last version
lid_top = top(V) + neck_z(V, True) + LIP + (LID_H if V >= FLOORS else CORK_H)
s = mascot_size(V)
place(mascot(), dz=lid_top, scale=s)
if V >= FLOORS:
    place(crown(), dz=lid_top + s * 1.45, scale=s)

mat = vcol_material("jar_vcol")
for name, objs, t in (("goo_jar_assembled", solid, None), ("goo_jar_assembled_glass", glass, D["glassTransparency"])):
    for o in objs:
        bpy.context.view_layer.objects.active = o
    o = join(name, objs)
    apply_transforms(o)
    o.data.materials.clear()
    o.data.materials.append(mat)
    if "Col" in o.data.color_attributes:
        o.data.color_attributes.active_color = o.data.color_attributes["Col"]
    if t:
        o["rbx_transparency"] = t
    o.rotation_euler.z = math.radians(float(os.environ.get("JAR_TURN", "-20")))
