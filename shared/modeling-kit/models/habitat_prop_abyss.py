# habitat_prop_abyss: signature prop for Abyss: a chunky dark-blue lantern fish (big toothy mouth, big eye, forked
# tail) held up on a coral stalk over a rock, its glowing yellow lure dangling in front. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

BLUE_D, BLUE, BLUE_HI = rgb(44, 66, 150), rgb(66, 102, 196), rgb(104, 146, 230)
MOUTH, TOOTH, EYE, PUPIL = rgb(150, 40, 90), rgb(250, 248, 240), rgb(250, 250, 255), rgb(24, 28, 50)
LURE, LURE_HI = rgb(255, 214, 40), rgb(255, 250, 170)
ROCK, ROCK_HI, CORAL = rgb(118, 108, 150), rgb(150, 140, 186), rgb(96, 210, 220)

FZ, TURN = 0.66, -32  # fish centre height, turn (head toward front-right)
fish = []
body = blob("Body", 0.34, (0, 0, 0), BLUE, subdiv=2, squash=(1.3, 0.85, 1.0), jitter=0.03, seed=2)
paint(body, lambda c, n: BLUE_HI if n.z > 0.55 else (BLUE_D if n.z < -0.35 else BLUE))
fish.append(body)
fish.append(blob("Mouth", 0.22, (0.36, 0, -0.06), MOUTH, subdiv=1, squash=(0.45, 0.85, 0.7), jitter=0))
for k in range(4):  # teeth: down from the top lip and up from the bottom
    y = -0.15 + k * 0.1
    fish.append(cone(f"TT{k}", 0.035, 0.11, (0.43, y, 0.06), TOOTH, segs=4, rot=(180, 0, 0)))
    fish.append(cone(f"TB{k}", 0.03, 0.09, (0.42, y + 0.05, -0.2), TOOTH, segs=4))
for s in (-1, 1):
    fish.append(blob(f"Eye{s}", 0.12, (0.2, s * 0.2, 0.12), EYE, subdiv=1, jitter=0, squash=(1, 0.7, 1)))
    fish.append(blob(f"Pup{s}", 0.065, (0.24, s * 0.27, 0.13), PUPIL, subdiv=1, jitter=0, squash=(1, 0.6, 1)))
    fish.append(slab(f"Pect{s}", [(0, 0), (-0.2, -0.08), (-0.16, 0.08)], 0.04, pos=(0.0, s * 0.27, -0.06), rot=(0, 0, s * 15), color=BLUE_HI))
fish.append(slab("Tail", [(0, 0), (-0.3, 0.24), (-0.22, 0.0), (-0.3, -0.22)], 0.07, pos=(-0.4, 0, 0.02), color=BLUE_HI))
fish.append(slab("Dorsal", [(-0.2, 0), (0.05, 0), (-0.15, 0.16)], 0.05, pos=(-0.08, 0, 0.3), color=BLUE_HI))
# lure: stalk from the forehead arching forward, glowing bulb with a light halo
lure_pts = [(0.12, 0, 0.3), (0.22, 0, 0.5), (0.42, 0, 0.58), (0.58, 0, 0.5), (0.62, 0, 0.38)]
fish.append(tube("Stalk", lure_pts, [0.03, 0.026, 0.022, 0.02, 0.018], BLUE_HI, segs=5))
fish.append(blob("Bulb", 0.11, (0.62, 0, 0.29), LURE, subdiv=2, jitter=0))
fish.append(blob("Glow", 0.06, (0.6, -0.06, 0.33), LURE_HI, subdiv=1, jitter=0))
for o in fish:
    move(o, (0.05, 0.05, FZ), (0, 0, TURN))

parts = fish
# rock base + coral stalk holding the fish
rock = blob("Rock", 0.4, (-0.05, 0.08, 0.0), ROCK, subdiv=1, squash=(1.3, 1.0, 0.55), jitter=0.12, seed=5)
gradient(rock, shade(ROCK, 0.9), ROCK_HI)
parts.append(floor(rock))
parts.append(tube("Stalk2", [(-0.05, 0.08, 0.15), (0.0, 0.06, 0.32), (0.02, 0.05, FZ - 0.2)], [0.07, 0.06, 0.05], CORAL, segs=6))
parts.append(blob("Bud", 0.07, (-0.32, -0.08, 0.2), CORAL, subdiv=1, jitter=0.1))
prop_finish("habitat_prop_abyss", parts)
