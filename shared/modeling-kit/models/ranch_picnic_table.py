# ranch_picnic_table: chunky plank picnic table with attached benches on A-frame legs (Slime Ranch).
# Long axis X (8 studs), benches at +-Y, top 3.0 high, seats 1.75. Front (-Y) shows the bench side.
# Small metaball goo spill on the top running over the front edge.
import math
from mathutils import Vector
from lib import *
from lib.goo import Ball, frame_quat, metaball_mesh, paint_goo

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL = PALETTE["ranch_cream"], PALETTE["ranch_metal"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
WOOD_LO = mix(WOOD_D, WOOD, 0.45)
WOOD_HI = mix(WOOD, CREAM, 0.15)
parts = []


def pbox(name, size, pos, bot, top, bev=0.08, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


L = 8.0
TZ = 3.0          # table top surface
TT = 0.42         # plank thickness
SZ = 1.75         # seat surface
BY = 2.35         # bench centre |y|
LX = L / 2 - 1.3  # leg frames x

# --- top: 5 planks along X, slightly uneven ---
for i, (y, dz, k) in enumerate(zip((-1.32, -0.66, 0.0, 0.66, 1.32), (0, 0.03, -0.01, 0.02, 0), (1, 1.05, .97, 1.04, 1))):
    parts.append(pbox(f"Top{i}", (L - (0.1 if i % 2 else 0), 0.6, TT), (0.03 * (i - 2), y, TZ - TT / 2 + dz),
                      shade(WOOD_LO, k), shade(WOOD_HI, k)))
# --- benches: 2 planks each side ---
for s in (-1, 1):
    for j, dy in enumerate((-0.33, 0.33)):
        parts.append(pbox(f"Seat{s}{j}", (L - 0.4, 0.6, 0.4), (0, s * BY + dy, SZ - 0.2),
                          WOOD_LO, shade(WOOD_HI, 1.0 if j else 0.96)))
# --- A-frame leg sets ---
foot_y, top_y = 2.0, 0.75
dy, dz = foot_y - top_y, TZ - TT
ang = math.degrees(math.atan2(dy, dz))
ln = math.hypot(dy, dz) + 0.25
for sx in (-1, 1):
    x = sx * LX
    for s in (-1, 1):
        parts.append(pbox(f"Leg{sx}{s}", (0.5, 0.5, ln), (x, s * (foot_y + top_y) / 2, dz / 2),
                          WOOD_D, WOOD, bev=0.07, rot=(s * ang, 0, 0)))
    # cleat under the top and bench beam across both benches
    parts.append(pbox(f"Cleat{sx}", (0.5, 3.1, 0.4), (x, 0, TZ - TT - 0.2), WOOD_LO, WOOD, bev=0.06))
    parts.append(pbox(f"Beam{sx}", (0.5, 2 * BY + 0.9, 0.42), (x, 0, SZ - 0.4 - 0.21), WOOD_LO, WOOD, bev=0.06))
    # pewter bolts at the beam/leg joints
    for s in (-1, 1):
        yb = s * (foot_y - (foot_y - top_y) * (SZ - 0.6) / dz)
        parts.append(cylinder(f"Bolt{sx}{s}", 0.11, 0.62, (x + 0.31, yb, SZ - 0.61), METAL, segs=6, rot=(0, -90, 0)))
# diagonal brace from the beam centre up to the top centre on each frame
for sx in (-1, 1):
    parts.append(pbox(f"Brace{sx}", (0.36, 0.36, 2.6), (sx * (LX - 1.25), 0, (SZ + TZ) / 2 - 0.3),
                      WOOD_LO, WOOD, bev=0.05, rot=(0, -sx * 52, 0)))

# --- goo spill on the top, rolling over the front (-Y) edge ---
balls = [Ball((1.6, -0.6, TZ), (1.0, 0.7, 0.16)), Ball((2.2, -0.95, TZ), (0.6, 0.5, 0.15)),
         Ball((1.1, -1.2, TZ), (0.45, 0.4, 0.14)), Ball((1.9, -1.55, TZ + 0.02), (0.38, 0.4, 0.17))]
down, lat, n = Vector((0, 0, -1)), Vector((1, 0, 0)), Vector((0, -1, 0))
fy = -1.32 - 0.3
balls.append(Ball((1.9, fy + 0.05, TZ + 0.02), (0.32, 0.3, 0.15)))  # roll over the edge
for j in range(6):
    z = TZ - 0.08 - j * 0.11
    balls.append(Ball((1.9, fy + 0.02, z), (0.24, 0.27 * (1 - 0.3 * j / 5), 0.12), rot=frame_quat(down, lat, n)))
balls.append(Ball((1.9, fy - 0.02, TZ - 0.72), 0.21))
goo = metaball_mesh("GooSpill", balls, resolution=0.12, tris=380)
parts.append(paint_goo(goo, lambda co, nn: mix(GOO, GOO_HI, min(0.5, 0.35 * max(0.0, nn.z) ** 6))))
for k, (x, y, r) in enumerate(((1.35, -0.45, 0.13), (2.25, -0.85, 0.09))):
    parts.append(blob(f"Bub{k}", r, (x, y, TZ + 0.14), GOO_HI, subdiv=1, squash=(1, 1, 0.6), jitter=0))

finish("ranch_picnic_table", parts)
