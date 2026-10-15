# phoenix_fence_segment: tileable 10-stud plank wall, 8 tall. Post at x=-5 only (neighbour supplies x=+5;
# phoenix_corner_post / gate close the ends). Outer face -Y. 6 per plot side + 20-stud gate = 80.
from lib import *
from models._phoenix_ranch import *
parts = rpost("Post", -SEG / 2, 0, WALL_H)
parts += board_wall("W", -SEG / 2 + POST_W / 2, SEG / 2, WALL_H - 0.3, seed=3)
finish("phoenix_fence_segment", parts)
