# Example: cartoon mushroom (~3.5 studs). Shows cylinder flare, squashed blob cap, bevelled box, spots.
import math
from lib import *

RED, CREAM = rgb(230, 70, 70), rgb(250, 236, 210)
parts = [
    cylinder("Stem", 0.7, 2.0, (0, 0, 0), CREAM, segs=10, r_top=0.5, jitter=0.04, seed=1),
    blob("Cap", 1.7, (0, 0, 2.2), RED, seed=2, subdiv=2, squash=(1, 1, 0.6), jitter=0.03),
]
for k in range(5):  # white spots on the cap
    a = k * math.tau / 5
    parts.append(blob(f"Spot{k}", 0.28, (math.cos(a) * 1.15, math.sin(a) * 1.15, 2.75), CREAM, seed=k, subdiv=1, squash=(1, 1, 0.5), jitter=0))
parts.append(blob("Spot_top", 0.35, (0.1, 0.1, 3.2), CREAM, seed=9, subdiv=1, squash=(1, 1, 0.5), jitter=0))
base = box("Base", (1.6, 1.6, 0.3), (0, 0, 0.15), PALETTE["leaf"])
bevel(base, 0.08)
parts.append(base)
finish("mushroom", parts)
