# habitat_barn_crate_overlay: red-barn dressing for the crate pad: a barn-red plank frame with a white inner
# trim round the mat, an L of red barn planks with white trim and a white post round each corner, a little
# barn door (red, white X brace both faces, gable roof) at the back, hay bales on the side middles, hay wisps.
import math
import random
from lib import *
from models._habitat_overlay import *
from models._phoenix_ranch import BUTTER, WOOD_D, bbox

BARN = rgb(220, 54, 46)  # deeper than the mat red (ROOF) so the frame doesn't merge into it
BARN_D = shade(BARN, 0.8)
WHITE = rgb(250, 246, 238)
R = random.Random(3)

parts = [frame("Planks", BARN, BARN_D, seed=3, wobble=0.0)]
# white trim strip round the mat (inner lip of the frame), proud of the frame top
for s in (-1, 1):
    parts.append(bbox(f"TrimX{s}", (INNER + 0.3, 0.16, 0.22), (0, s * (INNER / 2 + 0.08), 0.11), shade(WHITE, 0.85), WHITE, bev=0))
    parts.append(bbox(f"TrimY{s}", (0.16, INNER + 0.3, 0.22), (s * (INNER / 2 + 0.08), 0, 0.11), shade(WHITE, 0.85), WHITE, bev=0))
# plank seams across the frame band (dark lines on the red top)
for s in (-1, 1):
    for t in (-1.6, 0, 1.6):
        parts.append(box(f"SeamX{s}{t}", (0.07, HALF - INNER / 2 - 0.2, 0.02), (t, s * BAND, FRAME_H + 0.005), BARN_D))
        parts.append(box(f"SeamY{s}{t}", (HALF - INNER / 2 - 0.2, 0.07, 0.02), (s * BAND, t, FRAME_H + 0.005), BARN_D))

# corner barn walls: an L of vertical red planks round each corner, white top trim, white corner post + red peak
P_W, PC = 0.5, 3.35
for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
    x, y = sx * PC, sy * PC
    h = 0.95 if sy < 0 else 1.25  # front corners lower so the slime stays in view
    for ax in (0, 1):
        for k in range(3):  # three planks per arm, alternating shade and height
            d = 0.42 + k * 0.4
            ph = h - 0.06 * (k % 2)
            col = BARN if k % 2 == 0 else shade(BARN, 0.9)
            px, py = (x - sx * d, y) if ax == 0 else (x, y - sy * d)
            size = (0.38, 0.26, ph) if ax == 0 else (0.26, 0.38, ph)
            parts.append(bbox(f"Plank{i}{ax}{k}", size, (px, py, ph / 2), shade(col, 0.8), col, bev=0))
        cx, cy = (x - sx * 0.82, y) if ax == 0 else (x, y - sy * 0.82)
        size = (1.3, 0.34, 0.14) if ax == 0 else (0.34, 1.3, 0.14)
        parts.append(bbox(f"WallTrim{i}{ax}", size, (cx, cy, h + 0.07), shade(WHITE, 0.86), WHITE, bev=0))
    parts.append(bbox(f"Post{i}", (P_W, P_W, h + 0.25), (x, y, (h + 0.25) / 2), shade(WHITE, 0.8), WHITE, bev=0))
    parts.append(cone(f"Peak{i}", 0.4, 0.3, (x, y, h + 0.25), BARN, segs=4, rot=(0, 0, 45)))

# barn door at the back middle: red panel, white frame and X brace on both faces, white gable roof
D_W, D_H, DY = 2.1, 1.85, 3.15
parts.append(bbox("Door", (D_W, 0.3, D_H), (0, DY, D_H / 2), BARN_D, BARN, bev=0.03))
diag = math.degrees(math.atan2(D_H - 0.32, D_W - 0.32))
L = math.hypot(D_W - 0.32, D_H - 0.32)
for f, fy in (("F", DY - 0.19), ("B", DY + 0.19)):  # trim 0.04 proud of each door face
    for s in (-1, 1):
        parts.append(box(f"DoorSide{f}{s}", (0.18, 0.08, D_H), (s * (D_W / 2 - 0.09), fy, D_H / 2), WHITE))
        parts.append(box(f"DoorX{f}{s}", (L, 0.06, 0.16), (0, fy, D_H / 2), WHITE, rot=(0, s * diag, 0)))
    parts.append(box(f"DoorTop{f}", (D_W, 0.08, 0.18), (0, fy, D_H - 0.09), WHITE))
    parts.append(box(f"DoorBot{f}", (D_W, 0.08, 0.18), (0, fy, 0.09), WHITE))
for s in (-1, 1):
    parts.append(bbox(f"Roof{s}", (1.35, 0.55, 0.16), (s * 0.52, DY, D_H + 0.28), shade(WHITE, 0.85), WHITE, bev=0, rot=(0, -s * 30, 0)))

# hay bales on the side middles (with twine bands) and loose hay wisps on the band
for s in (-1, 1):
    x = s * 3.15
    parts.append(bbox(f"Bale{s}", (0.95, 1.5, 0.75), (x, 0, 0.375), shade(BUTTER, 0.92), shade(BUTTER, 1.06), bev=0.06))
    for t in (-0.4, 0.4):
        parts.append(box(f"Twine{s}{t}", (0.99, 0.1, 0.75), (x, t, 0.375), shade(WOOD_D, 0.9)))
for i, (x, y) in enumerate(((-1.6, -3.1), (1.7, -3.15), (-1.7, 3.2), (3.15, 1.5))):
    parts.append(blob(f"Hay{i}", 0.34, (x, y, 0.3), shade(BUTTER, R.uniform(0.95, 1.06)), subdiv=1,
                      squash=(1.3, 1.0, 0.8), jitter=0.08, seed=i, rot=(0, 0, R.uniform(0, 180))))
overlay_finish("habitat_barn_crate_overlay", parts)
