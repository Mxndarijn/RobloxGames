# ranch_lantern_post: wooden plaza lantern post with a soft goo-glow lantern (Slime Ranch).
# Square post on a foot, curved bracket arm, hanging pewter lantern with a pale goo-glow core.
# Not a torch: enclosed lantern, no flame. Medium prop, target < ~700 tris. cylinder() pos = base.
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL = PALETTE["ranch_cream"], PALETTE["ranch_metal"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
METAL_LO, METAL_HI = mix(METAL, WOOD_D, 0.15), mix(METAL, CREAM, 0.25)
parts = []

H = 9.0
# foot + post
parts.append(box("Foot", (1.6, 1.6, 0.5), (0, 0, 0.25), WOOD_LO)); bevel(parts[-1], 0.08)
gradient(parts[-1], WOOD_D, WOOD_LO)
parts.append(box("Post", (0.8, 0.8, H), (0, 0, H / 2), WOOD)); bevel(parts[-1], 0.08)
gradient(parts[-1], WOOD_LO, WOOD)
parts.append(box("Band", (0.92, 0.92, 0.3), (0, 0, 2.0), ROOF)); gradient(parts[-1], mix(ROOF_D, ROOF, .5), ROOF)
parts.append(box("Cap", (1.1, 1.1, 0.3), (0, 0, H + 0.15), ROOF)); bevel(parts[-1], 0.08)
gradient(parts[-1], mix(ROOF_D, ROOF, .5), ROOF)
# arm (+X) with brace
parts.append(box("Arm", (2.3, 0.4, 0.4), (1.4, 0, H - 0.6), WOOD)); gradient(parts[-1], WOOD_LO, WOOD)
parts.append(tube("Brace", [(0.4, 0, H - 2.0), (1.0, 0, H - 1.25), (1.7, 0, H - 0.8)], [0.13] * 3, METAL, segs=5))
gradient(parts[-1], METAL_LO, METAL_HI)
LX = 2.25
parts.append(cylinder("Hook", 0.06, 0.6, (LX, 0, H - 1.4), METAL, segs=5))
# lantern: base, glow core, 4 corner bars, roof cone, ring
LZ = H - 3.6
parts.append(cylinder("LBase", 0.55, 0.22, (LX, 0, LZ), METAL, segs=8)); gradient(parts[-1], METAL_LO, METAL)
parts.append(cylinder("Glow", 0.42, 1.3, (LX, 0, LZ + 0.22), GOO_HI, segs=8))
gradient(parts[-1], mix(GOO, GOO_HI, 0.5), GOO_HI)
for i, (sx, sy) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
    parts.append(box(f"Bar{i}", (0.1, 0.1, 1.3), (LX + sx * 0.36, sy * 0.36, LZ + 0.87), METAL))
parts.append(cylinder("LTop", 0.6, 0.18, (LX, 0, LZ + 1.52), METAL, segs=8)); gradient(parts[-1], METAL_LO, METAL_HI)
parts.append(cone("LRoof", 0.6, 0.55, (LX, 0, LZ + 1.7), ROOF, segs=8)); gradient(parts[-1], mix(ROOF_D, ROOF, .5), ROOF)
parts.append(cylinder("LRing", 0.12, 0.2, (LX, 0, LZ + 2.22), METAL, segs=5))
finish("ranch_lantern_post", parts)
