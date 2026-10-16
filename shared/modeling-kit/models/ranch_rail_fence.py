# ranch_rail_fence: rustic log rail fence, the border's second fence style (the plot fence is
# phoenix_fence_segment planks). ~12 x 4.7 x 1.6. Posts at both ends + one off-centre, so a lone
# segment looks finished; in a run the end posts sit side by side like a mended fence. rot= DEGREES.
import random
from lib import *
from models._border import *

R = random.Random(23)
W = 12.0
WOOD_LO = mix(WOOD_D, WOOD, 0.45)
POSTS = (-W / 2 + 0.6, 0.9, W / 2 - 0.6)
RAILS = (1.6, 3.1)
parts = []
for k, x in enumerate(POSTS):
    h = 4.35 + R.uniform(-0.2, 0.25)
    p = cylinder(f"Post{k}", 0.56, h, (x, 0, -0.05), WOOD, segs=8, r_top=0.48, jitter=0.04, seed=R.randint(0, 99))
    gradient(p, WOOD_D, WOOD)
    parts.append(p)
    parts.append(cylinder(f"Cap{k}", 0.52, 0.24, (x, 0, h - 0.08), mix(WOOD, CREAM, 0.35), segs=8, r_top=0.34))
    parts += tuft(f"Tuft{k}", (x + 0.4, -0.45, 0), R, h=1.0, blades=4)
# two log rails per bay, slightly sagging; rot y=90 grows the cylinder toward +X
for b in range(2):
    x0, x1 = POSTS[b], POSTS[b + 1]
    for k, z in enumerate(RAILS):
        tilt = R.uniform(-2.0, 2.0)
        rail = cylinder(f"Rail{b}{k}", 0.34, x1 - x0 + 0.5, (x0 - 0.25, -0.12 * (-1) ** k, z), WOOD, segs=8,
                        rot=(0, 90 + tilt, 0), jitter=0.05, seed=R.randint(0, 99))
        gradient(rail, WOOD_LO, mix(WOOD, CREAM, 0.15), z0=z - 0.35, z1=z + 0.35)
        parts.append(rail)
# rope lashings where the rails cross the posts
for x in POSTS:
    for z in RAILS:
        parts.append(cylinder(f"Lash{x}{z}", 0.62, 0.32, (x - 0.16, 0, z), PALETTE["ranch_path"], segs=8, rot=(0, 90, 0)))
# a goo dollop over the top rail of the long bay (lens + hanging drop, LESSONS: not a stuck-on tube)
g = blob("Goo", 0.42, (3.9, -0.1, 3.38), GOO, subdiv=2, squash=(1.7, 1.2, 0.5), jitter=0.03)
gradient(g, GOO, GOO_HI)
parts.append(g)
parts.append(blob("GooDrop", 0.22, (4.1, -0.38, 2.98), GOO_HI, subdiv=1, squash=(0.8, 0.8, 1.25), jitter=0.0))
parts += flower("BloomA", (-3.0, -0.65, 0.35), R, PINK, r=0.32)
parts += flower("BloomB", (4.4, -0.6, 0.3), R, BUTTER, r=0.3)
parts += flower("BloomC", (-1.4, 0.5, 0.3), R, LILAC, r=0.28)
parts += tuft("TuftMid", (-2.8, 0.45, 0), R, h=0.85)
finish("ranch_rail_fence", parts)
