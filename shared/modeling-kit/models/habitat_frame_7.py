# habitat_frame_7 (Secret): craggy shadow stone. Dark violet-black blocks with slanted, uneven tops and deep seams,
# small rainbow gems inlaid round it (the game adds a rainbow-shimmer glow lip on the inside).
import math, random
from lib import *
from models._habitat_frame import *

SHADOW = rgb(45, 40, 60)
TOP = rgb(66, 58, 90)
SEAM = rgb(30, 26, 42)
RAINBOW = [rgb(255, 70, 80), rgb(255, 150, 40), rgb(255, 226, 60), rgb(80, 220, 100), rgb(60, 160, 255),
           rgb(180, 90, 255)]
R = random.Random(7)
N, GAP = 10, 0.1

parts = [arc_mesh("Seam", 0, 0, [(R_IN, 0), (R_IN, 0.12), (R_OUT, 0.12), (R_OUT, 0)], SEAM, segs=24, closed=True)]
for i in range(N):
    a0 = -math.pi / 2 + (i + 0.5) * TAU / N
    g = GAP / MID
    hi, ho = R.uniform(0.22, 0.3), R.uniform(0.2, 0.3)
    prof = [(R_IN, 0), (R_IN, hi - 0.06), (R_IN + 0.08, hi), (R_OUT - 0.1, ho), (R_OUT, ho - 0.08), (R_OUT, 0)]
    top = shade(TOP, R.uniform(0.9, 1.1))

    def col(si, j, kind, th, top=top):
        return top if kind == "top" else (SHADOW if kind == "side" else SEAM)
    parts.append(arc_mesh(f"Crag{i}", a0 + g / 2, a0 + TAU / N - g / 2, prof, top, segs=3, col_fn=col))
for i, (x, y, th, deg) in enumerate(spots(12)):
    rr = MID + (0.18 if i % 2 else -0.18)
    parts += gem(f"Inlay{i}", 0.2, polar(rr, th, 0.19), RAINBOW[i % 6], h=0.13, rot=(0, 0, deg))
frame_finish("habitat_frame_7", parts)
