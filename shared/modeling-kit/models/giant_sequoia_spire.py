# giant_sequoia_spire: border v6 giant, a towering sequoia-like spire (~50 x 50 x 152): a very thick
# red-brown trunk with fluted roots under a tall tapering crown of nine drooping tiers.
import math, random
from lib import *
from models._giant_tree import *
from models._border_v3 import FIR_D

R = random.Random(602)
parts = [limb("Trunk", [(0, 0, -0.6), (0.5, 0.3, 22), (0.2, 0.9, 50), (0, 0.5, 78), (0, 0, 138)], [10.5, 8.2, 6.4, 4.6, 1.6], R, segs=8)]
for k in range(5):
    a = k * math.tau / 5 + R.uniform(-0.3, 0.3)
    parts.append(limb(f"Root{k}", [(math.cos(a) * 14, math.sin(a) * 14, -0.8), (math.cos(a) * 8, math.sin(a) * 8, 3.5), (math.cos(a) * 3, math.sin(a) * 3, 13)],
                      [1.8, 2.6, 3.2], R, segs=5))
# crown: a drooping 9-tier cone lifted onto the trunk, so the lower 55 studs are bare red-brown trunk
import bpy
crown = conifer("Sky", 0.0, 0.0, 100.0, R, tiers=9, tips=10, spread=0.27, shape=0.82, trunk=0.7, dark=shade(FIR_D, 0.95))
for o in crown:
    if o.name.endswith("Trunk"):
        bpy.data.objects.remove(o, do_unlink=True)
    else:
        o.location.z += 52
        parts.append(o)
finish("giant_sequoia_spire", parts)
