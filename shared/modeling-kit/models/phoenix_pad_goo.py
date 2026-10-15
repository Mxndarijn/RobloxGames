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
parts.append(blob("Spill", 0.9, (3.45, 0.6, 1.4), GOO, subdiv=2, squash=(0.6, 1.0, 0.7), jitter=0.05))
parts.append(blob("Spill2", 0.55, (3.65, 0.7, 0.85), GOO, subdiv=2, squash=(0.6, 0.9, 1.2), jitter=0.05))
finish("phoenix_pad_goo", parts)
