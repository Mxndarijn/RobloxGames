# Base concept (design sketch, not an asset): THE CANDY CASTLE (Exclusive).
# A square wafer keep with sugar-glass windows on every floor, frosting drips on each lintel, four swirl-roofed
# turrets at the corners and a frosted peak roof. Gingerbread gate on -Y, lollipops either side.
from models._base_x_square import *

H = 26.0
WAFER, WAFER_D = rgb(236, 190, 130), rgb(200, 150, 96)
FROST, PINK_C, MINT = rgb(255, 250, 250), rgb(255, 140, 190), rgb(140, 230, 200)
GINGER = rgb(170, 100, 50)

plot_foot(moat=True, moat_col=rgb(255, 170, 210), ground=rgb(150, 220, 140), door_r=H)
core(H, rgb(255, 220, 230), FROST, PINK_C, [PINK, LILAC, BUTTER, MINT], square=True)
square_walls(H, [WAFER, WAFER_D], rgb(255, 190, 220))

for f in range(1, FLOORS + 1):
    z = (top(f) if f > 1 else 1.0) + FLOOR_H - 2.5
    for k in range(28):
        side, t = divmod(k, 7)
        u = -H + (t + 0.5) * 2 * H / 7
        x, y = [(u, -H - 0.8), (H + 0.8, u), (u, H + 0.8), (-H - 0.8, u)][side]
        S(blob(f"Drip{f}_{k}", 1.1, (x, y, z), FROST, subdiv=1, squash=(1, 1, 1.5), jitter=0))

zt = top(FLOORS) + FLOOR_H
part("RoofSlab", (2 * H + 3, 2 * H + 3, 1.0), (0, 0, zt + 0.5), FROST, into="shell")
wedge_cone("Roof", (H + 1.5) * 1.414, 0.0, zt + 1.0, 18.0, [PINK_C, FROST], n=4, a0=-45)
add(blob("Cherry", 2.4, (0, 0, zt + 20.0), rgb(230, 40, 60), subdiv=2, jitter=0), into="shell")
for cx, cy in ((H, H), (-H, H), (H, -H), (-H, -H)):
    disc(f"Turret{cx}{cy}", 5.0, zt + 4.0, (cx, cy, 0.5), FROST, segs=20, into="shell")
    for k in range(4):
        disc(f"TBand{cx}{cy}{k}", 5.3, 2.0, (cx, cy, 8.0 + k * FLOOR_H), PINK_C if k % 2 == 0 else MINT, segs=20, into="shell")
    wedge_cone(f"TRoof{cx}{cy}", 6.5, 0.0, zt + 4.5, 12.0, [PINK_C, MINT], n=12, a0=0)
    import models._base_concept_common as _c
    for o in list(_c.shell[-12:]):
        o.location.x += cx
        o.location.y += cy

# Gingerbread gate and lollipops.
for sx in (-1, 1):
    part(f"Gate{sx}", (2.4, 2.4, 13.0), (sx * 6.2, -H - 1.0, 7.0), GINGER, into="shell")
    x = sx * 13.0
    disc(f"Stick{sx}", 0.4, 10.0, (x, -H - 7.0, 0.5), FROST, segs=6)
    add(cylinder(f"Pop{sx}", 3.0, 0.8, (x, -H - 7.0, 12.0), PINK_C if sx < 0 else MINT, segs=20, rot=(90, 0, 0)))
part("GateTop", (15.0, 2.4, 2.4), (0, -H - 1.0, 14.0), GINGER, into="shell")
for k in range(7):
    S(blob(f"GateIcing{k}", 0.8, (-6 + 2 * k, -H - 2.4, 15.3), FROST, subdiv=1, jitter=0))

ship("_base_x_candy_scene", turn=-25)
