# Base concept (design sketch, not an asset): THE HAUNTED MANOR (Exclusive, seasonal).
# A dark-purple timber manor with tall green-lit windows on every floor, a steep slate roof with a crooked corner
# tower and chimney, bats circling, pumpkins and a crooked fence round the plot. Creaky front door on -Y.
from models._base_x_square import *

H = 26.0
WOOD_P, WOOD_PD = rgb(96, 70, 120), rgb(70, 50, 90)
SLATE, GLOW = rgb(70, 72, 96), rgb(140, 250, 150)
PUMP = rgb(250, 140, 40)

plot_foot(moat=False, ground=rgb(90, 120, 80))
core(H, rgb(120, 96, 80), WOOD_PD, rgb(140, 110, 90), [PUMP, LILAC, GLOW, PINK], square=True)
square_walls(H, [WOOD_P, WOOD_PD], mix(GLOW, rgb(220, 255, 220), 0.4))

zt = top(FLOORS) + FLOOR_H
part("Eave", (2 * H + 4, 2 * H + 4, 1.0), (0, 0, zt + 0.5), SLATE, into="shell")
wedge_cone("Roof", (H + 2) * 1.414, 0.0, zt + 1.0, 24.0, [SLATE, shade(SLATE, 0.85)], n=4, a0=-45)
# Crooked corner tower (leans a little) and chimney.
import models._base_concept_common as _c
n0 = len(_c.shell)
disc("Tower", 6.0, 18.0, (0, 0, 0), WOOD_P, segs=12, into="shell")
add(cylinder("TowerWin", 3.0, 5.0, (0, -5.6, 8.0), GLOW, segs=10, rot=(90, 0, 0)), into="shell")
wedge_cone("TowerRoof", 7.5, 0.0, 18.0, 14.0, [SLATE], n=10)
for o in _c.shell[n0:]:
    o.location.x += H - 2
    o.location.y += H - 2
    o.location.z += zt - 4
    o.rotation_euler.y = math.radians(8)
part("Chimney", (4.0, 4.0, 14.0), (-12.0, 8.0, zt + 12.0), rgb(110, 70, 70), into="shell")

# Bats round the roof.
for k in range(7):
    a = k * 51
    x, y = polar(R.uniform(30, 40), a)
    z = zt + R.uniform(4, 22)
    S(blob(f"Bat{k}", 1.0, (x, y, z), rgb(30, 26, 40), subdiv=1, jitter=0))
    for sx in (-1, 1):
        part(f"Wing{k}{sx}", (2.4, 0.2, 1.0), (x + sx * 1.6, y, z + 0.3), rgb(30, 26, 40), rot=(0, sx * 20, a), into="shell")
# Pumpkins, gravestones and the fence.
for k in range(8):
    a = -150 + k * 40
    x, y = polar(33.0, a)
    if k % 2:
        S(blob(f"Pumpkin{k}", 2.2, (x, y, 2.2), PUMP, subdiv=2, squash=(1.2, 1.2, 0.8), jitter=0.05), shade(PUMP, 0.75), PUMP)
    else:
        part(f"Grave{k}", (3.0, 1.0, 4.0), (x, y, 2.5), rgb(150, 150, 160), rot=(0, 0, a + 90 + R.uniform(-15, 15)))
for k in range(40):
    a = k * 9
    if -104 < (a + 180) % 360 - 180 < -76:
        continue
    x, y = polar(38.0, a)
    part(f"Fence{k}", (0.6, 0.6, 4.0 + R.uniform(-0.6, 0.6)), (x, y, 2.4), rgb(40, 36, 46), rot=(R.uniform(-8, 8), 0, a))
# Creaky door frame.
part("DoorTop", (12.0, 1.8, 2.0), (0, -H - 1.0, 13.0), rgb(60, 40, 50), into="shell")

ship("_base_x_haunted_scene", turn=-25)
