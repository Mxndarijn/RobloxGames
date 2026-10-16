# ranch_border_fence_broken: three bays of old fence: one post leans, the top rail has dropped to the
# ground and a bay is missing its rails, hay tuft and a bloom growing through (~21 x 5 x 5).
import random
from lib import *
from models._border_v3 import *

R = random.Random(232)
xs = [-10.0, -4.0, 2.2, 8.0]
parts = fence_posts_rails("Fence", xs, 0.0, R, lean={2: 16.0}, skip=(1,), rail_drop={(0, 1): 0.7, (2, 0): 1.2, (2, 1): 2.4})
# the rails of the missing bay lie in the grass in front
for k, (dx, dy, ang) in enumerate([(-1.0, -1.8, -14.0), (0.6, -3.0, 9.0)]):
    r = cylinder(f"Fallen{k}", 0.36, 5.2, (-4.0 + 3.0 + dx, dy, 0.34), WOOD, segs=6, rot=(0, 90, ang), jitter=0.05, seed=5 + k)
    gradient(r, WOOD_LO, mix(WOOD, CREAM, 0.15))
    parts.append(r)
parts += tuft("TuftA", (-1.4, -1.0, 0), R, h=1.3, blades=4) + tuft("TuftB", (5.4, -1.6, 0), R, h=1.1)
parts += flower("Bloom", (-0.4, -1.6, 0.3), R, BUTTER)
finish("ranch_border_fence_broken", parts)
