# phoenix_pad_goo: goo puddle bowl, 7.8 diameter wood tub with goo surface at z=1.5 (slime sits in goo).
import math
from lib import *
from models._phoenix_ranch import *
parts = []
N = 14
for i in range(N):
    a = i * math.tau / N
    parts.append(bbox(f"Stave{i}", (1.75, 0.5, 1.8 + 0.1 * (i % 2)), (math.cos(a) * 3.6, math.sin(a) * 3.6, 0.92),
                      shade(WOOD, 0.85), WOOD if i % 2 else shade(WOOD, 0.95), bev=0.08, rot=(0, 0, math.degrees(a) + 90)))
for k, z in enumerate((0.35, 1.05)):  # r03: solid hoop discs (cap) covered the goo -> grey top; keep hoops below goo line
    c = cylinder(f"Hoop{k}", 3.92, 0.25, (0, 0, z), P["ranch_metal"], segs=14)
    parts.append(c)
g = cylinder("Goo", 3.45, 1.6, (0, 0, 0), GOO, segs=14)
gradient(g, shade(GOO, 0.8), GOO); parts.append(g)
# r02: a pale goo_hi dome read grey under the Roblox sky; use bright goo surface + small highlight blobs
parts.append(blob("GooDome", 3.2, (0, 0, 1.55), GOO, subdiv=2, squash=(1, 1, 0.1), jitter=0.0))
for k,(x,y) in enumerate(((-1.2,0.8),(1.0,-1.3),(0.3,1.6))):
    parts.append(blob(f"Bub{k}", 0.35, (x, y, 1.85), GOO_HI, subdiv=1, squash=(1,1,0.6), jitter=0, seed=k))
# spill: goo sliding over the rim at one side (r04: pulled in 0.3 so footprint <=8.0)
# fix 2026-10-16: the two icosphere spill blobs read as a lumpy clump; one metaball lip roll + short drip
# down the stave face (ends above the upper hoop, stays inside the 7.86 footprint) fuses into the rim.
from lib.goo import Ball, metaball_mesh, paint_goo
balls = [Ball((3.35, 0.6, 1.8), (0.6, 0.55, 0.13)), Ball((3.78, 0.62, 1.66), (0.14, 0.42, 0.2))]
for j, (z, w) in enumerate(((1.62, 0.4), (1.5, 0.33), (1.42, 0.27))):
    balls.append(Ball((3.86, 0.62 + 0.03 * j, z), (0.1, w, 0.16)))
balls.append(Ball((3.87, 0.7, 1.36), 0.2))
parts.append(paint_goo(metaball_mesh("Spill", balls, resolution=0.08, tris=240), lambda co, n: mix(GOO, GOO_HI, 0.12)))
finish("phoenix_pad_goo", parts)
