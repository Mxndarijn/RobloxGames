# fence_corner: chunky corner post for the plot kit (~1.1 x 1.1 x 4.1). Sits on a segment joint
# (plot corners, run ends); it is wider than the 0.7 fence_straight posts so it hides them.
from lib import *
from models._fence import *

parts = post("Corner", 0, 0, 0.9, 3.6, cap_h=0.45, collar=0.2)
finish("fence_corner", parts)
