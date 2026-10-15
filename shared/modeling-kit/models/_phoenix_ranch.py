# Phoenix shared helpers for Slime Ranch plot kit (not an asset). 1 BU = 1 stud, Z up, outer face -Y.
# Plot side 80 = gate piece 20 + 6 x fence segment 10. Walls 8 tall, gate clear 14.
import random
from lib import *
P = PALETTE
WOOD, WOOD_D = P["ranch_wood"], P["ranch_wood_dark"]
CREAM, ROOF, ROOF_D = P["ranch_cream"], P["ranch_roof"], P["ranch_roof_dark"]
GOO, GOO_HI, BUTTER, PINK = P["ranch_goo"], P["ranch_goo_hi"], P["ranch_butter"], P["ranch_pink"]
SEG, WALL_H, GATE_CLEAR = 10.0, 8.0, 14.0
POST_W = 1.4

def bbox(name, size, pos, lo, hi, bev=0.12, rot=(0, 0, 0)):
    o = box(name, size, pos, hi, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, lo, hi)
    return o

def rpost(name, x, y, h, w=POST_W):
    """Chunky bevelled post + cream cap + rounded knob."""
    out = [bbox(name, (w, w, h), (x, y, h / 2), shade(WOOD_D, 0.92), WOOD_D, bev=0.15)]
    out.append(bbox(name + "Cap", (w + 0.4, w + 0.4, 0.4), (x, y, h + 0.2), shade(CREAM, 0.9), CREAM, bev=0.12))
    out.append(blob(name + "Knob", w * 0.42, (x, y, h + 0.55), CREAM, subdiv=1, squash=(1, 1, 0.8), jitter=0))
    return out

def board_wall(prefix, x0, x1, h, seed=1):
    """Horizontal plank wall between posts: uneven boards + cream top rail, slight tilts."""
    R = random.Random(seed)
    out, z, n = [], 0.15, 6
    bh = (h - 0.9) / n
    for i in range(n):
        th = bh - 0.14
        col = WOOD if i % 2 else shade(WOOD, 0.94)
        out.append(bbox(f"{prefix}B{i}", (x1 - x0 - 0.05, 0.5, th), ((x0 + x1) / 2, R.uniform(-0.03, 0.03), z + bh / 2),
                        shade(col, 0.9), col, bev=0.1, rot=(R.uniform(-0.4, 0.4), 0, 0)))
        z += bh
    out.append(bbox(prefix + "Rail", (x1 - x0 + 0.2, 0.8, 0.5), ((x0 + x1) / 2, 0, h - 0.5), shade(CREAM, 0.88), CREAM))
    # back battens (inner side) so the plot side reads as framed too
    for k, x in enumerate((x0 + (x1 - x0) * 0.33, x0 + (x1 - x0) * 0.67)):
        out.append(bbox(f"{prefix}Bat{k}", (0.6, 0.3, h - 0.9), (x, 0.38, (h - 0.6) / 2 + 0.15), shade(WOOD_D, 0.95), WOOD_D, bev=0.06))
    return out
