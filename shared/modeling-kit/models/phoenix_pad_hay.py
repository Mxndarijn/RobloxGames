# phoenix_pad_hay: hay nest, ~7.8 diameter, rim 1.8, slime sits in the hollow at z~1.0.
import math
from lib import *
from models._phoenix_ranch import *
HAY = BUTTER
parts = [cylinder("Base", 3.2, 1.0, (0, 0, 0), shade(HAY, 0.85), segs=12)]
gradient(parts[0], shade(HAY, 0.75), shade(HAY, 0.9))
N = 10
for i in range(N):
    a = i * math.tau / N
    r = 2.85  # r02: was 3.3 -> 8.9 wide, over the 8x8 pad grid
    parts.append(blob(f"Tuft{i}", 1.05 + 0.15 * (i % 3 == 0), (math.cos(a) * r, math.sin(a) * r, 0.9), HAY, subdiv=2,
                      squash=(1.35, 1.0, 0.75), jitter=0.04, seed=i, rot=(0, 0, math.degrees(a) + 90)))
    gradient(parts[-1], shade(HAY, 0.8), HAY)
for i in range(5):
    a = i * math.tau / 5 + 0.3
    parts.append(tube(f"Straw{i}", [(math.cos(a) * 3.3, math.sin(a) * 3.3, 1.4), (math.cos(a) * 3.6, math.sin(a) * 3.6, 2.0)],
                      [0.12, 0.06], shade(HAY, 1.05), segs=4))
parts.append(cylinder("Bed", 2.6, 0.2, (0, 0, 0.95), shade(HAY, 0.92), segs=12))
finish("phoenix_pad_hay", parts)
