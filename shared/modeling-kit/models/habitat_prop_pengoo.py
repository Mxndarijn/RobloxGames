# habitat_prop_pengoo: a small snow igloo with block lines and an entrance tunnel facing the walkway.
import math
from models._habitat_prop3 import *

LINE = rgb(176, 206, 236)
parts = []
R0, H = 0.62, 0.78
ROWS, SEGS = 6, 16


def block_col(i, k, z):
    # staggered ice blocks: every other column of faces in a row is a shade, plus a blue mortar at the row starts
    if i >= ROWS - 1:
        return SNOW
    return mix(SNOW_LO, SNOW, 0.55 + 0.45 * ((k + i) % 2)) if i % 1 == 0 else SNOW


prof = [(0, 0)] + [(R0 * math.cos(math.pi / 2 * j / ROWS), H * math.sin(math.pi / 2 * j / ROWS)) for j in range(ROWS)] + [(0, H)]
dome = lathe("Dome", prof, segs=SEGS, phase=0.1, color_fn=lambda i, k, z: block_col(i - 1, k, z) if i > 0 else SNOW_LO)
xf(dome, (0, 0.05, 0), (0, 0, 0), (1.3, 0.85, 1.0))
parts.append(dome)
# mortar rings: thin blue bands between the rows
for j in range(1, ROWS - 1):
    a = math.pi / 2 * j / ROWS
    r, z = R0 * math.cos(a), H * math.sin(a)
    ring = lathe(f"Mortar{j}", [(0, z - 0.012), (r + 0.012, z - 0.012), (r + 0.012, z + 0.012), (0, z + 0.012)], segs=SEGS, phase=0.1,
                 color_fn=lambda i, k, zz: LINE)
    parts.append(xf(ring, (0, 0.05, 0), (0, 0, 0), (1.3, 0.85, 1.0)))
# entrance tunnel: half-cylinder arch toward -Y with a dark doorway
tun = lathe("Tunnel", [(0, -0.05), (0.3, -0.05), (0.3, 0.1), (0.3, 0.28), (0, 0.28)], segs=12,
            color_fn=lambda i, k, z: SNOW if i != 0 else SNOW_LO)
xf(tun, (0, -0.28, 0), (90, 0, 0))
# clip the tunnel's lower half (it's a full cylinder lying along Y): flatten everything under z = 0
parts.append(floor(tun))
parts.append(floor(xf(cylinder("Door", 0.21, 0.06, (0, 0, 0), rgb(78, 108, 170), segs=12), (0, -0.5, 0), (90, 0, 0))))
for j in range(5):  # block seams over the arch
    a = math.pi * (j + 0.5) / 5
    parts.append(box(f"Arch{j}", (0.02, 0.24, 0.02), (math.cos(a) * 0.305, -0.42, math.sin(a) * 0.305), LINE, rot=(0, -math.degrees(a), 0)))
# snow drift bits in front
parts.append(floor(blob("Drift", 0.18, (-0.55, -0.3, 0.0), SNOW, subdiv=1, squash=(1.4, 1, 0.6), jitter=0.1, seed=1)))
parts.append(floor(blob("Drift2", 0.13, (0.58, -0.28, 0.0), SNOW, subdiv=1, squash=(1.4, 1, 0.6), jitter=0.1, seed=2)))
ship("habitat_prop_pengoo", parts)
