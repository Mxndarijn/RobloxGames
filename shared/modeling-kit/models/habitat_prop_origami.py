# habitat_prop_origami: a paper crane mobile: a little wooden T-stand with four folded cranes on threads.
from models._habitat_prop5 import *

WOOD, WOOD_D = P["ranch_wood"], P["ranch_wood_dark"]
THREAD = rgb(240, 236, 226)
PAPER = [rgb(255, 120, 170), rgb(90, 200, 250), rgb(255, 214, 80), rgb(140, 220, 120)]
TOP = 1.2
S = 1.25


def crane(i, x, z, col, flip=1):
    """Side-profile paper crane centred at (x, 0, z), neck to +x * flip."""
    lo, hi = shade(col, 0.82), shade(col, 1.08)
    f = lambda pts: [(u * flip, v) for u, v in pts]
    out = [slab(f"C{i}Body", f([(-0.1, 0), (0, -0.06), (0.11, 0), (0, 0.04)]), 0.09, lo),
           slab(f"C{i}Neck", f([(0.06, 0), (0.12, 0), (0.2, 0.17)]), 0.04, col),
           slab(f"C{i}Head", f([(0.2, 0.17), (0.16, 0.17), (0.27, 0.13)]), 0.04, col),
           slab(f"C{i}Tail", f([(-0.06, 0), (-0.12, 0), (-0.2, 0.15)]), 0.04, col)]
    for s in (-1, 1):
        w = slab(f"C{i}Wing{s}", [(-0.09, 0), (0.07, 0), (-0.02, 0.2)], 0.025, hi)
        out.append(xf(w, (0, s * 0.03, 0.01), (s * -40, 0, 0)))
    for o in out:
        xf(o, (x, 0, z), scale=(S, S, S))
    out.append(rod(f"C{i}Thread", (x, 0, z + 0.03), (x, 0, TOP), 0.012, THREAD, segs=3))
    return out


parts = [
    gbox("Base", (0.5, 0.5, 0.1), (0, 0.22, 0.05), WOOD_D, WOOD, bev=0.03),
    gcyl("Post", 0.05, TOP + 0.04, (0, 0.22, 0.1), WOOD_D, WOOD, segs=6),
    rod("Arm", (0, 0.22, TOP), (0, 0, TOP), 0.035, WOOD),
    rod("Bar", (-0.74, 0, TOP), (0.74, 0, TOP), 0.035, WOOD),
    blob("Knob", 0.07, (0, 0.22, TOP + 0.1), WOOD_D, subdiv=1, jitter=0),
]
for sx in (-1, 1):
    parts.append(blob(f"End{sx}", 0.05, (sx * 0.76, 0, TOP), WOOD_D, subdiv=1, jitter=0))
for i, (x, z, flip) in enumerate(((-0.62, 0.56, 1), (-0.24, 0.8, -1), (0.24, 0.46, 1), (0.62, 0.72, -1))):
    parts += crane(i, x, z, PAPER[i], flip)
ship("habitat_prop_origami", parts)
