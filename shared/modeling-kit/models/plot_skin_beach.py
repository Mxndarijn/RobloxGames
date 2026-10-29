# plot_skin_beach: Beach plot decor (replaces the plot's mailbox slot in game).
# The jar theme's beach umbrella at decor size: a coral / butter / turquoise striped umbrella over a striped towel, plus a
# little pink starfish. Built with the Beach jar theme's own prop (models/_goo_jar.py), scaled down.
# ~5.2 x 4.7 x 5.2 studs, origin bottom-centre. Target < ~1000 tris.
import random

import os

os.environ["JAR_THEME"] = "beach"  # before the import: the module's colours are copied into this script
from models._goo_jar import *  # noqa: E402

parts = beach_prop("Umbrella", 0, -90, 0.0, 0.0, random.Random(1))
for k in range(5):  # a starfish on the towel's corner
    sa = k * math.tau / 5 + 0.3
    parts.append(painted(tube(f"Arm{k}", [(1.6, -1.6, 0.35), (1.6 + 0.9 * math.cos(sa), -1.6 + 0.9 * math.sin(sa), 0.3)], [0.32, 0.1], PINK,
                              segs=6), shade(PINK, 0.85), PINK))
parts.append(blob("Middle", 0.35, (1.6, -1.6, 0.38), PINK, subdiv=1, squash=(1, 1, 0.55), jitter=0))
for o in parts:
    o.data.transform(Matrix.Scale(0.65, 4))
finish("plot_skin_beach", parts)
