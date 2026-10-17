# giant_cloud_tree: border v6 giant, a layered "cloud" tree (~104 x 100 x 128): a tall, gently S-bent trunk that
# forks twice and carries three wide, flat, stacked canopy pads like an acacia, each pad built from squashed puffs.
import math, random
from lib import *
from models._giant_tree import *

R = random.Random(603)
parts = [limb("Trunk", [(0, 0, -0.5), (3, 1.5, 18), (-2, 3, 40), (2.5, 0, 62), (0, -1, 80)], [9.5, 6.6, 5.4, 4.4, 3.6], R, segs=7)]
for k in range(3):
    a = k * math.tau / 3 + 1.0 + R.uniform(-0.3, 0.3)
    parts.append(limb(f"Root{k}", [(math.cos(a) * 12, math.sin(a) * 12, -0.8), (math.cos(a) * 7, math.sin(a) * 7, 3), (math.cos(a) * 2.5, math.sin(a) * 2.5, 11)],
                      [1.6, 2.4, 3.0], R, segs=5))


def pad(prefix, cx, cy, cz, rx, ry, leaf=FIELD, leaf_d=FIELD_D, leaf_l=FIELD_L):
    """Flat canopy pad: a ring of flattened puffs round a flat core, rim lower than the middle."""
    out = []
    core = blob(f"{prefix}Core", rx * 0.62, (cx, cy, cz), seed=R.randint(0, 999), subdiv=2, squash=(1, ry / rx, 0.42), jitter=0.05)
    gradient(lowpoly(core, 0.6), shade(leaf_d, 0.92), leaf)
    out.append(core)
    n = 7
    for k in range(n):
        a = k * math.tau / n + R.uniform(-0.25, 0.25)
        d = R.uniform(0.55, 0.78)
        pr = rx * R.uniform(0.34, 0.46)
        o = blob(f"{prefix}Puff{k}", pr, (cx + math.cos(a) * rx * d, cy + math.sin(a) * ry * d, cz - rx * 0.03 + R.uniform(-0.03, 0.05) * rx),
                 seed=R.randint(0, 999), subdiv=2, squash=(1, ry / rx, 0.5), jitter=0.07)
        gradient(lowpoly(o, 0.58), leaf_d, mix(leaf, leaf_l, 0.4))
        out.append(o)
    top = blob(f"{prefix}Top", rx * 0.4, (cx + R.uniform(-0.1, 0.1) * rx, cy + R.uniform(-0.1, 0.1) * ry, cz + rx * 0.17),
               seed=R.randint(0, 999), subdiv=2, squash=(1, ry / rx, 0.5), jitter=0.05)
    gradient(lowpoly(top, 0.6), leaf, leaf_l)
    out.append(top)
    return out


# three pads on forks: low and wide to high and small; branches reach the pad undersides
for i, (end, rx, ry) in enumerate([((-30, 8, 66), 34, 26), ((26, -12, 92), 30, 24), ((-4, -4, 114), 22, 18)]):
    start = (2.5 if i < 2 else 0, 0, 56 + i * 12)
    parts.append(limb(f"Fork{i}", [start, (end[0] * 0.5, end[1] * 0.5, end[2] - 14), (end[0], end[1], end[2] - 3)], [3.4, 2.4, 1.7], R))
    parts += pad(f"Pad{i}", end[0], end[1], end[2] + 2, rx, ry, leaf=mix(FIELD, FIELD_L, 0.12 * i), leaf_l=mix(FIELD_L, rgb(255, 255, 200), 0.1 * i))
finish("giant_cloud_tree", parts)
