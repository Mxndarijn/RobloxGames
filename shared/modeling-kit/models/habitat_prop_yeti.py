# habitat_prop_yeti: an ice cave mouth: a chunky arch of ice boulders round a dark opening, snow on top, icicles
# hanging from the lip.
import math, random
from models._habitat_prop3 import *

CAVE = rgb(40, 62, 110)
R = random.Random(8)
parts = []
# dark back: a half-dome behind the arch so the opening reads deep
back = lathe("Back", [(0, 0), (0.5, 0), (0.5, 0.25), (0.38, 0.6), (0, 0.78)], segs=10)
xf(back, (0, 0.18, 0), (0, 0, 0), (1.15, 0.7, 1.15))
paint_faces(back, lambda p, n: CAVE if n.y < 0.2 else ICE_LO)
parts.append(back)
parts.append(box("Floor", (0.9, 0.5, 0.04), (0, -0.05, 0.02), shade(CAVE, 1.25)))
# arch: ice boulders along a half-ellipse, biggest at the feet
n = 9
for i in range(n):
    t = i / (n - 1)
    a = math.pi * t
    x, z = math.cos(a) * 0.66, math.sin(a) * 0.82
    s = 0.27 - 0.08 * math.sin(a) + R.uniform(-0.02, 0.02)
    b = blob(f"Ice{i}", s, (x, -0.12, max(z, s * 0.6)), ICE, subdiv=1, jitter=0.1, seed=i, squash=(1, 0.95, 1))
    paint_faces(b, lambda p, nn: ICE if nn.z > 0.3 else (mix(ICE_LO, ICE, 0.5) if nn.y < -0.3 else ICE_LO))
    parts.append(floor(b))
# snow cap over the top of the arch
for i, (x, z, r) in enumerate(((-0.3, 0.98, 0.2), (0.0, 1.06, 0.24), (0.32, 0.98, 0.2))):
    parts.append(grad(blob(f"Snow{i}", r, (x, -0.1, z), SNOW, subdiv=1, squash=(1.3, 1.2, 0.6), jitter=0.08, seed=20 + i), SNOW_LO, SNOW))
# icicles under the lip
for i, (x, h) in enumerate(((-0.24, 0.2), (-0.08, 0.28), (0.08, 0.18), (0.22, 0.24))):
    z0 = math.sqrt(max(0, 1 - (x / 0.66) ** 2)) * 0.82 - 0.2
    parts.append(xf(cone(f"Icicle{i}", 0.05, h, (0, 0, 0), rgb(200, 240, 255), segs=5), (x, -0.24, z0), (180, 0, 0)))
# little ice shards at the feet
for i, (x, y) in enumerate(((-0.8, -0.3), (0.79, -0.32))):
    c = prism_crystal(f"Shard{i}", 0.06, 0.22, lo=ICE_LO, hi=rgb(210, 245, 255))
    parts.append(floor(place(c, (x, y, 0.05), 20, 180 if x < 0 else 0)))
ship("habitat_prop_yeti", parts)
