# habitat_barn_crate: red-braced wooden crate (7.8 x 4.2 x 7.8), lid planks flat at z=2.4 for the slime, corner posts and hay wisps at the rim.
import math
from lib import *
from models._habitat import *

W, H = 7.8, 4.2
parts = []
S = 7.0
# body
parts.append(bbox("Body", (S, S, 2.0), (0, 0, 1.0), shade(WOOD_D, 0.9), WOOD, bev=0))
# lid: inset planks, top exactly at SEAT
parts.append(bbox("Lid", (S - 0.4, S - 0.4, 0.4), (0, 0, SEAT - 0.2), shade(WOOD, 0.9), mix(WOOD, CREAM, 0.2), bev=0))
for i in (-1, 1):
    parts.append(bbox(f"Seam{i}", (0.1, S - 0.5, 0.02), (i * 1.15, 0, SEAT + 0.005), WOOD_D, WOOD_D, bev=0))
# red edge rails around the lid top (low, rim only)
for i in range(4):
    a = i * math.pi / 2
    parts.append(bbox(f"Rail{i}", (S + 0.1, 0.5, 0.55), (math.cos(a) * (S / 2 - 0.2), math.sin(a) * (S / 2 - 0.2), 2.05 - 0.1),
                      ROOF_D, ROOF, bev=0, rot=(0, 0, math.degrees(a) + 90)))
# corner posts proud of the lid
for i, (sx, sy) in enumerate(((1, 1), (1, -1), (-1, -1), (-1, 1))):
    parts.append(bbox(f"Post{i}", (0.9, 0.9, 3.3), (sx * 3.2, sy * 3.2, 1.65), shade(WOOD_D, 0.85), WOOD_D, bev=0))
    parts.append(bbox(f"Cap{i}", (1.1, 1.1, 0.35), (sx * 3.2, sy * 3.2, 3.45), shade(CREAM, 0.9), CREAM, bev=0))
# plank gaps on the four sides (dark grooves) and a cream corner strip
for i in range(4):
    a = i * math.pi / 2
    for g in (-2.1, -0.7, 0.7, 2.1):
        parts.append(bbox(f"Gap{i}_{g}", (0.12, 0.1, 1.9), (math.cos(a) * (S / 2 + 0.02) - math.sin(a) * g, math.sin(a) * (S / 2 + 0.02) + math.cos(a) * g, 0.95),
                          WOOD_D, WOOD_D, bev=0, rot=(0, 0, math.degrees(a) + 90)))
# hay wisps poking out at the back rim
for i, x in enumerate((-1.6, -0.2, 1.4)):
    parts.append(blob(f"Hay{i}", 0.5, (x, 3.0, SEAT + 0.3 + 0.2 * (i % 2)), BUTTER, subdiv=1, squash=(1.3, 1, 1), jitter=0.06, seed=i))
fit(finish("habitat_barn_crate", parts), W, H, W)
