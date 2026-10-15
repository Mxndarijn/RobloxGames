# Preview (not an asset): one slime = body variant + accessory + face, body tinted like the game
# (MeshPart.Color x vertex colour). Env: SLIME_VARIANT, SLIME_FACE, SLIME_TINT=r,g,b.
import os
from models._slime import *

v = os.environ.get("SLIME_VARIANT", "slime_base")
rarity, body_parts, acc = VARIANTS[v]
t = [int(c) / 255 for c in os.environ.get("SLIME_TINT", ",".join(map(str, RARITY_RGB[rarity]))).split(",")]
bodies = body_parts()
for o in bodies:
    for d in o.data.color_attributes["Col"].data:
        c = d.color
        d.color = (c[0] * t[0], c[1] * t[1], c[2] * t[2], 1.0)
parts = bodies + (acc() if acc else []) + face(os.environ.get("SLIME_FACE", "default"))
o = finish("slime_preview", parts)
a = o.data.attributes["keep_smooth"]
for p, d in zip(o.data.polygons, a.data):
    p.use_smooth = bool(d.value)
o.data.attributes.remove(a)
