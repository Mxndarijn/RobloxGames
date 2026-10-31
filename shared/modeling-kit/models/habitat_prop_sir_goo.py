# habitat_prop_sir_goo: a wooden weapon rack holding a sword, a round knight's shield leaning on it.
from models._habitat_prop3 import *

STEEL, STEEL_LO = rgb(226, 236, 248), rgb(160, 176, 198)
BLUE, BLUE_LO = rgb(56, 120, 230), rgb(40, 86, 186)
GRIP = rgb(120, 70, 44)
parts = []
# rack: two posts on feet, two crossbars
for i, x in enumerate((-0.72, 0.72)):
    p = box(f"Post{i}", (0.12, 0.12, 1.1), (x, 0.25, 0.55), WOOD)
    bevel(p, 0.025)
    parts.append(grad(p, WOOD_LO, WOOD))
    f = box(f"Foot{i}", (0.18, 0.6, 0.1), (x, 0.2, 0.05), WOOD_LO)
    bevel(f, 0.025)
    parts.append(f)
    parts.append(blob(f"Cap{i}", 0.09, (x, 0.25, 1.13), WOOD, subdiv=1, jitter=0))
for i, z in enumerate((0.45, 0.95)):
    b = box(f"Bar{i}", (1.56, 0.1, 0.1), (0, 0.25, z), WOOD)
    bevel(b, 0.02)
    parts.append(b)
# sword standing point-down against the rack, left of centre
sx, sy = -0.32, 0.12
blade = prism("Blade", [(-0.075, 0.18), (0, 0.04), (0.075, 0.18), (0.075, 0.95), (-0.075, 0.95)], sy - 0.025, sy + 0.025, STEEL)
parts.append(grad(blade, STEEL_LO, STEEL))
for k, x0 in enumerate((sx,)):
    xf(blade, (x0, 0, 0))
parts.append(box("Fuller", (0.03, 0.06, 0.68), (sx, sy, 0.6), STEEL_LO))
guard = box("Guard", (0.42, 0.1, 0.08), (sx, sy, 0.99), GOLD)
bevel(guard, 0.02)
parts.append(guard)
parts.append(cylinder("Grip", 0.045, 0.24, (sx, sy, 1.02), GRIP, segs=6))
parts.append(blob("Pommel", 0.07, (sx, sy, 1.3), GOLD, subdiv=1, jitter=0))
# round shield leaning back against the rack, right of centre
sh = lathe("Shield", [(0, -0.05), (0.42, -0.04), (0.44, 0.0), (0.4, 0.05), (0.18, 0.08), (0, 0.09)], segs=14,
           color_fn=lambda i, k, z: GOLD if i in (1, 2) else (BLUE if k % 2 == 0 or i == 0 else rgb(240, 244, 255)))
xf(sh, (0.36, -0.08, 0.5), (75, 0, 0))
parts.append(sh)
parts.append(xf(blob("Boss", 0.11, (0, 0, 0), GOLD, subdiv=1, jitter=0, squash=(1, 1, 0.6)), (0.36, -0.17, 0.52), (75, 0, 0)))
ship("habitat_prop_sir_goo", parts)
