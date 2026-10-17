# rain_magnet: horseshoe magnet on a barn-wood stand pulling raindrops up (5.6 x 8.2 x 3.4 studs, ~1k tris).
# Runtime-only (RainMagnet): the client stands it on the owner's plot while the Rain Magnet upgrade has a level.
# Front faces -Y, the U lies in the XZ plane (open end up). Origin bottom centre, 1 BU = 1 stud.
import math
from lib import *
from models._phoenix_pad import lathe

WOOD, WOOD_D = rgb(196, 138, 86), rgb(158, 108, 68)
RED, RED_D = rgb(226, 64, 70), rgb(168, 42, 56)
SILVER, SILVER_D = rgb(226, 232, 240), rgb(160, 170, 188)
DROP, DROP_HI = rgb(88, 166, 255), rgb(176, 220, 255)
parts = []
# stand: round foot + post
parts.append(lathe("Foot", [(0, 0), (1.7, 0), (1.85, 0.25), (1.7, 0.55), (0.55, 0.7), (0, 0.7)], segs=14,
                   color_fn=lambda i, k, z: WOOD_D if i < 3 else WOOD))
parts.append(cylinder("Post", 0.5, 2.0, (0, 0, 0.6), WOOD, segs=8, r_top=0.42))
# the U: a half ring from the left pole round the bottom to the right pole (centre (0, 0, 4.0), radius 2.0)
R, CZ = 2.0, 4.0
pts, radii = [], []
n = 12
for i in range(n + 1):
    a = math.pi * (1 + i / n)  # pi..2pi = the lower half
    pts.append((math.cos(a) * R, 0, CZ + math.sin(a) * R + 1.3))
    radii.append(0.78)
parts.append(tube("Arc", pts, radii, RED, segs=8))
for side in (-1, 1):
    x = side * R
    z0 = CZ + 1.3
    parts.append(tube(f"Leg{side}", [(x, 0, z0), (x, 0, z0 + 2.0)], [0.78, 0.78], RED_D, segs=8))
    parts.append(cylinder(f"Pole{side}", 0.84, 0.95, (x, 0, z0 + 2.0), SILVER, segs=8))
    parts.append(cylinder(f"Cap{side}", 0.84, 0.18, (x, 0, z0 + 2.95), SILVER_D, segs=8, r_top=0.6))
# raindrops being pulled up between the poles
for i, (dx, dz, s) in enumerate(((-0.7, 0.0, 0.55), (0.55, 0.5, 0.45), (0.0, 1.5, 0.38))):
    z = 7.4 + dz
    parts.append(blob(f"Drop{i}", s, (dx, 0, z), DROP, subdiv=2, squash=(1, 1, 1.15), jitter=0))
    parts.append(cone(f"DropTip{i}", s * 0.62, s * 1.3, (dx, 0, z + s * 0.75), DROP_HI, segs=6))
finish("rain_magnet", parts)
