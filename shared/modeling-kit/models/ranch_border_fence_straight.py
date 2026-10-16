# ranch_border_fence_straight: four bays of sturdy log rail fence, two rails, a goo dollop on one rail (~25 x 2.5 x 5).
import random
from lib import *
from models._border_v3 import *

R = random.Random(231)
xs = [-12.0 + k * 6.0 for k in range(5)]
parts = fence_posts_rails("Fence", xs, 0.0, R)
g = blob("Goo", 0.46, (3.2, -0.6, 3.4), GOO, subdiv=2, squash=(1.7, 1.2, 0.5), jitter=0.03)
gradient(g, GOO, GOO_HI)
parts += [g, blob("GooDrop", 0.24, (3.4, -0.8, 2.9), GOO_HI, subdiv=1, squash=(0.8, 0.8, 1.25), jitter=0.0)]
parts += tuft("TuftA", (-6.0, -1.8, 0), R, h=1.1) + tuft("TuftB", (8.4, -1.6, 0), R, h=1.0) + tuft("TuftC", (-12.8, -1.4, 0), R, h=1.0)
finish("ranch_border_fence_straight", parts)
