# habitat_prop_isle: signature prop for Isle: a mini floating island: a grassy top with a little tree and a tiny
# waterfall, a rocky underside tapering to a point, held up on a short gold stand over a cloud disc. Front -Y.
import math
from lib import *
from models._habitat_prop4 import *

GRASS, GRASS_HI, GRASS_D = rgb(110, 210, 90), rgb(160, 232, 110), rgb(78, 168, 76)
ROCK, ROCK_D, ROCK_HI = rgb(170, 126, 92), rgb(132, 98, 76), rgb(196, 154, 112)
TRUNK, LEAF, LEAF_HI = rgb(160, 106, 66), rgb(80, 186, 86), rgb(130, 220, 100)
WATER, WATER_HI = rgb(96, 200, 250), rgb(196, 240, 255)
GOLD, BASE = rgb(255, 200, 70), rgb(240, 242, 252)

parts = []
parts.append(cylinder("Base", 0.3, 0.08, (0, 0, 0), BASE, segs=10, r_top=0.27))
parts.append(cylinder("Rod", 0.04, 0.42, (0, 0, 0.08), GOLD, segs=6))
ZT = 0.92  # grass top height
rock = lathe("Rock", [(0.0, 0.42), (0.12, 0.5), (0.3, 0.62), (0.48, 0.76), (0.58, ZT - 0.08), (0.6, ZT - 0.04)], segs=9)
for v in rock.data.vertices:  # jag the rock
    if 0.45 < v.co.z < ZT - 0.1:
        k = 1 + 0.12 * math.sin(math.atan2(v.co.y, v.co.x) * 3 + v.co.z * 9)
        v.co.x *= k
        v.co.y *= k
paint(rock, lambda c, n: ROCK_HI if c.z > 0.74 else (ROCK if c.z > 0.58 else ROCK_D))
parts.append(rock)
grass = lathe("Grass", [(0.0, ZT - 0.08), (0.64, ZT - 0.08), (0.66, ZT - 0.02), (0.6, ZT + 0.03), (0.3, ZT + 0.06), (0.0, ZT + 0.07)],
              segs=12)
for v in grass.data.vertices:  # drip lobes on the edge
    if v.co.z < ZT - 0.05:
        a = math.atan2(v.co.y, v.co.x)
        v.co.z -= 0.06 * max(0, math.sin(a * 4 + 0.5))
paint(grass, lambda c, n: GRASS_HI if n.z > 0.7 else GRASS)
parts.append(grass)
# little tree at the back left
parts.append(cylinder("Trunk", 0.05, 0.22, (-0.2, 0.18, ZT + 0.04), TRUNK, segs=5, r_top=0.035))
for k, (dx, dy, dz, r) in enumerate([(0, 0, 0.3, 0.17), (0.1, -0.04, 0.24, 0.12), (-0.09, 0.03, 0.25, 0.12)]):
    b = blob(f"Leaf{k}", r, (-0.2 + dx, 0.18 + dy, ZT + dz), LEAF, subdiv=1, jitter=0.08, seed=k)
    paint(b, lambda c, n: LEAF_HI if n.z > 0.3 else LEAF)
    parts.append(b)
# boulder and a flower at the front right
parts.append(blob("Boulder", 0.09, (0.28, -0.12, ZT + 0.05), rgb(186, 180, 176), subdiv=1, jitter=0.1, seed=7))
parts.append(cylinder("Stem", 0.012, 0.1, (0.05, -0.32, ZT + 0.03), GRASS_D, segs=3))
parts.append(blob("Bloom", 0.04, (0.05, -0.32, ZT + 0.14), rgb(255, 140, 190), subdiv=1, jitter=0))
# tiny waterfall: a pool on top spilling over the right edge and falling down the rock
parts.append(cylinder("Pool", 0.14, 0.02, (0.34, 0.12, ZT + 0.04), WATER, segs=8))
fall = ribbon("Fall", [(0.44, 0.14, ZT + 0.05), (0.62, 0.15, ZT + 0.0), (0.68, 0.15, ZT - 0.14), (0.68, 0.15, ZT - 0.34)],
              [0.12, 0.12, 0.11, 0.08], thick=0.03, up=(0, 1, 0), color=WATER)
paint(fall, lambda c, n: WATER_HI if c.z > ZT - 0.05 else WATER)
parts.append(fall)
parts.append(blob("Mist", 0.05, (0.68, 0.15, ZT - 0.38), WATER_HI, subdiv=1, jitter=0))
for o in parts:  # oval island: keeps the depth inside the rim band
    move(o, scale=(1, 0.84, 1))
prop_finish("habitat_prop_isle", parts)
