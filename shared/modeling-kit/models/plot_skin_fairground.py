# plot_skin_fairground: Fairground plot decor (replaces the plot's mailbox slot in game).
# The jar theme's fair pole at decor size: a coral pole with butter bands on a teal foot, a gold knob, three balloons on
# strings, and a little pennant flag. Built with the Fairground jar theme's own prop (models/_goo_jar.py), scaled down.
# ~2.6 x 7.6 x 1.5 studs, origin bottom-centre. Target < ~1000 tris.
import random

import os

os.environ["JAR_THEME"] = "fairground"  # before the import: the module's colours are copied into this script
from models._goo_jar import *  # noqa: E402

parts = fair_pole("Fair", 0, -90, 0.0, 0.0, random.Random(3))
parts.append(cone("Flag", 0.45, 1.1, (0.0, 0.0, FAIR_POLE_H - 0.6), AWNING[1], segs=3, rot=(0, 90, 0)))
for o in parts:
    o.data.transform(Matrix.Scale(0.6, 4))
finish("plot_skin_fairground", parts)
