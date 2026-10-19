# Preview (not an asset): the pet_cloud at its in-game scale, alone or with a tier-3 slime on top.
# Env: PC_PET=1 adds the slime, PC_TOP=1 turns the scene so the top faces the front camera (a straight top-down view).
# In game: cloud x0.9 (FollowPets.CLOUD_SCALE), slime x0.55 (FollowPets.SCALE), foot sunk 0.12 into the top.
import os
from models._pet_cloud import cloud_parts
from models._slime import *

CLOUD_SCALE, PET_SCALE, SINK = 0.9, 0.55, 0.12
parts = cloud_parts()
for o in parts:
    o.scale = (CLOUD_SCALE,) * 3
if os.environ.get("PC_PET"):
    rarity, body_parts, acc = VARIANTS["slime_ears"]  # tier 3 = Rare: round goo ears
    t = [c / 255 for c in RARITY_RGB[rarity]]
    bodies = body_parts()
    for o in bodies:
        for d in o.data.color_attributes["Col"].data:
            c = d.color
            d.color = (c[0] * t[0], c[1] * t[1], c[2] * t[2], 1.0)
    slime = bodies + face("happy")
    for o in slime:
        o.scale = (PET_SCALE,) * 3
        o.location.z = 1.225 * CLOUD_SCALE - SINK
    parts += slime
o = finish("pet_cloud_scene", parts)
a = o.data.attributes.get("keep_smooth")
if a:
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
if os.environ.get("PC_TOP"):
    import math
    o.rotation_euler = (math.pi / 2, 0, 0)
    bpy.context.view_layer.update()
