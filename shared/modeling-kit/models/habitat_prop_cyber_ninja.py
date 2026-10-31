# habitat_prop_cyber_ninja: a small neon sign: dark board on two legs, hot-pink shuriken in a cyan neon frame.
from models._habitat_prop5 import *

BOARD, BOARD_HI = rgb(44, 42, 78), rgb(74, 70, 120)
PINK, CYAN = rgb(255, 70, 190), rgb(60, 240, 255)
LEG = rgb(90, 90, 120)
W, Z0, Z1 = 1.5, 0.34, 1.24
ZC = (Z0 + Z1) / 2
parts = []
for sx in (-1, 1):
    parts.append(gbox(f"Leg{sx}", (0.1, 0.1, Z0 + 0.1), (sx * 0.5, 0.06, (Z0 + 0.1) / 2), LEG, bev=0.02))
    parts.append(gbox(f"Foot{sx}", (0.18, 0.5, 0.06), (sx * 0.5, 0.06, 0.03), LEG, bev=0.02))
parts.append(gbox("Board", (W, 0.12, Z1 - Z0), (0, 0.06, ZC), BOARD, BOARD_HI, bev=0.04))
# neon frame: four tubes just in front of the board
ix, iz = W / 2 - 0.1, (Z1 - Z0) / 2 - 0.1
corners = [(-ix, ZC - iz), (ix, ZC - iz), (ix, ZC + iz), (-ix, ZC + iz)]
for k in range(4):
    (x0, z0), (x1, z1) = corners[k], corners[(k + 1) % 4]
    parts.append(rod(f"Neon{k}", (x0, -0.03, z0), (x1, -0.03, z1), 0.035, CYAN, segs=6))
for k, (x, z) in enumerate(corners):
    parts.append(blob(f"NeonC{k}", 0.036, (x, -0.03, z), CYAN, subdiv=1, jitter=0))
# shuriken: 4-point star with a dark hub
parts.append(slab("Shuriken", star_pts(4, 0.32, 0.1, cz=ZC, phase=0.4), 0.06, PINK, (0, -0.02, 0)))
parts.append(slab("Hub", circle_pts(0.06, 8, cz=ZC), 0.08, BOARD, (0, -0.04, 0)))
# short neon bars either side (the sign's "text")
for sx in (-1, 1):
    for j, dz in enumerate((0.12, -0.12)):
        parts.append(rod(f"Txt{sx}{j}", (sx * 0.42, -0.03, ZC + dz), (sx * 0.58, -0.03, ZC + dz), 0.028, PINK if j else CYAN, segs=5))
ship("habitat_prop_cyber_ninja", parts)
