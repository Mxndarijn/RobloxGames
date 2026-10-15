# ranch_water_pump: cast hand pump on a wooden plinth, spout dripping into a goo puddle (Slime Ranch).
# Plinth + pewter barrel + curved handle + spout (+Y); puddle = flat closed disc painted goo.
# Small prop, target < 500 tris. cylinder() pos = base.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL = PALETTE["ranch_cream"], PALETTE["ranch_metal"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
METAL_LO, METAL_HI = mix(METAL, WOOD_D, 0.15), mix(METAL, CREAM, 0.25)
parts = []

parts.append(box("Plinth", (2.0, 2.0, 0.8), (0, -0.4, 0.4), WOOD)); bevel(parts[-1], 0.1)
gradient(parts[-1], WOOD_LO, WOOD)
parts.append(cylinder("Body", 0.42, 3.0, (0, -0.4, 0.8), ROOF, segs=8, r_top=0.36))
gradient(parts[-1], mix(ROOF_D, ROOF, .5), ROOF)
for i, z in enumerate((1.0, 3.5)):
    parts.append(cylinder(f"Ring{i}", 0.5, 0.2, (0, -0.4, z), METAL, segs=8)); gradient(parts[-1], METAL_LO, METAL_HI)
parts.append(cylinder("Top", 0.48, 0.25, (0, -0.4, 3.8), METAL, segs=8)); gradient(parts[-1], METAL_LO, METAL_HI)
parts.append(blob("Knob", 0.2, (0, -0.4, 4.15), METAL_HI, subdiv=1, jitter=0))
# spout toward +Y
parts.append(tube("Spout", [(0, -0.1, 3.0), (0, 0.5, 3.0), (0, 0.85, 2.7)], [0.16, 0.15, 0.13], METAL, segs=6))
gradient(parts[-1], METAL_LO, METAL_HI)
# handle toward -Y, angled up
parts.append(tube("Handle", [(0, -0.6, 3.75), (0, -1.4, 4.2), (0, -2.0, 4.0)], [0.1, 0.09, 0.09], METAL, segs=5))
gradient(parts[-1], METAL_LO, METAL_HI)
parts.append(blob("Grip", 0.16, (0, -2.05, 3.98), WOOD, subdiv=1, squash=(1, 1.6, 1), jitter=0))
# drip falling from spout
parts.append(blob("Drip", 0.2, (0, 0.9, 2.3), GOO, subdiv=1, squash=(0.8, 0.8, 1.5), jitter=0.02))
parts.append(blob("Drip2", 0.14, (0, 0.92, 1.6), GOO_HI, subdiv=1, jitter=0.02))
# puddle: closed thin disc with a raised wobbly edge, centred under the spout
PR, SEG = 1.8, 14
bm = bmesh.new()
top_c = bm.verts.new((0, 1.3, 0.2)); bot_c = bm.verts.new((0, 1.3, 0.0))
tops, bots = [], []
for i in range(SEG):
    a = 2 * math.pi * i / SEG
    r = PR * (1 + 0.14 * math.sin(3 * a) + 0.07 * math.cos(5 * a))
    x, y = r * math.cos(a), 1.3 + r * 0.8 * math.sin(a)
    tops.append(bm.verts.new((x, y, 0.1))); bots.append(bm.verts.new((x, y, 0.0)))
for i in range(SEG):
    j = (i + 1) % SEG
    bm.faces.new((top_c, tops[i], tops[j])); bm.faces.new((bot_c, bots[j], bots[i]))
    bm.faces.new((tops[i], bots[i], bots[j], tops[j]))
bm.normal_update()
layer = bm.loops.layers.color.new("Col")
for f in bm.faces:
    hi = top_c in f.verts
    col = mix(GOO, GOO_HI, 0.35) if hi else GOO
    for lp in f.loops:
        lp[layer] = (*col[:3], 1.0)
parts.append(obj_from_bm("Puddle", bm))
parts.append(blob("Bub", 0.14, (0.6, 1.6, 0.15), GOO_HI, subdiv=1, squash=(1, 1, 0.6), jitter=0.03))
finish("ranch_water_pump", parts)
