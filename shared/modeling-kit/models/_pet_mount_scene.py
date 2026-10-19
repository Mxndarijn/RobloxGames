# Preview (not an asset): pet mount(s) at in-game scale, each with a tier-3 slime on top (as _pet_cloud_scene.py).
# Env: PM_NAME=<mount> (or PM_NAME=all for a lineup), PM_PET=1 adds the slime(s). In game: mount x0.9, slime x0.55, foot sunk 0.12.
import os
from models._pet_mounts import *
from models._slime import VARIANTS, RARITY_RGB, face as slime_face

MOUNT_SCALE, PET_SCALE, SINK = 0.9, 0.55, 0.12


def pet_parts():
    rarity, body_parts, acc = VARIANTS["slime_ears"]  # tier 3 = Rare: round goo ears
    t = [c / 255 for c in RARITY_RGB[rarity]]
    bodies = body_parts()
    for o in bodies:
        for d in o.data.color_attributes["Col"].data:
            c = d.color
            d.color = (c[0] * t[0], c[1] * t[1], c[2] * t[2], 1.0)
    return bodies + slime_face("happy")


def placed(name, x=0.0, y=0.0, pet=True):
    """the shipped mount (same mesh as the FBX), scaled, moved to x, with a slime sitting on its seat."""
    m = ship("pm_" + name, MOUNTS[name](), fit=name not in NOFIT)
    seat = seat_z(m)
    m.scale = (MOUNT_SCALE,) * 3
    m.location = (x, y, 0)
    bpy.context.view_layer.update()
    paint_attr_smooth(m, True)
    out = [m]
    if pet:
        slime = pet_parts()
        for o in slime:
            o.scale = (PET_SCALE,) * 3
            o.location = (x, y, seat * MOUNT_SCALE - SINK)
            if "keep_smooth" not in o.data.attributes:
                paint_attr_smooth(o, False)
        out += slime
    return out


names = list(MOUNTS) if os.environ.get("PM_NAME") == "all" else [os.environ["PM_NAME"]]
pet = bool(os.environ.get("PM_PET"))
parts = []
for i, n in enumerate(names):
    col, row = i % 4, i // 4
    parts += placed(n, x=(col - (min(len(names), 4) - 1) / 2) * 3.5 if len(names) > 1 else 0.0, y=row * 3.2, pet=pet)
o = finish("pet_mount_scene", parts)
a = o.data.attributes.get("keep_smooth")
if a:
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
# pitch the scene toward the camera so the seat (and the pet's feet) show in the 3/4 view (PM_TILT degrees, default 20)
import math
o.rotation_euler = (math.radians(float(os.environ.get("PM_TILT", "20"))), 0, 0)
bpy.context.view_layer.update()
