# habitat_prop_snow_bunny: a small wooden sled side-on to the walkway: red runners curling up at the front, wooden
# slats on top, a rope loop.
import math
from models._habitat_prop3 import *

RUN, RUN_LO = rgb(232, 62, 62), rgb(186, 44, 52)
SLAT, SLAT_LO = rgb(220, 160, 98), rgb(176, 120, 72)
ROPE = rgb(240, 220, 170)
parts = []
L = 1.4  # sled length along X; the curl is at +X
for s in (-1, 1):
    y = s * 0.32
    # runner path: flat along the snow, then curling up and back over itself at the front
    pts = [(-L / 2, y, 0.06), (L / 2 - 0.22, y, 0.06)]
    for j in range(1, 7):
        a = -math.pi / 2 + j * math.pi * 1.25 / 6
        pts.append((L / 2 - 0.22 + math.cos(a) * 0.22, y, 0.28 + math.sin(a) * 0.22))
    parts.append(tube(f"Runner{s}", pts, [0.055] * len(pts), RUN, segs=5, twist_free=True))
    # struts from runner to deck
    for i, x in enumerate((-0.5, -0.05, 0.4)):
        parts.append(box(f"Strut{s}{i}", (0.07, 0.06, 0.22), (x, y, 0.19), RUN_LO))
# deck slats across the runners
for i in range(6):
    x = -L / 2 + 0.12 + i * 0.2
    sl = box(f"Slat{i}", (0.15, 0.82, 0.06), (x, 0, 0.33), SLAT if i % 2 else shade(SLAT, 1.06))
    bevel(sl, 0.015)
    parts.append(grad(sl, SLAT_LO, SLAT))
for s in (-1, 1):  # side rails tying the slats
    parts.append(box(f"Rail{s}", (L - 0.25, 0.06, 0.05), (-0.08, s * 0.38, 0.385), SLAT_LO))
# rope loop from the curl tips, hanging forward
rope = [(L / 2 - 0.1, -0.32, 0.42)] + [(L / 2 + 0.05 + 0.08 * math.sin(math.pi * t / 6), -0.32 + 0.64 * t / 6, 0.36 - 0.1 * math.sin(math.pi * t / 6)) for t in range(7)] + [(L / 2 - 0.1, 0.32, 0.42)]
parts.append(tube("Rope", rope, [0.025] * len(rope), ROPE, segs=4))
ship("habitat_prop_snow_bunny", parts)
