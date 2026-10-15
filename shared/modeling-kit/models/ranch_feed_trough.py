# ranch_feed_trough: chunky wooden feed trough on two skid feet, filled with slime feed
# (Slime Ranch theme). ~6 x 2.5 x 2.2 studs, long axis X, front -Y.
# Goo fill = lib/goo.py metaballs: fused puddle + meniscus up the walls + 2 spills over the
# front lip. Not glowing: plain vertex colour, no emissive.
import math
import bmesh
from lib import *

# Slime Ranch palette (theme table, sRGB 0-255)
WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM = PALETTE["ranch_cream"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
BUTTER = PALETTE["ranch_butter"]

WOOD_LO = mix(WOOD_D, WOOD, 0.4)   # lifted after the first --look roblox check (shadow side went brown)
WOOD_HI = mix(WOOD, CREAM, 0.2)
parts = []


def pbox(name, size, pos, bot, top, bev=0.1, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    bevel(o, bev)
    gradient(o, bot, top)
    return o


L, D = 6.0, 2.35         # overall length (x) and depth (y)
Z0 = 0.55                # underside of the trough body (skids below)
TOP = 2.2

# skid feet: one chunky cross block under each end
for sx in (-1, 1):
    parts.append(pbox(f"Skid{sx}", (0.95, D, Z0 + 0.05), (sx * 2.15, 0, (Z0 + 0.05) / 2), WOOD_LO, WOOD, bev=0.14))

# floor board
parts.append(pbox("Floor", (L - 0.6, D - 0.5, 0.5), (0, 0, Z0 + 0.25), WOOD_LO, WOOD, bev=0.1))

# side walls: two stacked planks per side, flared outward, slightly uneven
FLARE = 10
for sy in (-1, 1):
    for k, (z, h, c) in enumerate(((Z0 + 0.6, 0.72, WOOD), (Z0 + 1.28, 0.72, CREAM))):
        y = sy * (D / 2 - 0.3 + (z - Z0) * math.tan(math.radians(FLARE)) * 0.5)
        tilt = sy * -FLARE
        jit = 0.03 * (k * 2 - 1) * sy
        parts.append(pbox(f"Side{sy}{k}", (L - 0.75 + jit, 0.45, h), (jit, y, z), WOOD_LO if c is WOOD else mix(c, WOOD, 0.3), WOOD_HI if c is WOOD else c, bev=0.1, rot=(tilt, 0, 0)))

# end boards: chunky, a bit taller and wider than the side walls, top corners soft
for sx in (-1, 1):
    x = sx * (L / 2 - 0.3)
    h = TOP + 0.12 - Z0
    parts.append(pbox(f"End{sx}", (0.55, D, h), (x, 0, Z0 + h / 2), WOOD_LO, WOOD_HI, bev=0.18))


# goo fill: one metaball skin (lib/goo.py) = flat lenses filling the tub + a meniscus ridge
# climbing the inner walls + a spill over the front lip that runs down to a fat drop.
# The lens edges sink into the wood, so only the top and the spill are seen.
GZ = TOP - 0.2           # goo level (centre of the lenses)
IX, IY = L / 2 - 0.55, 0.78   # inner wall line (end boards, flared side walls at goo level)
DRIPS = [(-1.3, 1.0), (1.1, 0.6)]   # front spill: x, length down the outside
BUBBLES = [(-1.1, 0.3), (0.85, -0.3), (1.95, 0.15)]


def wall_y(z):
    """outer face of the flared front wall (sy=-1) at height z."""
    return -1.087 - (z - 1.13) * 0.173


def goo_balls():
    bs = []
    for i in range(7):                      # fused puddle: overlapping flat lenses along the tub
        x = -IX + 0.25 + i * (2 * IX - 0.5) / 6
        bs.append(Ball((x, 0.04 * (-1) ** i, GZ - 0.06), (0.62, IY + 0.15, 0.2)))
    for sy in (-1, 1):                      # meniscus ridge along the side walls
        for i in range(9):
            x = -IX + 0.2 + i * (2 * IX - 0.4) / 8
            bs.append(Ball((x, sy * (IY - 0.02), GZ + 0.01), (0.42, 0.2, 0.13)))
    for sx in (-1, 1):                      # ... and the end boards
        for y in (-0.45, 0, 0.45):
            bs.append(Ball((sx * (IX - 0.02), y, GZ + 0.01), (0.2, 0.36, 0.13)))
    for x, ln in DRIPS:                     # spill: wide over the lip, tapering run, fat round tip
        bs.append(Ball((x, -IY - 0.05, GZ + 0.1), (0.45, 0.22, 0.17)))
        bs.append(Ball((x, -1.08, TOP + 0.02), (0.36, 0.2, 0.14)))
        n = 4
        for k in range(n + 1):
            z = TOP - 0.05 - (ln - 0.15) * k / n
            w = 0.3 - 0.16 * k / n            # neck narrows toward the drop
            bs.append(Ball((x + 0.03 * k, wall_y(z) + 0.05, z), (w, 0.11, 0.2)))
        z = TOP - 0.05 - ln
        bs.append(Ball((x + 0.12, wall_y(z) - 0.0, z), (0.2, 0.16, 0.21)))
    for x, y in BUBBLES:                    # half-sunk bubbles fuse into soft bumps
        bs.append(Ball((x, y, GZ + 0.2), 0.13))
    return bs


def goo_col(co, n):
    if n.z < 0.3 and co.y > -1.0:           # hidden sides/underside in the tub
        return shade(GOO, 0.85)
    if co.y < -1.0:                         # spill: darker run, light tip
        tip = max(0.0, min(1.0, (TOP - 0.1 - co.z) / 1.0))
        return mix(mix(GOO, GOO_HI, 0.12), GOO_HI, 0.5 * tip ** 3)   # lifted: the run sits in shade
    rim = max(abs(co.x) / IX, abs(co.y) / IY)
    hi = 0.5 * max(0.0, (rim - 0.86) / 0.14) ** 2            # thin glossy meniscus only
    hi = max(hi, 0.6 * max(0.0, (co.z - GZ - 0.12) / 0.15))   # bubble tops
    return mix(GOO, GOO_HI, min(0.6, hi))


goo = metaball_mesh("Goo", goo_balls(), resolution=0.13, tris=700)
print("goo nm", goo["nm"], "zmax %.2f" % max(v.co.z for v in goo.data.vertices), "zmin %.2f" % min(v.co.z for v in goo.data.vertices))
parts.append(paint_goo(goo, goo_col))

# a few butter feed pellets bobbing in the goo
for k, (x, y) in enumerate(((-1.6, -0.2), (-0.7, 0.3), (0.3, -0.1), (1.6, 0.25))):
    parts.append(blob(f"Pellet{k}", 0.26, (x, y, GZ + 0.12), BUTTER, seed=k + 3, subdiv=2, squash=(1.1, 1, 0.7), jitter=0.08))
    gradient(parts[-1], BUTTER, mix(BUTTER, CREAM, 0.4))

for o in parts:
    if "keep_smooth" not in o.data.attributes:
        o.data.attributes.new("keep_smooth", "INT", "FACE")
o = finish("ranch_feed_trough", parts)
a = o.data.attributes["keep_smooth"]
for p, d in zip(o.data.polygons, a.data):
    p.use_smooth = bool(d.value)
o.data.attributes.remove(a)
