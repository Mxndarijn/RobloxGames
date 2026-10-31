# habitat_prop_narwhal: signature prop for Narwhal: two snowy ice floe chunks on a patch of blue sea with a crack
# of open water between them, a little orange fish leaping out of the crack with a splash. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

ICE, ICE_LO, SNOW = rgb(176, 226, 255), rgb(110, 186, 240), rgb(250, 253, 255)
WATER, WATER_HI = rgb(40, 140, 235), rgb(110, 200, 255)
FISH, FISH_HI, EYE = rgb(255, 130, 40), rgb(255, 196, 70), rgb(40, 40, 60)


def floe(name, pts, top):
    """Flat chunk: outline (x, -y) extruded from z 0.04 up to `top`."""
    o = slab(name, pts, top - 0.04, rot=(90, 0, 0), color=ICE)
    move(o, (0, 0, (top + 0.04) / 2))
    return paint(o, lambda c, n: SNOW if n.z > 0.7 else (ICE if c.z > top * 0.55 else ICE_LO))


parts = []
sea = lathe("Sea", [(0.0, 0.0), (0.9, 0.0), (0.88, 0.06), (0.0, 0.06)], segs=16, squash=(1.0, 0.62, 1.0))
paint(sea, lambda c, n: WATER_HI if n.z < 0.5 else WATER)
parts.append(sea)
# left floe (big), right floe (smaller); the gap between is the crack (outline points are (x, -y))
L = [(-0.82, 0.05), (-0.7, 0.3), (-0.4, 0.42), (-0.12, 0.36), (-0.06, 0.1), (-0.14, -0.12), (-0.04, -0.34), (-0.3, -0.44), (-0.66, -0.3)]
R = [(0.1, 0.36), (0.42, 0.42), (0.74, 0.22), (0.8, -0.08), (0.6, -0.36), (0.24, -0.4), (0.14, -0.2), (0.06, 0.08)]
L = [(x * 0.92 - 0.05, z) for x, z in L]
R = [(x * 0.92 + 0.05, z) for x, z in R]
parts.append(floe("FloeL", list(reversed(L)), 0.32))
parts.append(floe("FloeR", list(reversed(R)), 0.24))
# snow lumps
for i, (x, y, z, r) in enumerate(((-0.5, 0.1, 0.32, 0.2), (-0.3, -0.18, 0.32, 0.13), (0.5, 0.05, 0.24, 0.16))):
    b = blob(f"Snow{i}", r, (x, y, z), SNOW, subdiv=2, squash=(1.3, 1.1, 0.5), jitter=0.06, seed=i)
    gradient(b, shade(SNOW, 0.93), SNOW)
    parts.append(b)
# small ice shards standing on the left floe
parts.append(cylinder("Shard", 0.08, 0.32, (-0.62, 0.2, 0.3), ICE, segs=5, r_top=0.0))
parts.append(cylinder("Shard2", 0.06, 0.2, (-0.48, 0.28, 0.3), shade(ICE, 1.05), segs=5, r_top=0.0, rot=(0, 18, 0)))
# leaping fish over the crack, arched, head up-right
FX, FY, FZ = 0.0, -0.08, 0.68
fish = []
body = blob("Fish", 0.15, (0, 0, 0), FISH, subdiv=2, squash=(1.5, 0.75, 1.0), jitter=0)
paint(body, lambda c, n: FISH_HI if n.z > 0.3 else FISH)
fish.append(body)
fish.append(slab("Tail", [(0, 0), (-0.17, 0.13), (-0.12, 0.0), (-0.17, -0.13)], 0.05, pos=(-0.2, 0, 0), color=FISH_HI))
fish.append(slab("Fin", [(-0.08, 0), (0.06, 0), (-0.06, 0.09)], 0.04, pos=(0, 0, 0.13), color=FISH_HI))
fish.append(blob("EyeW", 0.05, (0.13, -0.075, 0.04), SNOW, subdiv=1, jitter=0, squash=(1, 0.6, 1)))
fish.append(blob("Eye", 0.03, (0.14, -0.1, 0.04), EYE, subdiv=1, jitter=0))
for o in fish:
    move(o, (FX, FY, FZ), (0, -35, 0))
parts += fish
# splash ring + droplets in the crack
parts.append(torus("Splash", 0.11, 0.04, seg=12, seg2=4, pos=(-0.02, -0.12, 0.1), color=SNOW))
for i, (x, y, z, r) in enumerate(((-0.2, -0.08, 0.3, 0.04), (0.12, -0.12, 0.34, 0.035), (-0.12, -0.15, 0.44, 0.03))):
    parts.append(blob(f"Drop{i}", r, (x, y, z), WATER_HI, subdiv=1, jitter=0))
prop_finish("habitat_prop_narwhal", parts)
