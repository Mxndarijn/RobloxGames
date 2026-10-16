# ranch_fence_20: 20-stud plot fence = two phoenix_fence_segment bays joined. Like the segment it has
# a post at its -X end only (plus the mid post): the next panel's -X post closes the +X end, so a run
# shows ONE post per joint (r02; r01 had posts at both ends, doubled where panels met). Same posts/
# planks/rail/battens/colours/height (shared helpers in models/_phoenix_ranch.py). Outer face -Y.
# Native length stays 22.0 (11 per 10 studs, like the segment): the -X post cap reaches x=-11.0, the
# rail x=+11.0, so a uniform 20/22 = 10/11 scale tiles a 20-stud grid at the same height as
# phoenix_fence_segment at FENCE_SCALE, and the posts land where two segments put theirs.
from lib import *
from models._phoenix_ranch import *
# r03 (v30 C5): planks, rail and battens run as ONE wall from the -X post through the mid post to the
# +X edge, so there is no plank start/stop beside the mid post and no per-bay tilt (r02 gave each bay
# its own random tilts, so the two halves' planks sat at different heights and the rail broke at the
# post). Planks touch edge to edge (their bevels draw the seam; r02 left a 0.14 gap that showed the
# battens through). The -X post is 1.6 deep in X with its outer face ON the bbox edge (x=-11.0) and no
# X overhang on the cap, so the previous panel's planks/rail, which end exactly at +11.0, meet its body
# with no gap (r02's post body started 0.2 in, a see-through slit at every joint). The rail sinks 0.1
# into the top plank (no coplanar rail-bottom/plank-top pair). Same 22.0 x 9.02 x 1.8 bbox.
END = SEG + 0.1  # -X post (r02 centre); body now spans -11.0..-9.4, centre -10.2
MID = 0.9        # second bay's post: two segments at 10/11 put theirs at -10.1 and +0.9 native
X0, X1 = -11.0, 11.0
PX = X0 + 0.8    # -X post centre
H = WALL_H - 0.3
N = 6
BH = 6.95 / N     # planks 0..6.95, rail 6.85..7.45 (top 7.45 like r02 and phoenix_fence_segment)
parts = []
# -X post: wider in X so its outer face is flush with the bbox edge; cap flush too
parts.append(bbox("Post0", (1.6, POST_W, WALL_H), (PX, 0, WALL_H / 2), shade(WOOD_D, 0.92), WOOD_D, bev=0.15))
parts.append(bbox("Post0Cap", (1.6, POST_W + 0.4, 0.4), (PX, 0, WALL_H + 0.2), shade(CREAM, 0.9), CREAM, bev=0.12))
parts.append(blob("Post0Knob", POST_W * 0.42, (PX, 0, WALL_H + 0.55), CREAM, subdiv=1, squash=(1, 1, 0.8), jitter=0))
parts += rpost("Post1", MID, 0, WALL_H)
# one plank wall, no tilt, boards touching (bevel seams); starts inside the -X post, ends at +11.0
for i in range(N):
    col = WOOD if i % 2 else shade(WOOD, 0.94)
    parts.append(bbox(f"B{i}", (X1 - (PX + 0.2), 0.5, BH), ((X1 + PX + 0.2) / 2, 0, i * BH + BH / 2),
                      shade(col, 0.9), col, bev=0.1))
# top rail, continuous, sunk 0.1 into the top plank
RZ0, RZ1 = N * BH - 0.1, H - 0.25
parts.append(bbox("Rail", (X1 - (PX + 0.2), 0.8, RZ1 - RZ0), ((X1 + PX + 0.2) / 2, 0, (RZ0 + RZ1) / 2),
                  shade(CREAM, 0.88), CREAM))
# back battens (inner side): centred in each bay so the two halves match
for k, x in enumerate((-5.0, 6.0)):
    parts.append(bbox(f"Bat{k}", (0.6, 0.3, N * BH - 0.2), (x, 0.38, (N * BH - 0.2) / 2 + 0.1), shade(WOOD_D, 0.95), WOOD_D, bev=0.06))
finish("ranch_fence_20", parts)
