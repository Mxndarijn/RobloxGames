# ranch_upgrade_cabinet: Upgrade Shop C, "upgrade cabinet". A farm booth with a rounded blue barrel roof whose back
# wall is a big wood-framed display cabinet: six cubbies (two rows of three), one upgrade in each with its level pips,
# plus a chalkboard price board on the side. Counter 10.4 wide, top at z 4.1. Sign hangs under the roof front:
# 7.6 x 1.6. In the exported mesh frame (bbox 16.41 x 9.93 x 15.29, origin bottom centre): face centre x 0, z 12.5;
# its outer face is 0.03 behind the bbox front.
import math
from lib import *
from models._phoenix_ranch import *
from models._shop_parts import *

W = 10.4
X = W / 2
CY, CD, CH = -2.2, 3.0, 3.6
BX, BY0, BY1, BZ = 5.8, -3.9, 3.2, 11.2  # booth half width, front / back y, wall height
parts = []

parts += blue_counter("C", W, CY, CD, CH)

# side walls (boards) + corner posts
for k in range(7):
    z = k * BZ / 7
    h = BZ / 7 - 0.1
    c = WOOD if k % 2 else shade(WOOD, 0.93)
    for sx in (-1, 1):
        parts.append(bbox(f"Side{sx}{k}", (0.5, BY1 - (CY + 1.6), h), (sx * BX, (BY1 + CY + 1.6) / 2, z + h / 2), shade(c, 0.86), c, bev=0.06))
for sx in (-1, 1):
    for y in (BY0, BY1):
        parts.append(bbox(f"Post{sx}{y}", (1.0, 1.0, BZ), (sx * BX, y, BZ / 2), shade(WOOD_D, 0.9), WOOD_D, bev=0.12))
    parts.append(bbox(f"Beam{sx}", (0.8, BY1 - BY0, 0.8), (sx * BX, (BY0 + BY1) / 2, BZ - 0.4), shade(WOOD_D, 0.9), WOOD_D, bev=0.1))
parts.append(bbox("FrontBeam", (2 * BX + 0.8, 0.8, 0.8), (0, BY0, BZ - 0.4), shade(WOOD_D, 0.9), WOOD_D, bev=0.1))

# the cabinet: back board, wood frame, 2 x 3 cubbies with blue insides, one upgrade per cubby
CW, CZ0, CZ1 = 2 * BX - 0.8, 4.3, 10.0
parts.append(bbox("CabBack", (CW, 0.5, CZ1 - CZ0 + 0.6), (0, BY1, (CZ0 + CZ1) / 2), shade(WOOD, 0.85), WOOD, bev=0))
parts.append(bbox("CabBase", (CW, 2.4, CZ0), (0, BY1 - 1.0, CZ0 / 2), shade(WOOD, 0.85), WOOD, bev=0.06))
cell_w = CW / 3
cell_h = (CZ1 - CZ0) / 2
for r in range(2):
    for c in range(3):
        xc = -CW / 2 + cell_w * (c + 0.5)
        z0 = CZ0 + cell_h * r            # the first three upgrades sit on the lower row, nearest the counter
        idx = r * 3 + c
        parts.append(bbox(f"Cub{idx}", (cell_w - 0.5, 0.3, cell_h - 0.4), (xc, BY1 - 0.3, z0 + cell_h / 2), BLUE_HI, mix(BLUE_HI, CREAM, 0.45), bev=0))
        parts.append(bbox(f"CubFloor{idx}", (cell_w - 0.5, 1.8, 0.25), (xc, BY1 - 1.2, z0 + 0.15), WOOD_LO, WOOD, bev=0))
        parts += UPGRADE_PROPS[idx](f"Up{idx}", xc, BY1 - 1.2, z0 + 0.3, s=0.95 if idx == 4 else 1.15)
        parts += level_pips(f"Lv{idx}", xc - 0.45, BY1 - 2.15, z0 + 0.12, n=3, lit=(3, 2, 2, 1, 1, 0)[idx])
        parts.append(bbox(f"Tag{idx}", (0.8, 0.1, 0.5), (xc + 0.75, BY1 - 2.17, z0 + 0.12), BUTTER_LO, BUTTER, bev=0, rot=(0, 6, 0)))
# frame bars
for c in range(4):
    x = -CW / 2 + cell_w * c
    parts.append(bbox(f"FrameV{c}", (0.4, 2.2, CZ1 - CZ0 + 0.4), (x, BY1 - 1.0, (CZ0 + CZ1) / 2), WOOD_LO, WOOD, bev=0.05))
for r in range(3):
    z = CZ0 + cell_h * r
    parts.append(bbox(f"FrameH{r}", (CW + 0.4, 2.2, 0.35), (0, BY1 - 1.0, z), WOOD_LO, WOOD, bev=0.05))

# chalkboard price board on the left side wall, facing out
parts.append(bbox("Chalk", (0.3, 3.0, 3.6), (-BX - 0.4, 0.4, 5.6), shade(WOOD_D, 0.8), WOOD_D, bev=0.06))
parts.append(bbox("ChalkFace", (0.3, 2.6, 3.2), (-BX - 0.5, 0.4, 5.6), BLUE_D, BLUE, bev=0))
for k in range(5):
    parts.append(box(f"ChalkLine{k}", (0.32, 1.6 - 0.2 * (k % 2), 0.12), (-BX - 0.52, 0.2, 6.8 - k * 0.55), CREAM))
    parts.append(blob(f"ChalkCoin{k}", 0.14, (-BX - 0.55, 1.3, 6.8 - k * 0.55), GOLD, subdiv=1, squash=(0.5, 1, 1), jitter=0))

# barrel roof: curved blue planks over an arc, dark wood ribs at the front and back, blue scallop trim
RR = BX + 1.0
NARC = 9
RY0, RY1 = BY0 - 1.2, BY1 + 0.8
for k in range(NARC):
    a0 = math.radians(180 * k / NARC)
    a1 = math.radians(180 * (k + 1) / NARC)
    am = (a0 + a1) / 2
    x, z = math.cos(am) * RR, BZ + math.sin(am) * RR * 0.55
    seg = math.hypot(math.cos(a1) * RR - math.cos(a0) * RR, (math.sin(a1) - math.sin(a0)) * RR * 0.55) + 0.1
    ang = math.degrees(math.atan2((math.sin(a1) - math.sin(a0)) * 0.55, math.cos(a1) - math.cos(a0)))
    c = BLUE if k % 2 else mix(BLUE, BLUE_HI, 0.35)
    parts.append(bbox(f"Arc{k}", (seg, RY1 - RY0, 0.5), (x, (RY0 + RY1) / 2, z), shade(c, 0.85), c, bev=0, rot=(0, -ang, 0)))
    for j, y in enumerate((RY0 - 0.1, RY1 + 0.1)):
        parts.append(bbox(f"Rib{k}{j}", (seg, 0.4, 0.7), (x * 1.01, y, z), shade(WOOD_D, 0.9), WOOD_D, bev=0, rot=(0, -ang, 0)))
parts.append(bbox("RoofBase", (2 * RR, RY1 - RY0, 0.4), (0, (RY0 + RY1) / 2, BZ), BLUE_D, BLUE_D, bev=0))
parts.append(prism("ArcFront", [(math.cos(math.radians(180 * i / 18)) * (RR - 0.2), BZ + math.sin(math.radians(180 * i / 18)) * (RR - 0.2) * 0.55) for i in range(19)],
                   RY0 + 0.2, RY0 + 0.6, BLUE, mix(BLUE_HI, CREAM, 0.25)))
parts += scallops("ScF", -RR, RR, RY0 - 0.4, BZ - 0.1, 11, cols=(BLUE_HI, BLUE))
# sign under the arch front + a gold star badge above it
parts += blue_sign("Sign", RY0 + 0.1, BZ + 1.3, w=7.6, h=1.6)   # set back in the arch: room for the game's SHOP text
parts.append(prism("Star", [(math.cos(math.radians(90 + i * 36)) * (0.75 if i % 2 == 0 else 0.32), BZ + 3.2 + math.sin(math.radians(90 + i * 36)) * (0.75 if i % 2 == 0 else 0.32)) for i in range(10)],
                   RY0 - 0.2, RY0 + 0.2, GOLD_D, GOLD))

# counter goods: only a gold bell at the right end, so nothing hides the cabinet
T = CH + 0.5
parts.append(gcyl("Bell", 0.6, 0.7, (4.3, CY - 0.5, T), GOLD_D, GOLD, segs=10, r_top=0.25))
parts.append(blob("BellKnob", 0.2, (4.3, CY - 0.5, T + 0.8), GOLD, subdiv=1, jitter=0))

# dark wood battens on the back wall (the side players see from the outer ring)
for k, z in enumerate((2.0, 6.0, 9.6)):
    parts.append(bbox(f"BackBat{k}", (CW, 0.3, 0.6), (0, BY1 + 0.4, z), shade(WOOD_D, 0.9), WOOD_D, bev=0.06))

# flower barrels at the corners
for sx in (-1, 1):
    bx = sx * (BX + 1.5)
    parts.append(gcyl(f"FBar{sx}", 0.9, 1.4, (bx, BY0 + 0.2, 0), BLUE_D, BLUE, segs=10))
    parts.append(cylinder(f"FHoop{sx}", 0.95, 0.2, (bx, BY0 + 0.2, 1.0), METAL, segs=10))
    for j, (dx, dy, col) in enumerate(((-0.35, 0, PINK), (0.35, 0.1, GOLD), (0, -0.35, BLUE_HI), (0, 0.4, PINK))):
        parts.append(blob(f"FB{sx}{j}", 0.35, (bx + dx, BY0 + 0.2 + dy, 1.7), col, subdiv=1, jitter=0))
    parts.append(blob(f"FLeaf{sx}", 0.75, (bx, BY0 + 0.2, 1.4), PALETTE["ranch_field_dark"], subdiv=1, squash=(1, 1, 0.5), jitter=0))

finish("ranch_upgrade_cabinet", parts)
