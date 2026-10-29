# Base concept (design sketch, not an asset): THE CAROUSEL TENT (Exclusive).
# A 4-tier fairground carousel. Each floor is a round deck behind a glass band between gold poles, capped by a
# scalloped striped valance with bulbs. A striped big-top roof and a pennant crown the top floor. Wooden horses on
# gold poles circle the outside of floor 1 as decor (non-colliding). The door is the ticket-booth arch on -Y.
from models._base_concept_extra import *

R = 29.0
RED_S, CREAM_S, GOLD = rgb(232, 64, 72), rgb(252, 240, 214), rgb(246, 196, 70)
TEAL_S = rgb(70, 190, 200)
DECK = rgb(150, 92, 60)

plot_foot(moat=False, ground=rgb(120, 200, 110))
disc("Plinth", R + 3, 0.9, (0, 0, 0.2), shade(GOLD, 0.8), segs=48)
core(R, DECK, GOLD, rgb(196, 120, 80), [PINK, LILAC, BUTTER, TEAL_S])
bands(R, [CREAM_S], frame=GOLD, frame_n=16, frame_r=0.55)

for i in range(FLOORS):
    f = i + 1
    zt = top(f) + FLOOR_H - 2.5 if f > 1 else 1.0 + FLOOR_H - 2.5
    # Valance: striped frustum skirt flaring out, then a row of bulbs.
    wedge_cone(f"Val{f}", R + 0.2, R + 2.4, zt + 2.5, -3.0, [RED_S, CREAM_S], n=24)
    for k in range(24):
        x, y = polar(R + 2.5, -90 + k * 15)
        add(blob(f"Bulb{f}_{k}", 0.45, (x, y, zt - 0.6), rgb(255, 236, 150), subdiv=1, jitter=0), into="shell")

# Big-top roof, finial and pennant.
zr = top(FLOORS) + FLOOR_H
wedge_cone("Roof", R + 3.0, 0.0, zr, 22.0, [RED_S, CREAM_S], n=16)
disc("RoofRim", R + 3.2, 0.8, (0, 0, zr - 0.4), GOLD, segs=48, into="shell")
disc("Finial", 0.7, 6.0, (0, 0, zr + 22.0), GOLD, segs=8, into="shell")
add(blob("FinialBall", 1.4, (0, 0, zr + 28.0), GOLD, subdiv=2, jitter=0), into="shell")
part("Pennant", (0.3, 6.0, 3.0), (0, 3.2, zr + 26.0), TEAL_S, into="shell")

# Ticket-booth arch over the door.
for sx in (-1, 1):
    x, y = sx * 6.0, -(R + 1.2)
    disc(f"Pillar{sx}", 1.1, 12.0, (x, y, 1.0), GOLD, segs=12, into="shell")
part("ArchTop", (14.0, 2.4, 2.6), (0, -(R + 1.2), 13.6), RED_S, into="shell")
part("ArchSign", (9.0, 0.6, 3.0), (0, -(R + 2.5), 13.8), CREAM_S, into="shell")

# Horses on poles round the outside of floor 1 (decor).
for k, a in enumerate((-40, 0, 45, 90, 135, 180, 220)):
    x, y = polar(R + 5.5, a)
    disc(f"HPole{k}", 0.4, 14.0, (x, y, 1.0), GOLD, segs=6)
    col = [CREAM_S, PINK, rgb(140, 200, 250), BUTTER][k % 4]
    bob = 4.0 + (k % 2) * 2.0
    tx, ty = polar(1.0, a + 90)
    add(blob(f"HBody{k}", 2.8, (x, y, bob + 2.0), col, subdiv=2, squash=(1.5, 0.7, 0.8), jitter=0, rot=(0, 0, a + 90)),
        shade(col, 0.8), col)
    add(blob(f"HHead{k}", 1.5, (x + tx * 3.6, y + ty * 3.6, bob + 4.4), col, subdiv=2, squash=(1, 0.7, 1.2), jitter=0))
mascot(0, -2.0, zr + 30.0, s=2.4)

ship("_base_x_carousel_scene", turn=-25)
