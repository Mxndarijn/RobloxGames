# habitat_prop_imp: a little red devil's pitchfork stuck at a slant in a grey rock.
import math
from models._habitat_prop3 import *

RED, RED_LO, RED_HI = rgb(236, 44, 52), rgb(176, 26, 40), rgb(255, 104, 96)
parts = []
rock = blob("Rock", 0.5, (0, 0.05, 0.05), ROCK, subdiv=2, squash=(1.35, 0.95, 0.7), jitter=0.12, lumps=0.15, seed=11)
parts.append(grad(floor(rock), ROCK_LO, rgb(196, 186, 176)))
parts.append(floor(blob("Pebble", 0.16, (0.68, -0.25, 0.02), ROCK_LO, subdiv=1, jitter=0.12, seed=3)))
parts.append(floor(blob("Pebble2", 0.11, (-0.7, -0.2, 0.02), ROCK, subdiv=1, jitter=0.12, seed=4)))
# crack in the rock where the fork goes in
parts.append(floor(blob("Chip", 0.09, (-0.12, -0.36, 0.25), ROCK_LO, subdiv=1, jitter=0.15, seed=8)))
# the fork, built upright then leaned: handle, crossbar, three barbed prongs (cut-outs, front-facing)
fork = []
fork.append(cylinder("Shaft", 0.07, 0.9, (0, 0, 0.0), RED, segs=6))
fork.append(blob("Knob", 0.1, (0, 0, -0.02), RED_LO, subdiv=1, jitter=0))
bar = prism("Bar", [(-0.3, 0.84), (0.3, 0.84), (0.3, 0.98), (0.22, 1.01), (-0.22, 1.01), (-0.3, 0.98)], -0.065, 0.065, RED)
fork.append(bar)
for i, x in enumerate((-0.25, 0.0, 0.25)):
    h = 1.32 if x == 0 else 1.24
    pts = [(x - 0.055, 0.96), (x + 0.055, 0.96), (x + 0.055, h - 0.2), (x + 0.13, h - 0.24), (x, h), (x - 0.13, h - 0.24), (x - 0.055, h - 0.2)]
    fork.append(prism(f"Prong{i}", pts, -0.06, 0.06, RED_HI))
for o in fork:
    xf(o, (0.06, 0.0, -0.05), (0, 16, 0))  # lean right, foot buried inside the rock
    parts.append(o)
parts = [floor(p) for p in parts]
ship("habitat_prop_imp", parts)
