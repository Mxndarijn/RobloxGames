# habitat_prop_pebble: a little pile of round stones with moss on their tops and a tiny sprout.
import math
from lib import *
from models._habitat_prop2 import *

GREYS = [rgb(168, 160, 150), rgb(148, 144, 142), rgb(180, 170, 156), rgb(158, 150, 140)]
MOSS, MOSS_HI = rgb(92, 168, 70), rgb(124, 192, 82)


def mossy(o, base, moss_z):
    """Moss on faces that look up and sit above moss_z; stone below, darker toward the bottom."""
    return paint(o, lambda c, n: (MOSS_HI if n.z > 0.9 else MOSS) if (n.z > 0.62 and c.z > moss_z)
                 else (base if c.z > moss_z * 0.6 else shade(base, 0.88)))


stones = [  # r, pos, squash, seed
    (0.38, (-0.36, 0.05, 0.22), (1.25, 1.0, 0.68), 1),
    (0.32, (0.38, 0.08, 0.18), (1.2, 1.05, 0.66), 2),
    (0.24, (0.12, -0.32, 0.12), (1.3, 1.0, 0.6), 3),
    (0.3, (0.0, 0.1, 0.5), (1.15, 1.0, 0.78), 4),
    (0.16, (-0.1, 0.12, 0.8), (1.1, 1.0, 0.8), 5),
    (0.14, (-0.66, -0.25, 0.07), (1.2, 1.0, 0.6), 6),
]
parts = []
for j, (r, p, sq, sd) in enumerate(stones):
    o = floor(blob(f"Stone{j}", r, p, None, seed=sd, subdiv=2, squash=sq, jitter=0.04))
    parts.append(mossy(o, GREYS[j % 4], p[2] + r * sq[2] * 0.25))
# sprout on top: two leaves
parts.append(cylinder("SproutStem", 0.025, 0.14, (-0.1, 0.12, 0.9), LEAF_D, segs=4))
for s in (-1, 1):
    parts.append(blob(f"SproutLeaf{s}", 0.07, (-0.1 + s * 0.07, 0.12, 1.04), LEAF, subdiv=1, squash=(1.4, 0.7, 0.4),
                      jitter=0, rot=(0, -s * 25, 0)))
ship("habitat_prop_pebble", parts)
