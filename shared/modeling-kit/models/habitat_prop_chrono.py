# habitat_prop_chrono: a small grandfather clock: wooden case, arched hood, big white face, gold pendulum.
import math
from models._habitat_prop3 import *

CASE, CASE_LO = rgb(186, 112, 64), rgb(138, 78, 46)
FACE = rgb(255, 250, 236)
INK = rgb(60, 48, 70)
parts = []
plinth = box("Plinth", (0.7, 0.5, 0.16), (0, 0, 0.08), CASE_LO)
bevel(plinth, 0.03)
parts.append(plinth)
body = box("Body", (0.56, 0.4, 0.72), (0, 0, 0.52), CASE)
bevel(body, 0.03)
parts.append(grad(body, CASE_LO, CASE))
# pendulum window: dark glass with a gold rod + disc
parts.append(box("Window", (0.32, 0.04, 0.5), (0, -0.2, 0.52), rgb(80, 60, 92)))
parts.append(box("Rod", (0.03, 0.03, 0.34), (0, -0.225, 0.58), GOLD_LO))
parts.append(xf(cylinder("Bob", 0.09, 0.04, (0, 0, -0.02), GOLD, segs=10), (0, -0.23, 0.4), (90, 0, 0)))
# hood: wider box with an arched top
hood = box("Hood", (0.7, 0.48, 0.42), (0, 0, 1.08), CASE)
bevel(hood, 0.03)
parts.append(grad(hood, CASE, rgb(206, 132, 80)))
arch = prism("Arch", [(-0.35 + 0.7 * j / 8, 1.29 + 0.09 * math.sin(math.pi * j / 8)) for j in range(9)] + [(0.35, 1.27), (-0.35, 1.27)],
             -0.22, 0.22, CASE_LO)
parts.append(arch)
parts.append(blob("Finial", 0.06, (0, 0, 1.38) , GOLD, subdiv=1, jitter=0))
parts.append(cylinder("Base", 0.4, 0.04, (0, 0, 0.86), CASE_LO, segs=4, rot=(0, 0, 45)))
# clock face: gold bezel, white dial, hour ticks and two hands
parts.append(xf(cylinder("Bezel", 0.26, 0.04, (0, 0, 0), GOLD, segs=16), (0, -0.24, 1.08), (90, 0, 0)))
parts.append(xf(cylinder("Dial", 0.22, 0.04, (0, 0, 0), FACE, segs=16), (0, -0.26, 1.08), (90, 0, 0)))
for k in range(12):
    a = k / 12 * math.tau
    s = 0.04 if k % 3 == 0 else 0.025
    parts.append(box(f"Tick{k}", (s, 0.02, s), (math.sin(a) * 0.17, -0.3, 1.08 + math.cos(a) * 0.17), INK))
parts.append(box("HandH", (0.035, 0.02, 0.11), (0.03, -0.31, 1.12), INK, rot=(0, 30, 0)))
parts.append(box("HandM", (0.025, 0.02, 0.16), (-0.05, -0.315, 1.1), INK, rot=(0, -70, 0)))
parts.append(xf(cylinder("Pin", 0.03, 0.03, (0, 0, 0), GOLD, segs=6), (0, -0.3, 1.08), (90, 0, 0)))
parts = [xf(o, scale=(1, 1, 0.94)) for o in parts]  # keep it under the 1.4 prop height
ship("habitat_prop_chrono", parts)
