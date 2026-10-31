# habitat_prop_ninja: a straw training dummy on a wooden post: rope bands, arm pegs, red headband, target.
from models._habitat_prop5 import *

STRAW, STRAW_HI = rgb(226, 182, 92), rgb(252, 222, 140)
ROPE = rgb(150, 86, 50)
WOOD, WOOD_D = P["ranch_wood"], P["ranch_wood_dark"]
RED = rgb(230, 46, 56)
parts = [
    gbox("BaseA", (0.9, 0.22, 0.12), (0, 0, 0.06), WOOD_D, WOOD, bev=0.03),
    gbox("BaseB", (0.22, 0.9, 0.12), (0, 0, 0.06), WOOD_D, WOOD, bev=0.03),
    gcyl("Post", 0.08, 0.5, (0, 0, 0.1), WOOD_D, WOOD, segs=6),
    gcyl("Body", 0.25, 0.5, (0, 0, 0.45), STRAW, STRAW_HI, segs=10, r_top=0.22),
]
for i, z in enumerate((0.55, 0.85)):
    parts.append(gcyl(f"Band{i}", 0.265 - 0.02 * i, 0.06, (0, 0, z), ROPE, segs=10))
for sx in (-1, 1):
    parts.append(tube(f"Arm{sx}", [(sx * 0.18, 0, 0.82), (sx * 0.58, -0.04, 0.9)], [0.07, 0.06], WOOD, segs=6))
parts.append(gcyl("Neck", 0.1, 0.08, (0, 0, 0.95), ROPE, segs=8))
parts.append(gradient(blob("Head", 0.22, (0, 0, 1.12), STRAW_HI, subdiv=2, jitter=0.03, squash=(1, 1, 1.05)), STRAW, STRAW_HI))
parts.append(gcyl("Band", 0.225, 0.08, (0, 0, 1.1), RED, segs=12))
parts.append(slab("Tail1", [(0, 0), (0.28, -0.08), (0.3, 0.0), (0.05, 0.06)], 0.04, RED, (0.12, 0.2, 1.11), rot_z=-60))
parts.append(slab("Tail2", [(0, 0), (0.24, -0.16), (0.27, -0.09), (0.05, 0.05)], 0.04, RED, (0.12, 0.2, 1.11), rot_z=-40))
parts.append(slab("Target", circle_pts(0.1, 10, cz=0.68), 0.03, RED, (0, -0.245, 0)))
parts.append(slab("TargetIn", circle_pts(0.045, 8, cz=0.68), 0.03, rgb(255, 245, 230), (0, -0.265, 0)))
ship("habitat_prop_ninja", parts)
