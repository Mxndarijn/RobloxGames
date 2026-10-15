# phoenix_corner_post: chunky corner post for plot corners (closes two fence runs at 90 deg). 2.2 square, 8.8 tall.
from lib import *
from models._phoenix_ranch import *
W = 2.2
parts = [bbox("Foot", (W + 0.6, W + 0.6, 0.6), (0, 0, 0.3), shade(WOOD_D, 0.9), WOOD_D, bev=0.15)]
parts += rpost("Post", 0, 0, WALL_H + 0.4, w=W)
parts.append(bbox("Band", (W + 0.2, W + 0.2, 0.45), (0, 0, WALL_H - 1.2), shade(ROOF, 0.9), ROOF, bev=0.1))
finish("phoenix_corner_post", parts)
