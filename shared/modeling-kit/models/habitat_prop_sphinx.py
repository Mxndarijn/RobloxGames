# habitat_prop_sphinx: a small stepped sandstone pyramid with blue-striped step faces and a shiny gold capstone.
from models._habitat_prop5 import *

SAND, SAND_HI = rgb(236, 192, 120), rgb(255, 226, 160)
BLUE = rgb(60, 150, 255)
GOLD, GOLD_HI = rgb(255, 196, 60), rgb(255, 240, 150)

parts = []
steps = [(1.5, 1.08), (1.16, 0.84), (0.84, 0.62), (0.54, 0.42)]
H = 0.22
for i, (w, d) in enumerate(steps):
    z = i * H
    parts.append(gbox(f"Step{i}", (w, d, H), (0, 0, z + H / 2), SAND, SAND_HI, bev=0.03))
    parts.append(gbox(f"Stripe{i}", (w * 0.7, 0.03, 0.06), (0, -d / 2 - 0.005, z + H * 0.5), BLUE, bev=0))
TOPZ = len(steps) * H
parts.append(gradient(cone("Cap", 0.3, 0.42, (0, 0, TOPZ), GOLD, segs=4, rot=(0, 0, 45)), GOLD, GOLD_HI))
parts.append(slab("Glint", star_pts(4, 0.1, 0.03, cx=0.09, cz=TOPZ + 0.2), 0.02, rgb(255, 255, 230), (0, -0.12, 0)))
ship("habitat_prop_sphinx", parts)
