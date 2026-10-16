# ranch_fence_20: 20-stud plot fence = two phoenix_fence_segment bays joined. Like the segment it has
# a post at its -X end only (plus the mid post): the next panel's -X post closes the +X end, so a run
# shows ONE post per joint (r02; r01 had posts at both ends, doubled where panels met). Same posts/
# planks/rail/battens/colours/height (shared helpers in models/_phoenix_ranch.py). Outer face -Y.
# Native length stays 22.0 (11 per 10 studs, like the segment): the -X post cap reaches x=-11.0, the
# rail x=+11.0, so a uniform 20/22 = 10/11 scale tiles a 20-stud grid at the same height as
# phoenix_fence_segment at FENCE_SCALE, and the posts land where two segments put theirs.
from lib import *
from models._phoenix_ranch import *
END = SEG + 0.1  # -X post centre; with the 1.8 cap the panel spans -11.0..+11.0
MID = 0.9        # second bay's post: two segments at 10/11 put theirs at -10.1 and +0.9 native
RAIL = 0.1       # board_wall's rail overhangs each end by 0.1
parts = []
for i, x in enumerate((-END, MID)):
    parts += rpost(f"Post{i}", x, 0, WALL_H)
# walls from the post's inner face into the mid post's centre, then on to the open +X end
parts += board_wall("WA", -END + POST_W / 2, MID, WALL_H - 0.3, seed=3)
parts += board_wall("WB", MID, END + 0.9 - RAIL, WALL_H - 0.3, seed=4)
finish("ranch_fence_20", parts)
