# habitat_prop_king: a small red-and-gold throne (King slime's signature prop, front of the habitat rim).
from models._habitat_prop3 import *

RED, RED_LO = rgb(222, 48, 58), rgb(170, 30, 48)
parts = []
W, D = 1.2, 0.85
# gold legs + seat frame
for i, (x, y) in enumerate([(-0.5, -0.33), (0.5, -0.33), (-0.5, 0.33), (0.5, 0.33)]):
    parts.append(cylinder(f"Leg{i}", 0.09, 0.36, (x, y, 0), GOLD_LO, segs=6, r_top=0.07))
seat = box("Seat", (W, D, 0.16), (0, 0, 0.42), GOLD)
bevel(seat, 0.04)
parts.append(seat)
cush = box("Cushion", (W - 0.16, D - 0.12, 0.14), (0, -0.02, 0.55), RED)
bevel(cush, 0.05)
parts.append(grad(cush, RED_LO, RED))
# back: gold frame with a red panel and a pointed top
back = prism("Back", [(-0.6, 0.45), (0.6, 0.45), (0.6, 1.1), (0.3, 1.2), (0, 1.33), (-0.3, 1.2), (-0.6, 1.1)],
             0.3, 0.44, GOLD)
parts.append(grad(back, GOLD_LO, GOLD))
panel = prism("Panel", [(-0.46, 0.62), (0.46, 0.62), (0.46, 1.04), (0.22, 1.11), (0, 1.2), (-0.22, 1.11), (-0.46, 1.04)],
              0.25, 0.31, RED)
parts.append(grad(panel, RED_LO, RED))
# gold post knobs and a little crown badge on the panel
for i, x in enumerate((-0.6, 0.6)):
    parts.append(cylinder(f"Post{i}", 0.08, 0.75, (x, 0.37, 0.45), GOLD, segs=6))
    parts.append(blob(f"Knob{i}", 0.11, (x, 0.37, 1.24), GOLD, subdiv=1, jitter=0))
parts.append(blob("Jewel", 0.08, (0, 0.27, 1.12), rgb(80, 170, 255), subdiv=1, jitter=0, squash=(1, 0.6, 1)))
crown = prism("Crown", [(-0.2, 0.78), (0.2, 0.78), (0.2, 0.96), (0.12, 0.88), (0, 0.98), (-0.12, 0.88), (-0.2, 0.96)],
              0.21, 0.26, GOLD)
parts.append(crown)
# armrests
for i, s in enumerate((-1, 1)):
    arm = box(f"Arm{i}", (0.12, D - 0.1, 0.1), (s * 0.58, 0.0, 0.8), GOLD)
    bevel(arm, 0.03)
    parts.append(arm)
    parts.append(cylinder(f"ArmPost{i}", 0.05, 0.3, (s * 0.58, -0.3, 0.5), GOLD_LO, segs=6))
    parts.append(blob(f"ArmKnob{i}", 0.08, (s * 0.58, -0.36, 0.82), GOLD, subdiv=1, jitter=0))
ship("habitat_prop_king", parts)
