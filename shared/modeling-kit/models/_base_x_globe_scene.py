# Base concept (design sketch, not an asset): THE SNOW GLOBE (Exclusive, seasonal).
# Floor 1 is the wooden pedestal (glass window band all round, gold trim, the door on -Y); floors 2-4 float inside a
# giant glass globe on top, with snow drifting inside and a snowy pine on the top floor. Same centre ramp and pads.
from models._base_concept_extra import *

WOOD_G, GOLD = rgb(150, 90, 60), rgb(246, 196, 70)
SNOW = rgb(250, 252, 255)
PINE = rgb(50, 140, 90)

plot_foot(moat=False, ground=rgb(235, 244, 250))
core([29.0, 24.0, 31.0, 30.0], rgb(220, 230, 240), GOLD, rgb(150, 200, 240), [PINK, LILAC, BUTTER, rgb(120, 190, 250)])

# Pedestal (floor 1): kick wall, glass band, a fat gold-trimmed lintel that the globe sits on.
ring_wall("PedKick", 30.0, 31.0, 1.0, 3.0, WOOD_G, segs=48, gap=DOOR_GAP)
ring_wall("PedGlass", 30.3, 30.6, 4.0, 10.5, GLASS_C, segs=48, gap=DOOR_GAP, into="glass")
ring_wall("PedTop", 28.0, 32.0, 14.5, 2.5, WOOD_G, segs=48)
ring_wall("PedGold", 31.9, 32.3, 15.0, 1.2, GOLD, segs=48)
ring_wall("PedFoot", 31.0, 33.0, 0.5, 1.5, shade(WOOD_G, 0.8), segs=48)
for k in range(12):
    x, y = polar(31.2, -90 + 15 + k * 30)
    disc(f"PedPost{k}", 0.7, 13.5, (x, y, 1.0), GOLD, segs=8, into="shell")
part("DoorFrame", (12.0, 1.6, 1.6), (0, -31.5, 13.6), GOLD, into="shell")

# The globe: a sphere r 34 centred at z 40 (its bottom sits inside the pedestal).
add(blob("Globe", 34.0, (0, 0, 40.0), rgb(215, 240, 255), subdiv=4, jitter=0.0), into="glass")
# Snow flakes drifting inside and a snowy pine on the top floor.
for k in range(60):
    a = R.uniform(0, 360)
    r = R.uniform(10, 29)
    z = R.uniform(20, 70)
    if (r * r + (z - 40) ** 2) > 31 ** 2:
        continue
    x, y = polar(r, a)
    S(blob(f"Flake{k}", 0.45, (x, y, z), SNOW, subdiv=1, jitter=0))
zt = top(4)
for k, (rr, hh) in enumerate(((6.0, 5.0), (4.6, 4.5), (3.0, 4.0))):
    wedge_cone(f"Pine{k}", rr, 0.0, zt + 1.0 + k * 3.2, hh, [PINE], n=10)
    import models._base_concept_common as _c
    for o in _c.shell[-10:]:
        o.location.y += 9.0
# Snowman out front (decor).
for k, (r_, z_) in enumerate(((2.6, 2.6), (2.0, 6.6), (1.4, 9.6))):
    add(blob(f"Snowman{k}", r_, (-14.0, -38.0, z_), SNOW, subdiv=2, jitter=0))
mascot(0, 0, 74.0, s=2.6, col=rgb(150, 210, 255))

ship("_base_x_globe_scene", turn=-25)
