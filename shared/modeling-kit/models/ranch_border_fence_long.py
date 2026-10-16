# ranch_border_fence_long: eight bays of log rail fence with a field-gate gap: taller gate posts and the
# gate leaf swung open towards the map (~51 x 6 x 5.5). Longest piece of the inner layer.
import random
from lib import *
from models._border_v3 import *

R = random.Random(251)
xs = [-25.0 + k * 6.25 for k in range(9)]
parts = fence_posts_rails("Fence", xs, 0.0, R, skip=(4,), lean={7: 3.0}, rail_drop={(6, 1): 2.7})
# gate posts: the two posts either side of the gap grow taller with a cream cap
for k in (4, 5):
    p = cylinder(f"GatePost{k}", 0.78, 5.4, (xs[k] + (0.55 if k == 4 else -0.55), 0.0, -0.1), WOOD, segs=6, r_top=0.66, jitter=0.03, seed=k)
    gradient(p, WOOD_D, WOOD)
    parts += [p, cylinder(f"GateCap{k}", 0.7, 0.28, (xs[k] + (0.55 if k == 4 else -0.55), 0.0, 5.2), mix(WOOD, CREAM, 0.35), segs=6, r_top=0.46)]
# gate leaf swung open: two rails and a brace along -Y from the left gate post
gx = xs[4] + 0.55
for k, z in enumerate((1.5, 3.4)):
    r = cylinder(f"Leaf{k}", 0.34, 5.6, (gx, -0.2, z), WOOD, segs=6, rot=(90, 0, 0), jitter=0.04, seed=40 + k)
    gradient(r, WOOD_LO, mix(WOOD, CREAM, 0.15), z0=z - 0.4, z1=z + 0.4)
    parts.append(r)
parts.append(cylinder("LeafEnd", 0.5, 4.2, (gx, -5.9, -0.05), WOOD, segs=6, r_top=0.42, jitter=0.03, seed=44))
gradient(parts[-1], WOOD_D, WOOD)
g = blob("Goo", 0.46, (-8.4, -0.6, 3.4), GOO, subdiv=2, squash=(1.7, 1.2, 0.5), jitter=0.03)
gradient(g, GOO, GOO_HI)
parts += [g, blob("GooDrop", 0.24, (-8.2, -0.8, 2.9), GOO_HI, subdiv=1, squash=(0.8, 0.8, 1.25), jitter=0.0)]
parts += tuft("TuftA", (-18.0, -1.7, 0), R, h=1.1) + tuft("TuftB", (13.0, -1.6, 0), R, h=1.0) + tuft("TuftC", (-1.0, -2.2, 0), R, h=1.2, blades=4)
parts += flower("Bloom", (19.0, -1.8, 0.3), R, PINK)
finish("ranch_border_fence_long", parts)
