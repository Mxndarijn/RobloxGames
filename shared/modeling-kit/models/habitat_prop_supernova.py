# habitat_prop_supernova: a small brass telescope on a wooden tripod, tilted up at a bright bursting star.
import math
from mathutils import Vector
from models._habitat_prop5 import *
from models._habitat_prop4 import lathe, torus, paint, move

BRASS, BRASS_LO, BRASS_HI = rgb(250, 190, 60), rgb(232, 150, 40), rgb(255, 232, 140)
WOOD, WOOD_HI = rgb(196, 120, 64), rgb(228, 160, 96)
LENS = rgb(140, 218, 255)
STAR, STAR_HI = rgb(255, 200, 60), rgb(255, 245, 170)
PINK = rgb(255, 110, 170)

parts = []
HUB = Vector((-0.05, 0.05, 0.58))
for k, (x, y) in enumerate(((-0.52, 0.32), (0.42, 0.34), (-0.05, -0.42))):
    parts.append(gradient(rod(f"Leg{k}", (x, y, 0), HUB, 0.04, WOOD, segs=5), WOOD, WOOD_HI))
parts.append(blob("Hub", 0.08, HUB, BRASS_LO, subdiv=1, jitter=0))
# telescope tube: built along +Z, then tipped 50 deg toward +X (stays in the XZ plane, side-on to the walkway)
tube_ = lathe("Tube", [(0.07, -0.28), (0.085, -0.26), (0.085, 0.05), (0.11, 0.07), (0.11, 0.42), (0.14, 0.45),
                       (0.14, 0.52), (0.11, 0.53)], segs=10)
paint(tube_, lambda c, n: BRASS_HI if n.x < -0.3 else (BRASS if n.y < 0.2 else BRASS_LO))
eye = lathe("Eye", [(0.05, -0.38), (0.06, -0.28)], segs=8, color=BRASS_LO)
glass = gcyl("Lens", 0.11, 0.02, (0, 0, 0.52), LENS, segs=10)
bands = [torus(f"B{k}", 0.115, 0.02, seg=10, seg2=4, pos=(0, 0, z), color=BRASS_LO) for k, z in enumerate((0.12, 0.3))]
for p in [tube_, eye, glass] + bands:
    move(p, rot=(0, 50, 0))
    move(p, pos=HUB + Vector((0, 0, 0.06)))
    parts.append(p)
# the supernova: a star burst ahead of the lens
tip = HUB + Vector((0, 0, 0.06)) + Vector((math.sin(math.radians(50)), 0, math.cos(math.radians(50)))) * 0.82
parts.append(slab("Burst", star_pts(8, 0.2, 0.1, cx=tip.x, cz=tip.z), 0.05, PINK, (0, 0.02, 0)))
parts.append(slab("Star", star_pts(5, 0.15, 0.07, cx=tip.x, cz=tip.z), 0.1, STAR, (0, 0, 0), hi=STAR_HI))
ship("habitat_prop_supernova", parts)
