# plot_skin_winter: Winter plot decor (replaces the plot's mailbox slot in game).
# The jar theme's snowman on a snow drift: red-and-cream knitted scarf and bobble hat, a lantern-goo carrot nose, stick
# arms. Built with the Winter jar theme's own prop (models/_goo_jar.py).
# ~4.2 x 6.8 x 4.4 studs, origin bottom-centre. Target < ~1000 tris.
import random

import os

os.environ["JAR_THEME"] = "winter"  # before the import: the module's colours are copied into this script
from models._goo_jar import *  # noqa: E402

parts = winter_prop("Snowman", 1, -90, 0.0, 0.0, random.Random(4))
parts.append(painted(blob("Drift", 2.1, (0, 0, 0.05), SNOW, subdiv=2, squash=(1.1, 1.05, 0.25), jitter=0.05, seed=3), mix(SNOW, GLASS, 0.5), SNOW))
finish("plot_skin_winter", parts)
