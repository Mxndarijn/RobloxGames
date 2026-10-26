# Base concept (design sketch, not an asset): THE GOO FACTORY.
# A square brick factory, 48 x 48, one storey per floor. You climb a switchback ramp core along the back wall
# (two straight 20-stud runs per floor with a landing at each turn), so the climb is a zig-zag, not a spiral.
# Floor 1: a roll-up shutter door at the front (rolls down when locked), the merge vat and the lock button either
# side of it inside. 8 pads per floor in two rows of 4 on the factory floor. A sawtooth roof, chimneys and a big goo
# tank with the mascot sit on whatever floor is on top. Owner exit: the goo chute, a zig-zag slide down the +X wall.
# Env: FLOORS, CUT (see _base_concept_common).
import math

from lib import blob, box, cylinder, rgb, shade, mix, tube
from models._base_concept_common import *

HALF = 24.0          # half the footprint
WALL = 1.0
BRICK = rgb(214, 104, 80)
BRICK_D = rgb(176, 84, 70)
TRIM = P["ranch_cream"]
STEEL = rgb(150, 160, 176)
RAMP = rgb(110, 196, 236)  # the climb, bright so it reads in the cut-away
HAZ = rgb(250, 206, 70)
DARK = rgb(70, 70, 84)
GLASS = rgb(190, 232, 240)
LANE_A, LANE_B = 15.2, 20.0       # ramp lane centres (y), along the back wall
RUN = (-13.0, 7.0)                # each run's x span
RW = 4.4                          # ramp width

plot_foot(moat=True, door_r=HALF)
# Concrete yard slab under the factory.
part("Yard", (HALF * 2 + 4, HALF * 2 + 4, 0.3), (0, 0, 0.8), rgb(200, 196, 186))

for f in range(1, FLOORS + 1):
    z = top(f)
    # Floor slab (contents: the cut keeps it), with a hole over the ramp core except on floor 1.
    if f == 1:
        part(f"Slab{f}", (HALF * 2, HALF * 2, 0.6), (0, 0, z - 0.3), rgb(186, 182, 172))
    else:
        part(f"Slab{f}a", (HALF * 2, HALF * 2 - 11.5, 0.6), (0, -11.5 / 2, z - 0.3), rgb(186, 182, 172))
        # the slab round the core: left landing strip and right of the turn landing
        part(f"Slab{f}L", (HALF - 13 - 4.5, 11.5, 0.6), (-HALF + (HALF - 17.5) / 2, HALF - 11.5 / 2, z - 0.3),
             rgb(186, 182, 172))
        part(f"Slab{f}R", (HALF - 12.0, 11.5, 0.6), (HALF - (HALF - 12.0) / 2, HALF - 11.5 / 2, z - 0.3),
             rgb(186, 182, 172))
    # Hazard stripe along the slab edge round the core opening.
    part(f"CoreEdge{f}", (21, 0.4, 0.15), (-3, 12.0, z + 0.05), HAZ, k=1.0)

    # Outer walls (shell): brick, a cream band, a strip of windows.
    h = FLOOR_H
    for side, (sx, sy, w, d) in {
        "S": (0, -HALF + WALL / 2, HALF * 2, WALL), "N": (0, HALF - WALL / 2, HALF * 2, WALL),
        "W": (-HALF + WALL / 2, 0, WALL, HALF * 2), "E": (HALF - WALL / 2, 0, WALL, HALF * 2),
    }.items():
        if side == "S" and f == 1:
            # doorway 10 wide, 11 tall in the front wall
            for s in (-1, 1):
                S(box(f"Wall{f}{side}{s}", (HALF - 5, d, h), (s * (5 + (HALF - 5) / 2), sy, z + h / 2), BRICK),
                  BRICK_D, BRICK)
            S(box(f"Wall{f}{side}Top", (10, d, h - 11), (0, sy, z + 11 + (h - 11) / 2), BRICK), BRICK_D, BRICK)
        else:
            S(box(f"Wall{f}{side}", (w, d, h), (sx, sy, z + h / 2), BRICK), BRICK_D, BRICK)
        # window strip (glass, cut with the shell)
        wl = (w if w > d else d) - 8
        ws = (wl, d + 0.3, 3.2) if w > d else (w + 0.3, wl, 3.2)
        if not (side == "S" and f == 1):
            add(box(f"Win{f}{side}", ws, (sx, sy, z + 9.5), GLASS), into="glass")
        # cream band at the top of the storey
        bs = (w + 0.6, d + 0.6, 0.8) if w > d else (w + 0.6, d + 0.6, 0.8)
        S(box(f"Band{f}{side}", bs, (sx, sy, z + h - 0.4), TRIM), shade(TRIM, 0.9), TRIM)

    # Pads: two rows of 4 on the factory floor, front row clear of the spawn at (0, -12.5).
    for row, y in enumerate((-3.0, 7.0)):
        for k in range(4):
            x = -14.1 + k * 9.4
            stand(f"Pad{f}_{row}_{k}", x, y, z, trim=HAZ)
    # A conveyor belt along the west wall carrying slimes (decor).
    part(f"Belt{f}", (3.0, 30, 1.2), (-HALF + 3.2, -4, z + 1.6), DARK)
    for k in range(3):
        slime(-HALF + 3.2, -14 + k * 9, z + 2.2, k + f, r=1.1)

    if f < FLOORS:
        # Switchback ramp core up to floor f + 1: run A (front lane) left->right, landing, run B (back lane) right->left.
        z_mid = z + FLOOR_H / 2
        straight_ramp(f"RampA{f}", (RUN[0], LANE_A, z), (RUN[1], LANE_A, z_mid), RW, RAMP)
        part(f"Landing{f}", (5.5, 9.6, 0.8), (RUN[1] + 2.75, (LANE_A + LANE_B) / 2, z_mid - 0.4), RAMP)
        straight_ramp(f"RampB{f}", (RUN[1], LANE_B, z_mid), (RUN[0] - 4.5, LANE_B, z + FLOOR_H), RW, RAMP)
        # yellow guard rail between the lanes and on the open side
        part(f"Rail{f}", (20, 0.4, 3.0), ((RUN[0] + RUN[1]) / 2, (LANE_A + LANE_B) / 2, z_mid + 1.0), HAZ, k=0.9)
        part(f"RailF{f}", (20, 0.4, 2.6), ((RUN[0] + RUN[1]) / 2, LANE_A - RW / 2 - 0.2, z + 3.4), HAZ, k=0.9)

# Floor 1 front: roll-up shutter (open: rolled into a drum above the doorway), hazard frame, vat and lock inside.
z1 = top(1)
part("ShutterDrum", (11, 2.0, 2.0), (0, -HALF - 0.6, z1 + 12.0), STEEL)
for s in (-1, 1):
    part(f"DoorPost{s}", (0.8, 1.4, 11.5), (s * 5.4, -HALF - 0.2, z1 + 5.75), HAZ, k=0.9)
    for k in range(4):
        part(f"DoorStripe{s}{k}", (0.85, 1.45, 0.9), (s * 5.4, -HALF - 0.2, z1 + 1.5 + k * 2.8), DARK, k=1.0)
vat(-13.5, -17.0, z1)
lock_button(12.5, -18.5, z1)
avatar(0, -12.5, z1)
avatar(3, -HALF - 6, 1.0, rgb(230, 120, 90))

# Roof on the top floor: sawtooth skylights, two chimneys, the goo tank with the mascot.
zt = top(FLOORS) + FLOOR_H
part("RoofSlab", (HALF * 2 + 1, HALF * 2 + 1, 0.8), (0, 0, zt + 0.4), STEEL, into="shell")
for k in range(4):
    y = -HALF + 6 + k * 12
    S(box(f"Saw{k}", (HALF * 2 - 2, 8, 0.6), (0, y, zt + 3.2), STEEL, rot=(35, 0, 0)), shade(STEEL, 0.8), STEEL)
    add(box(f"SawGlass{k}", (HALF * 2 - 4, 0.4, 4.2), (0, y + 3.2, zt + 2.8), GLASS), into="glass")
for k, (x, y) in enumerate(((-16, 14), (-8, 18))):
    S(cylinder(f"Chimney{k}", 2.4, 14 + 3 * k, (x, y, zt), BRICK, segs=12, r_top=2.0), BRICK_D, BRICK)
    S(cylinder(f"ChimneyCap{k}", 2.8, 0.8, (x, y, zt + 14 + 3 * k), DARK, segs=12))
    add(blob(f"Steam{k}", 2.6, (x + 1, y, zt + 17.5 + 3 * k), GOO_HI, subdiv=2, squash=(1.2, 1, 0.8), jitter=0.05))
# goo tank: a round tank on legs, glass band showing the goo
tx, ty = 10, 4
for k in range(4):
    lx, ly = polar(6.5, 45 + k * 90)
    part(f"TankLeg{k}", (0.8, 0.8, 4), (tx + lx, ty + ly, zt + 2.8), STEEL)
disc("TankBot", 8, 2, (tx, ty, zt + 4.8), STEEL, segs=24, into="shell")
disc("TankGoo", 7.6, 5, (tx, ty, zt + 6.8), GOO, segs=24, into="shell")
disc("TankTop", 8, 1.2, (tx, ty, zt + 11.8), STEEL, segs=24, into="shell")
mascot(tx, ty, zt + 13.0, s=4.2)
# A big goo pipe from the tank down the front corner.
tube("GooPipe", [(tx + 7.5, ty - 4, zt + 8), (HALF + 1.5, -10, zt + 4), (HALF + 1.5, -10, 2)], [1.2, 1.2, 1.2], GOO, segs=10)

# Owner exit, the goo chute: a zig-zag half-pipe slide down the +X wall from the top floor to the ground.
zs = top(FLOORS) + 2.0
pts = []
n = max(FLOORS - 1, 0) * 2 + 1
for k in range(n + 1):
    y = -18 if k % 2 == 0 else 18
    pts.append((HALF + 3.0, y, zs - (zs - 2.0) * k / n))
for k in range(len(pts) - 1):
    straight_ramp(f"Chute{k}", pts[k], pts[k + 1], 3.2, GOO, thick=0.6)
    a, b = pts[k], pts[k + 1]
    for s in (-1, 1):
        straight_ramp(f"ChuteLip{k}{s}", (a[0] + s * 1.8, a[1], a[2] + 1.0), (b[0] + s * 1.8, b[1], b[2] + 1.0), 0.5, STEEL,
                      thick=1.2)
disc("SplashPool", 5, 0.6, (HALF + 4, 18 if n % 2 else -18, 0.6), GOO_HI, segs=20)

# Factory character: a GOO CO. sign over the door, two goo silos on the west yard, pipes up the facade.
part("SignBoard", (22, 0.8, 4.0), (0, -HALF - 0.8, top(1) + 14.0), TRIM, into="shell", k=0.92)
for k in range(5):
    add(blob(f"SignDot{k}", 1.1, (-8 + k * 4, -HALF - 1.3, top(1) + 14.0), [GOO, PINK, BUTTER, LILAC, GOO][k],
             subdiv=2, squash=(1, 0.5, 1), jitter=0), into="shell")
for k, y in enumerate((-12, 0)):
    disc(f"Silo{k}", 4.2, 22, (-HALF - 5.5, y, 1.0), STEEL, segs=20)
    disc(f"SiloGoo{k}", 4.3, 9, (-HALF - 5.5, y, 4.0), GOO, segs=20)
    add(blob(f"SiloCap{k}", 4.2, (-HALF - 5.5, y, 23.0), STEEL, subdiv=2, squash=(1, 1, 0.5), jitter=0))
    tube(f"SiloPipe{k}", [(-HALF - 5.5, y, 24.5), (-HALF - 1, y, 26), (-HALF + 0.2, y, 26)], [0.7, 0.7, 0.7], GOO, segs=8)
for x in (-18, 18):
    S(cylinder(f"FacadePipe{x}", 0.8, top(FLOORS) + FLOOR_H - 1, (x, -HALF - 1.0, 1.0), GOO, segs=8))

ship("_base_factory_scene", turn=-25)
