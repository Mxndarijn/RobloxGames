# phoenix_fence_segment: tileable 10-stud plank wall, 8 tall. Post at the -X end only (neighbour supplies the
# next one; phoenix_corner_post / gate close the ends). Outer face -Y. 6 per plot side + 20-stud gate = 80.
# r02 (v30 C5): same joint fix as ranch_fence_20 r03: the post body is flush with the -X bbox edge (cap
# without X overhang) and the planks/rail run to the +X edge and touch edge to edge (no 0.14 gap showing
# the battens, no per-board tilt), so a neighbouring segment or panel joins with no slit. Same 11.0 x 9.02
# x 1.8 bbox (posts at the same height, rail top 7.45).
from lib import *
from models._phoenix_ranch import *
X0, X1 = -SEG / 2 - 0.9, SEG / 2 + 0.1  # bbox -5.9..5.1 (r01 cap reached -5.9, rail +5.1)
PX = X0 + 0.8
N = 6
BH = 6.95 / N
parts = []
parts.append(bbox("Post", (1.6, POST_W, WALL_H), (PX, 0, WALL_H / 2), shade(WOOD_D, 0.92), WOOD_D, bev=0.15))
parts.append(bbox("PostCap", (1.6, POST_W + 0.4, 0.4), (PX, 0, WALL_H + 0.2), shade(CREAM, 0.9), CREAM, bev=0.12))
parts.append(blob("PostKnob", POST_W * 0.42, (PX, 0, WALL_H + 0.55), CREAM, subdiv=1, squash=(1, 1, 0.8), jitter=0))
W0 = PX + 0.2
for i in range(N):
    col = WOOD if i % 2 else shade(WOOD, 0.94)
    parts.append(bbox(f"B{i}", (X1 - W0, 0.5, BH), ((X1 + W0) / 2, 0, i * BH + BH / 2), shade(col, 0.9), col, bev=0.1))
parts.append(bbox("Rail", (X1 - W0, 0.8, 0.6), ((X1 + W0) / 2, 0, N * BH - 0.1 + 0.3), shade(CREAM, 0.88), CREAM))
for k, x in enumerate((W0 + (X1 - W0) * 0.33, W0 + (X1 - W0) * 0.67)):
    parts.append(bbox(f"Bat{k}", (0.6, 0.3, N * BH - 0.2), (x, 0.38, (N * BH - 0.2) / 2 + 0.1), shade(WOOD_D, 0.95), WOOD_D, bev=0.06))
finish("phoenix_fence_segment", parts)
