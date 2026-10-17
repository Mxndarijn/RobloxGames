# Shared helpers for the border v5 giant trees (giant_broadleaf, giant_pine_layered, giant_round_canopy):
# the ranch_border_pine_tall / oak_round recipes at 3-5x the height. Not a model: no finish().
import math, random
from lib import *
from models._border_v3 import conifer, lowpoly, WOOD, WOOD_D, FIELD, FIELD_D, FIELD_L, mix, shade


def puff_cluster(prefix, cx, cy, cz, r, R, n=6, leaf=FIELD, leaf_d=FIELD_D, leaf_l=FIELD_L, ratio=0.62):
    """Lumpy canopy cluster: a core blob, a ring of n uneven puffs round it and one crown puff on top."""
    parts = []
    core = blob(f"{prefix}Core", r * 0.82, (cx, cy, cz), seed=R.randint(0, 999), subdiv=2, squash=(1.05, 1.0, 0.85), jitter=0.05)
    gradient(lowpoly(core, ratio), shade(leaf_d, 0.9), leaf)
    parts.append(core)
    for k in range(n):
        a = k * math.tau / n + R.uniform(-0.35, 0.35)
        d = r * R.uniform(0.6, 0.85)
        pr = r * R.uniform(0.5, 0.68)
        o = blob(f"{prefix}Puff{k}", pr, (cx + math.cos(a) * d, cy + math.sin(a) * d, cz - r * 0.12 + R.uniform(-0.05, 0.1) * r),
                 seed=R.randint(0, 999), subdiv=2, squash=(1, 1, 0.85), jitter=0.07)
        gradient(lowpoly(o, ratio * 0.95), leaf_d, leaf)
        parts.append(o)
    top = blob(f"{prefix}Top", r * 0.55, (cx + R.uniform(-0.05, 0.05) * r, cy + R.uniform(-0.05, 0.05) * r, cz + r * 0.5),
               seed=R.randint(0, 999), subdiv=2, squash=(1, 1, 0.85), jitter=0.05)
    gradient(lowpoly(top, ratio), leaf, leaf_l)
    parts.append(top)
    return parts


def limb(name, pts, radii, R, segs=6):
    t = tube(name, pts, radii, WOOD, segs=segs, seed=R.randint(0, 999), jitter=0.05)
    gradient(t, shade(WOOD_D, 0.92), mix(WOOD, WOOD_D, 0.4))
    return t
