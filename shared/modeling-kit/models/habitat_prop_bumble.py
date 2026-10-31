# habitat_prop_bumble: a little striped straw skep beehive with a round door and one chubby bee buzzing by.
import math
from lib import *
from models._habitat_prop2 import *

STRAW, STRAW_D = rgb(255, 204, 80), rgb(226, 150, 50)
BEE_Y = rgb(255, 214, 40)

# skep: coil bands, each band bulges out at its middle (two rings per band), dome top
prof = [(0.5, 0.0)]
H, N = 1.0, 6
for i in range(N):
    t0, t1 = i / N, (i + 1) / N
    for t, bulge in ((t0 + 0.02, 0.0), ((t0 + t1) / 2, 0.06)):
        z = t * H
        r = 0.5 * math.cos(min(t, 0.999) ** 1.6 * math.pi / 2) ** 0.6 + bulge
        prof.append((max(r, 0.08), z))
prof += [(0.16, H + 0.02), (0.0, H + 0.07)]


def band(c, i, k):
    z = c.z
    band_i = int(z / (H / N))
    return STRAW if band_i % 2 == 0 else STRAW_D


parts = [lathe("Skep", prof, segs=14, col=band)]
# board under it
b = box("Board", (1.2, 1.05, 0.08), (0, 0, 0.04), WOOD)
bevel(b, 0.03)
parts.append(b)
# door: dark arch on the front
door = lathe("Door", [(0.0, -0.1), (0.17, -0.1), (0.17, 0.02), (0.0, 0.02)], segs=12, col=rgb(96, 54, 36))
move(door, (0, -0.49, 0.27), rot=(90, 0, 0), scale=(1, 1.15, 1))
parts.append(door)
# bee: striped body (lathe along Y), head, wings, stinger, hovering front-right
def bee_band(c, i, k):
    return BLACK if int((c.z + 0.2) / 0.1) % 2 else BEE_Y


bee = lathe("Bee", [(0.0, -0.2), (0.1, -0.17), (0.15, -0.1), (0.16, 0.0), (0.15, 0.08), (0.11, 0.15), (0.0, 0.19)],
            segs=10, col=bee_band)
BC = (0.62, -0.22, 0.98)
D = (-math.sin(math.radians(70)), -math.cos(math.radians(70)))  # bee faces front-left, toward the door
PP = (-D[1], D[0])  # perpendicular (to the bee's right/left)
parts.append(move(bee, BC, rot=(90, 0, -70)))
parts.append(blob("BeeHead", 0.12, (BC[0] + D[0] * 0.25, BC[1] + D[1] * 0.25, BC[2] + 0.02), BLACK, subdiv=2, jitter=0))
for s in (-1, 1):
    w = blob(f"Wing{s}", 0.17, (0, 0, 0), rgb(220, 244, 255), subdiv=2, squash=(1.0, 0.5, 0.12), jitter=0)
    parts.append(move(w, (BC[0] + PP[0] * s * 0.13, BC[1] + PP[1] * s * 0.13, BC[2] + 0.17), rot=(0, -s * 25, -70)))
    parts.append(blob(f"Eye{s}", 0.045, (BC[0] + D[0] * 0.34 + PP[0] * s * 0.06, BC[1] + D[1] * 0.34 + PP[1] * s * 0.06, BC[2] + 0.06),
                      WHITE, subdiv=1, jitter=0))
sting = cone("Sting", 0.045, 0.12, (0, 0, 0), BLACK, segs=5)
parts.append(move(sting, (BC[0] - D[0] * 0.18, BC[1] - D[1] * 0.18, BC[2]), rot=(90, 0, 110)))
ship("habitat_prop_bumble", parts)
