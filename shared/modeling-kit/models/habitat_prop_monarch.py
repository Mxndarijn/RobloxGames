# habitat_prop_monarch: a milkweed plant (green stem, broad leaves, pink flower clusters) with a jade-and-gold
# chrysalis hanging under a leaf and an orange monarch butterfly resting on top. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

STEM, LEAF, LEAF_HI = rgb(110, 190, 80), rgb(104, 196, 84), rgb(150, 220, 104)
FLOWER, FLOWER_HI = rgb(255, 140, 190), rgb(255, 190, 220)
JADE, JADE_HI, GOLDD = rgb(110, 216, 150), rgb(170, 244, 190), rgb(255, 206, 60)
ORANGE, ORANGE_HI, EDGE, DOT = rgb(255, 136, 30), rgb(255, 176, 60), rgb(56, 40, 36), rgb(255, 250, 240)
SOIL = rgb(150, 104, 70)
parts = [floor(blob("Soil", 0.3, (0, 0.04, 0.0), SOIL, subdiv=2, squash=(1.4, 1.0, 0.35), jitter=0.08, seed=2))]
stem_pts = [(0, 0.05, 0.05), (0.02, 0.06, 0.4), (-0.01, 0.05, 0.75), (0.0, 0.06, 1.0)]
parts.append(tube("Stem", stem_pts, [0.04, 0.035, 0.03, 0.026], STEM, segs=6))


def leaf(name, z, yaw, l=0.42, w=0.12, droop=12, x0=0.0):
    n = 6
    top = [(l * k / n, w * math.sin(math.pi * k / n)) for k in range(n + 1)]
    bot = [(l * k / n, -w * 0.9 * math.sin(math.pi * k / n)) for k in range(n - 1, 0, -1)]
    o = slab(name, top + bot, 0.03)
    move(o, rot=(84, droop, 0))
    paint(o, lambda c, n_: LEAF_HI if n_.z > 0.3 else LEAF)
    return move(o, (x0, 0.05, z), (0, 0, yaw))


LEAVES = [(0.56, -35, 0.5, 14), (0.42, 150, 0.48, 12), (0.28, 30, 0.46, 10), (0.74, -150, 0.38, 10), (0.88, 60, 0.28, 4)]
for k, (z, yaw, l, d) in enumerate(LEAVES):
    parts.append(leaf(f"Leaf{k}", z, yaw, l, droop=d))
# flower umbels: a dome of small pink buds on top and a smaller one on the right
for c, (cx, cy, cz, r, n) in enumerate(((0.0, 0.06, 1.04, 0.13, 9), (0.26, 0.1, 0.8, 0.09, 6))):
    if c:
        parts.append(tube("Branch", [(0.01, 0.06, 0.66), (0.14, 0.08, 0.74), (cx, cy, cz - 0.03)], [0.022] * 3, STEM, segs=5))
    for k in range(n):
        a = k * math.tau / (n - 1)
        rr = 0 if k == n - 1 else r
        parts.append(blob(f"Bud{c}{k}", 0.055 if c == 0 else 0.045, (cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.8,
                                                                     cz + (0.06 if k == n - 1 else 0)),
                          FLOWER_HI if k % 2 else FLOWER, subdiv=1, jitter=0.05, seed=k))
# chrysalis hanging under the front-right leaf (yaw -35, ~0.28 out)
a = math.radians(-35)
hx, hy, hz = 0.3 * math.cos(a), 0.05 + 0.3 * math.sin(a), 0.56 - 0.3 * math.sin(math.radians(14)) - 0.02
parts.append(tube("Silk", [(hx, hy, hz + 0.01), (hx, hy, hz - 0.04)], [0.012, 0.012], EDGE, segs=4))
chry = lathe("Chrysalis", [(0, 0), (0.05, 0.03), (0.075, 0.09), (0.07, 0.15), (0.045, 0.2), (0.02, 0.22), (0, 0.22)], segs=10,
             pos=(hx, hy, hz - 0.26))
paint(chry, lambda c, n: GOLDD if abs(c.z - (hz - 0.08)) < 0.018 else (JADE_HI if n.y < -0.5 and n.x < 0 else JADE))
parts.append(chry)
for k in range(3):  # gold dots under the band
    t = (k - 1) * 0.7
    parts.append(blob(f"Gold{k}", 0.014, (hx + 0.07 * math.sin(t), hy - 0.07 * math.cos(t), hz - 0.2), GOLDD, subdiv=1, jitter=0))
# monarch butterfly resting in front of the top flowers, wings spread facing the walkway
BX, BY, BZ = -0.02, -0.08, 1.12
fore = [(0.0, 0.0), (0.08, 0.1), (0.24, 0.17), (0.26, 0.1), (0.18, -0.01)]
hind = [(0.0, -0.01), (0.17, -0.02), (0.17, -0.11), (0.09, -0.16), (0.02, -0.08)]
for s in (-1, 1):
    for nm, pts in (("F", fore), ("H", hind)):
        sp = [(s * x, z) for x, z in pts]
        if s < 0:
            sp = list(reversed(sp))
        cx = sum(p[0] for p in sp) / len(sp)
        cz = sum(p[1] for p in sp) / len(sp)
        inner = [(cx + (x - cx) * 0.72, cz + (z - cz) * 0.72) for x, z in sp]
        w = slab(f"W{nm}{s}", sp, 0.02, color=EDGE)
        paint(w, lambda c, n_: ORANGE if n_.y > 0.5 else EDGE)  # back face orange, so it reads from behind too
        o = slab(f"WO{nm}{s}", inner, 0.02, color=ORANGE)
        paint(o, lambda c, n_: ORANGE_HI if c.z > 0.0 else ORANGE)
        for p in (w, o):
            move(p, (BX, BY - (0.012 if p is o else 0), BZ), (0, 0, s * -18))
        parts += [w, o]
        tip = sp[2]
        parts.append(blob(f"Dot{nm}{s}", 0.014, (BX + tip[0] * 0.95, BY - 0.02, BZ + tip[1] * 0.9), DOT, subdiv=1, jitter=0))
parts.append(tube("Body", [(BX, BY - 0.01, BZ - 0.12), (BX, BY - 0.01, BZ + 0.09)], [0.022, 0.026], EDGE, segs=5))
for s in (-1, 1):
    parts.append(tube(f"Ant{s}", [(BX, BY - 0.01, BZ + 0.08), (BX + s * 0.06, BY - 0.02, BZ + 0.17)], [0.008, 0.008], EDGE, segs=3))
prop_finish("habitat_prop_monarch", parts)
