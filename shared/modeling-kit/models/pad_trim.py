# pad_trim: slime-pad plinth (replaces v17 pad_trim). Footprint 9.4 x 9.4 like the old mesh.
# Modelled at its in-game height 1.8 (WorldLayout.PAD_TRIM_HEIGHT): Detail.luau scales Y by
# 1.8 / native height, so a 1.8-tall mesh is shown 1:1 instead of a 0.3 slab stretched 6x.
# The pad (9.6 wide, top at 3.0) sits on it; nothing may rise above 1.8 or outside 9.4.
# Game tints it mix(plotAccent, white, 0.85), so keep vertex colours light: value contrast only.
import math
from lib import *

W, H = 9.4, 1.8
GOO, STONE, FOOT = rgb(252, 252, 248), rgb(184, 180, 176), rgb(142, 138, 136)
parts = []


def ring(name, w, h, z, t, color, bev=0.0):
    """Square frame of four bevelled boxes (outer size w, wall t), base at z."""
    out = []
    for k, (sx, sy, px, py) in enumerate(((w, t, 0, (w - t) / 2), (w, t, 0, -(w - t) / 2),
                                          (t, w - 2 * t, (w - t) / 2, 0), (t, w - 2 * t, -(w - t) / 2, 0))):
        b = box(f"{name}{k}", (sx, sy, h), (px, py, z + h / 2), color)
        if bev:
            bevel(b, bev)
        out.append(b)
    return out


for o in ring("Foot", W, 0.35, 0.0, 0.9, FOOT):
    gradient(o, shade(FOOT, 0.9), FOOT)
    parts.append(o)
for o in ring("Body", W - 0.5, 1.2, 0.3, 0.7, STONE):
    gradient(o, shade(STONE, 0.86), STONE)
    parts.append(o)
parts += ring("Lip", W - 0.1, 0.32, H - 0.32, 0.8, GOO, bev=0.1)
# corner pillars: full height, rounded tops just under the lip line
for i, (x, y) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
    c = (W / 2 - 0.55)
    p = cylinder(f"Post{i}", 0.55, H - 0.05, (x * c, y * c, 0), STONE, segs=8)
    gradient(p, shade(STONE, 0.86), shade(STONE, 1.08))
    parts.append(p)
# goo drips running down from the lip on each side (inside the 9.4 footprint)
DRIPS = [(-2.3, 0.6), (0.4, 0.9), (2.7, 0.5)]  # 3 per side: placed 64x per map, keep it cheap
for side in range(4):
    a = side * math.pi / 2
    ca, sa = math.cos(a), math.sin(a)
    for j, (u, length) in enumerate(DRIPS):
        u = u * (1 if side % 2 == 0 else -1)
        d = (W - 0.5) / 2 - 0.02
        x, y = ca * d - sa * u, sa * d + ca * u
        top, bot = H - 0.3, H - 0.32 - length
        o = (ca, sa, 0)
        parts.append(tube(f"Drip{side}_{j}", [(x - ca * 0.12, y - sa * 0.12, top), (x, y, top - 0.15), (x, y, bot + 0.2)],
                          [0.26, 0.21, 0.19], GOO, segs=5))
        parts.append(blob(f"Bulb{side}_{j}", 0.28, (x + ca * 0.02, y + sa * 0.02, bot + 0.18), GOO, seed=side * 10 + j,
                          subdiv=1, squash=(1, 1, 1.15), jitter=0.0))
finish("pad_trim", parts)
