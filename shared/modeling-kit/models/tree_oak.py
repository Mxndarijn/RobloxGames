# tree_oak: stylised cartoon oak for Steal a Slime (replaces v17 tree_oak, same ~11x13 footprint).
import math, random
from lib import *

R = random.Random(11)
BARK, BARK_D = PALETTE["bark"], PALETTE["bark_dark"]
LEAF_D, LEAF, LEAF_L = PALETTE["leaf_dark"], PALETTE["leaf"], rgb(146, 214, 72)  # lime highlight, a bit more saturated than PALETTE
parts = []

# trunk with flare
H = 6.6
parts.append(tube("Trunk", [(0, 0, -0.1), (0, 0, 0.7), (0.05, 0, 2.5), (0.1, 0.05, 4.9), (0.15, 0.1, H)],
                  [1.4, 0.95, 0.74, 0.66, 0.58], BARK, segs=8, seed=R, jitter=0.06))
gradient(parts[-1], BARK_D, shade(BARK, 1.15), z0=0, z1=H)
# roots
for k in range(5):
    a = k * math.tau / 5 + R.uniform(-0.3, 0.3)
    c, s = math.cos(a), math.sin(a)
    parts.append(tube(f"Root{k}", [(c * 0.4, s * 0.4, 0.9), (c * 1.3, s * 1.3, 0.35), (c * 2.1, s * 2.1, -0.05)],
                      [0.45, 0.32, 0.12], BARK_D, segs=5, seed=R))
    gradient(parts[-1], shade(BARK_D, 0.8), BARK_D)
# branches into canopy
for k, (a, z) in enumerate(((0.3, 4.6), (2.5, 5.0), (4.4, 4.5))):
    c, s = math.cos(a), math.sin(a)
    parts.append(tube(f"Branch{k}", [(0, 0, z), (c * 1.5, s * 1.5, z + 1.1), (c * 2.6, s * 2.6, z + 2.3)],
                      [0.42, 0.32, 0.2], BARK, segs=5, seed=R))
    gradient(parts[-1], BARK, shade(BARK, 1.2))

# canopy: 3 tiers (low wide ring, mid, crown), uneven sizes so the silhouette is lumpy,
# not a ring of beads; each puff dark below / light above. Slight lean to +X.
TOP, CX = 9.6, 0.3
core = blob("Core", 3.6, (CX, 0, TOP), seed=R, subdiv=2, squash=(1.25, 1.1, 0.8), jitter=0.04)
gradient(core, shade(LEAF_D, 0.75), LEAF)
parts.append(core)
LOW = [(0.1, 4.3, 2.5, -1.5), (1.15, 3.6, 1.9, -0.8), (2.0, 4.1, 2.3, -1.3), (2.9, 3.5, 1.8, -0.6),
       (3.7, 4.2, 2.4, -1.4), (4.6, 3.7, 2.0, -0.9), (5.4, 3.9, 1.7, -1.6)]
for k, (a, d, rr, dz) in enumerate(LOW):
    o = blob(f"Low{k}", rr, (CX + math.cos(a) * d, math.sin(a) * d * 0.97, TOP + dz),
             seed=R, subdiv=2, squash=(1, 1, 0.82), jitter=0.06)
    gradient(o, shade(LEAF_D, 0.8), LEAF)
    parts.append(o)
for k, (a, d, rr) in enumerate(((0.7, 2.6, 2.3), (2.4, 2.8, 2.1), (4.1, 2.5, 2.4), (5.6, 2.2, 1.9))):
    o = blob(f"Mid{k}", rr, (CX + math.cos(a) * d, math.sin(a) * d, TOP + 1.1 + R.uniform(-0.2, 0.3)),
             seed=R, subdiv=2, squash=(1, 1, 0.85), jitter=0.06)
    gradient(o, LEAF, LEAF_L)
    parts.append(o)
for k, (x, y, rr) in enumerate(((0.9, 0.4, 2.1), (-0.7, -0.5, 1.8))):
    o = blob(f"Crown{k}", rr, (CX + x, y, TOP + 2.6), seed=R, subdiv=2, squash=(1, 1, 0.85), jitter=0.06)
    gradient(o, LEAF, LEAF_L)
    parts.append(o)

# canopy underside height (ghost decor is fine at any height; collidable needs >= 7)
leaves = [o for o in parts if o.name[:3] in ("Cor", "Low", "Mid", "Cro")]
print(f"tree_oak: canopy underside {min(min(v.co.z for v in o.data.vertices) for o in leaves):.1f} studs")
finish("tree_oak", parts)
