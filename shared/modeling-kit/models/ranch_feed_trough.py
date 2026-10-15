# ranch_feed_trough: chunky wooden feed trough on two skid feet, filled with slime feed
# (Slime Ranch theme). ~6 x 2.5 x 2.2 studs, long axis X, front -Y.
# Goo fill = one closed grid slab with an indented (dipped) surface and a lighter rim
# where it climbs the walls (meniscus). Not glowing: plain vertex colour, no emissive.
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


# goo fill: closed grid slab, surface indented, lighter rim against the walls
def goo_fill(name, hx, hy, zb, zt, nx=16, ny=6, dip=0.22):
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=nx, y_segments=ny, size=1.0)
    bmesh.ops.scale(bm, vec=(hx, hy, 1), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0, 0, zb), verts=bm.verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    top = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    for v in top:
        u, w = v.co.x / hx, v.co.y / hy
        edge = max(abs(u) ** 6, abs(w) ** 2)           # 0 centre .. 1 at the walls
        dimple = 0.06 * math.sin(u * 7.0 + 0.6) * math.cos(w * 2.4)
        v.co.z = zt - dip * (1 - edge) + dimple * (1 - edge)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            v = lp.vert.co
            t = max(abs(v.x / hx) ** 8, abs(v.y / hy) ** 4)   # only the outer rim goes light
            lp[layer] = mix(GOO, GOO_HI, min(1.0, t * 1.3)) if v.z > zb + 0.01 else shade(GOO, 0.8)
    return obj_from_bm(name, bm)


parts.append(goo_fill("Goo", L / 2 - 0.5, D / 2 - 0.2, Z0 + 0.4, TOP - 0.08, dip=0.18))

# a few butter feed pellets resting in the goo
for k, (x, y) in enumerate(((-1.4, -0.25), (-0.9, 0.3), (0.2, -0.1), (1.1, 0.35), (1.6, -0.3))):
    parts.append(blob(f"Pellet{k}", 0.24, (x, y, TOP - 0.24), BUTTER, seed=k + 3, subdiv=1, squash=(1.1, 1, 0.75), jitter=0.06))
    gradient(parts[-1], BUTTER, mix(BUTTER, CREAM, 0.4))

finish("ranch_feed_trough", parts)
