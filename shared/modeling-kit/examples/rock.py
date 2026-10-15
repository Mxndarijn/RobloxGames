# Example: lumpy boulder cluster (~4 studs). Shows blob + noise lumps + gradient + finish.
from lib import *

ROCK = PALETTE["rock"]
parts = [
    blob("Boulder", 2.0, (0, 0, 1.3), seed=1, subdiv=3, squash=(1.1, 1.0, 0.7), jitter=0.04, lumps=0.18, lump_scale=1.6),
    blob("Slab0", 1.0, (1.9, 0.6, 0.45), seed=2, subdiv=2, squash=(1.2, 1, 0.55), jitter=0.12),
    blob("Slab1", 0.8, (-1.6, -1.0, 0.35), seed=3, subdiv=2, squash=(1, 1.2, 0.6), jitter=0.12),
]
for o in parts:
    gradient(o, shade(ROCK, 0.7), shade(ROCK, 1.15))
finish("rock", parts)
