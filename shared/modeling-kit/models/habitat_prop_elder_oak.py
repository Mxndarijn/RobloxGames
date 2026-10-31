# habitat_prop_elder_oak: an old tree stump with root feet and growth rings, and a round little owl sitting on it.
import math
from lib import *
from models._habitat_prop2 import *

BARK, BARK_D = rgb(156, 108, 74), rgb(124, 86, 60)
RING, RING_D = rgb(240, 204, 150), rgb(206, 162, 108)
OWL, OWL_D = rgb(214, 156, 104), rgb(174, 118, 78)
BELLY = rgb(250, 226, 186)
BEAK = rgb(255, 160, 40)
MOSS = rgb(110, 190, 80)

SH = 0.5  # stump height
parts = [lathe("Stump", [(0.52, 0.0), (0.44, 0.06), (0.4, 0.2), (0.38, SH - 0.02), (0.36, SH)], segs=12,
               col=lambda c, i, k: BARK if k % 2 else BARK_D)]
# top: concentric growth rings as stacked thin discs
for j, (r, col) in enumerate([(0.36, RING), (0.27, RING_D), (0.18, RING), (0.08, RING_D)]):
    parts.append(lathe(f"Ring{j}", [(r, SH - 0.01), (r, SH + 0.006 * j + 0.004), (0.0, SH + 0.006 * j + 0.004)], segs=12, col=col))
# roots: four stubby tubes out from the foot
for j in range(4):
    a = j * math.tau / 4 + 0.6
    c, s = math.cos(a), math.sin(a)
    parts.append(tube(f"Root{j}", [(c * 0.3, s * 0.3, 0.14), (c * 0.5, s * 0.5, 0.06), (c * 0.62, s * 0.58, 0.0)],
                      [0.1, 0.08, 0.04], BARK_D, segs=6))
# moss patch on one side of the top edge and a tiny mushroom
parts.append(blob("Moss", 0.12, (0.28, 0.16, SH), MOSS, subdiv=1, squash=(1.5, 1.0, 0.5), jitter=0.05))
# owl: egg body, cream belly, head with ear tufts, big eyes, beak, wings, feet
OZ = SH + 0.02
parts.append(lathe("OwlBody", [(0.0, OZ), (0.16, OZ + 0.01), (0.22, OZ + 0.1), (0.23, OZ + 0.22), (0.2, OZ + 0.34),
                                (0.21, OZ + 0.42), (0.19, OZ + 0.5), (0.1, OZ + 0.56), (0.0, OZ + 0.57)], segs=12,
                   col=lambda c, i, k: OWL if c.z > OZ + 0.08 else OWL_D))
parts.append(blob("Belly", 0.16, (0, -0.1, OZ + 0.17), BELLY, subdiv=2, squash=(1.0, 0.6, 1.1), jitter=0))
for s in (-1, 1):
    parts.append(cone(f"Tuft{s}", 0.07, 0.14, (0, 0, 0), OWL_D, segs=4))
    move(parts[-1], (s * 0.13, 0.0, OZ + 0.5), (0, s * 22, 0))
    # eye: white disc, black pupil, white catchlight
    ex, ey, ez = s * 0.085, -0.19, OZ + 0.39
    parts.append(lathe(f"EyeW{s}", [(0.0, 0), (0.085, 0), (0.08, 0.03), (0.0, 0.035)], segs=12, col=WHITE))
    move(parts[-1], (ex, ey, ez), (90, 0, 0))
    parts.append(lathe(f"Pupil{s}", [(0.0, 0), (0.045, 0), (0.04, 0.02), (0.0, 0.025)], segs=10, col=BLACK))
    move(parts[-1], (ex + s * 0.008, ey - 0.03, ez - 0.005), (90, 0, 0))
    parts.append(blob(f"Glint{s}", 0.014, (ex + s * 0.008 - 0.015, ey - 0.055, ez + 0.018), WHITE, subdiv=1, jitter=0))
    # wing on the side
    parts.append(blob(f"Wing{s}", 0.14, (s * 0.2, 0.02, OZ + 0.2), OWL_D, subdiv=2, squash=(0.35, 0.8, 1.2), jitter=0,
                      rot=(0, -s * 12, 0)))
    # foot
    for t in (-1, 0, 1):
        parts.append(blob(f"Toe{s}{t}", 0.025, (s * 0.08 + t * 0.03, -0.15, OZ + 0.01), BEAK, subdiv=1, squash=(1, 1.6, 0.7), jitter=0))
parts.append(cone("Beak", 0.04, 0.08, (0, 0, 0), BEAK, segs=4))
move(parts[-1], (0, -0.215, OZ + 0.32), (180, 0, 0))
ship("habitat_prop_elder_oak", parts)
