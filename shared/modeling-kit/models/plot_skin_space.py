# plot_skin_space: Space plot decor (replaces the plot's mailbox slot in game).
# The jar theme's little rocket on a round periwinkle launch pad with two cyan landing lights. Built with the Space jar
# theme's own prop (models/_goo_jar.py), scaled down a little.
# ~4.4 x 7.2 x 4.4 studs, origin bottom-centre. Target < ~1000 tris.
import random

import os

os.environ["JAR_THEME"] = "space"  # before the import: the module's colours are copied into this script
from models._goo_jar import *  # noqa: E402

parts = [painted(cylinder("Pad", 2.6, 0.5, (0, 0, 0), WOOD, segs=16), shade(WOOD, 0.85), WOOD),
         cylinder("PadRing", 2.2, 0.08, (0, 0, 0.5), METAL, segs=16)]
for k, a in enumerate((0.5, 3.6)):
    parts.append(blob(f"Light{k}", 0.28, (2.3 * math.cos(a), 2.3 * math.sin(a), 0.55), GOO, subdiv=1, jitter=0))
rocket = space_prop("Rocket", 0, -90, 0.0, 0.0, random.Random(2))
for o in rocket:
    o.data.transform(Matrix.Translation((0, 0, 0.45)))
parts += rocket
for o in parts:
    o.data.transform(Matrix.Scale(0.85, 4))
finish("plot_skin_space", parts)
