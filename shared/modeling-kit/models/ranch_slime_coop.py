# ranch_slime_coop: chicken-coop style slime hutch on stilts, red gable roof, ramp, round door, goo nest (Slime Ranch).
# NOTE: lib shapes rot= is in DEGREES. Ridge along X, door/ramp on -Y.
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
BUTTER, CREAM = PALETTE["ranch_butter"], PALETTE["ranch_cream"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
parts = []


def pbox(n, s, p, bot, top, bev=0.1, rot=(0, 0, 0)):
    o = box(n, s, p, bot, rot=rot); bevel(o, bev); gradient(o, bot, top); return o


W, D, Z0, H = 6.0, 4.4, 1.4, 3.6
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(pbox(f"Leg{sx}{sy}", (0.8, 0.8, Z0 + 0.2), (sx * (W / 2 - 0.5), sy * (D / 2 - 0.5), (Z0 + 0.2) / 2), WOOD_LO, WOOD_D, 0.12))
parts.append(pbox("Floor", (W + 0.3, D + 0.3, 0.45), (0, 0, Z0 + 0.22), WOOD_LO, WOOD, 0.12))
# walls: planks stacked, slight jitter
for k in range(4):
    z = Z0 + 0.45 + 0.45 + k * 0.82
    j = 0.04 * ((k % 2) * 2 - 1)
    for sy in (-1, 1):
        parts.append(pbox(f"WallY{sy}{k}", (W + j, 0.42, 0.78), (j, sy * (D / 2 - 0.2), z), WOOD_LO, WOOD, 0.08))
    for sx in (-1, 1):
        parts.append(pbox(f"WallX{sx}{k}", (0.42, D - 0.4, 0.78), (sx * (W / 2 - 0.2), 0, z), WOOD_LO, WOOD, 0.08))
# corner posts
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(pbox(f"Cor{sx}{sy}", (0.6, 0.6, H + 0.3), (sx * (W / 2 - 0.15), sy * (D / 2 - 0.15), Z0 + 0.45 + (H + 0.3) / 2), WOOD_D, WOOD, 0.1))
# gable ends (triangle-ish via stacked shrinking boards)
TOPZ = Z0 + 0.45 + H
for sx in (-1, 1):
    for k in range(3):
        parts.append(pbox(f"Gab{sx}{k}", (0.4, D - 0.6 - k * 1.3, 0.62), (sx * (W / 2 - 0.2), 0, TOPZ + 0.35 + k * 0.6), WOOD_LO, WOOD, 0.08))
# roof
for s in (-1, 1):
    parts.append(pbox(f"Roof{s}", (W + 1.2, 3.3, 0.3), (0, s * 1.35, TOPZ + 1.0), ROOF_D, ROOF, 0.1, rot=(-s * 34, 0, 0)))
parts.append(pbox("Ridge", (W + 1.4, 0.45, 0.45), (0, 0, TOPZ + 1.95), ROOF_D, ROOF_D, 0.1))
# round door hole frame + dark-ish opening on -Y, with goo drip on sill
parts.append(cylinder("DoorFrame", 1.05, 0.25, (0, -D / 2 - 0.05, Z0 + 1.6), CREAM, segs=12, rot=(90, 0, 0)))
parts.append(cylinder("Door", 0.85, 0.3, (0, -D / 2 - 0.08, Z0 + 1.6), WOOD_D, segs=12, rot=(90, 0, 0)))
parts.append(blob("SillGoo", 0.45, (0, -D / 2 - 0.25, Z0 + 0.72), GOO, subdiv=1, squash=(1.6, 0.8, 0.5), jitter=0.04))
gradient(parts[-1], GOO, GOO_HI)
# ramp with cleats
import math
RA = 33
parts.append(pbox("Ramp", (1.6, 3.4, 0.25), (0, -D / 2 - 1.4, (Z0 + 0.45) / 2), WOOD_LO, WOOD, 0.08, rot=(RA, 0, 0)))
for k in range(3):
    t = (k + 0.7) / 3.6
    parts.append(pbox(f"Cleat{k}", (1.5, 0.25, 0.18), (0, -D / 2 - 0.05 - t * 2.8, (Z0 + 0.45) * (1 - t) + 0.2), WOOD_D, WOOD_D, 0.04, rot=(RA, 0, 0)))
# side window with butter shutter + goo nest box hint on +X
parts.append(pbox("Win", (0.2, 1.2, 1.0), (W / 2 + 0.05, 0, Z0 + 2.4), WOOD_D, WOOD_D, 0.05))
parts.append(pbox("Shutter", (0.15, 0.6, 1.1), (W / 2 + 0.15, 0.95, Z0 + 2.4), BUTTER, mix(BUTTER, CREAM, 0.3), 0.05))
# goo drip down the roof edge (surface blob, not tube)
parts.append(blob("RoofGoo", 0.5, (1.4, -2.55, TOPZ + 0.2), GOO, subdiv=1, squash=(1.4, 0.6, 0.5), jitter=0.04))
gradient(parts[-1], GOO, GOO_HI)
finish("ranch_slime_coop", parts)
