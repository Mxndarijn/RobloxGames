# ranch_fence_20: 20-stud plot fence = two phoenix_fence_segment bays joined, with a post at both ends
# and a mid post at the 10-stud mark. Same posts/planks/rail/battens/colours/height (shared helpers in
# models/_phoenix_ranch.py). Outer face -Y. End posts sit at x=+-10.1 so the native length is 22.0
# (11 per 10 studs, like the segment): a uniform 20/22 = 10/11 scale tiles a 20-stud grid and gives
# the exact same height as phoenix_fence_segment at FENCE_SCALE.
from lib import *
from models._phoenix_ranch import *
END = SEG + 0.1  # 22.0 overall incl. caps (1.8 wide)
parts = []
for i, x in enumerate((-END, 0.0, END)):
    parts += rpost(f"Post{i}", x, 0, WALL_H)
# same span as the segment wall: from the post's inner face into the next post's centre
parts += board_wall("WA", -END + POST_W / 2, 0.0, WALL_H - 0.3, seed=3)
parts += board_wall("WB", 0.0, END - POST_W / 2, WALL_H - 0.3, seed=4)
finish("ranch_fence_20", parts)
