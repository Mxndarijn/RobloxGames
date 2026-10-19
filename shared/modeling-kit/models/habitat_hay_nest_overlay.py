# habitat_hay_nest_overlay: straw dressing for the crate pad: a ragged straw frame round the mat, a ring of hay
# tufts (big on the corners), straws sticking up out of the tufts and a cream egg tucked in at the back right.
import random
from lib import *
from models._habitat_overlay import *
from models._phoenix_ranch import BUTTER, CREAM

HAY = BUTTER
R = random.Random(5)
parts = [frame("Straw", shade(HAY, 1.02), shade(HAY, 0.72), seed=5, wobble=0.14)]
# r02: 16 tufts (r01's 8 read as sparse dots), corners biggest, slight random lean
for i, (x, y, a) in enumerate(band_spots(16, inset=0.04)):
    corner = i % 4 == 0
    r = 0.64 if corner else (0.5 if i % 2 else 0.44)
    parts.append(blob(f"Tuft{i}", r, (x, y, r * 0.45), shade(HAY, R.uniform(0.86, 1.06)), subdiv=1,
                      squash=(1.3, 1.05, 0.95 if corner else 0.8), jitter=0.08, seed=i, rot=(0, R.uniform(-8, 8), a + 90)))
for i, (x, y, a) in enumerate(band_spots(8, phase=0.5)):
    dx, dy = (x / BAND) * 0.35, (y / BAND) * 0.35
    parts.append(tube(f"Straw{i}", [(x, y, 0.3), (x + dx, y + dy, 1.25 + 0.3 * (i % 2))], [0.13, 0.04],
                      shade(HAY, 1.1), segs=4))
parts.append(blob("Egg", 0.42, (2.2, 3.2, 0.7), CREAM, subdiv=2, squash=(0.8, 0.8, 1.0), jitter=0))
overlay_finish("habitat_hay_nest_overlay", parts)
