# ranch_barrel_stack: Slime Ranch plaza prop. Two ranch_barrels side by side on the ground, a third
# standing on their lids leaning ~7 deg toward the front (-Y), its open top brimming with goo that
# spills over the front rim in metaball drips, plus a goo puddle on the ground in front (-Y).
# Barrel recipe = models/ranch_barrel.py (bulged staves, pewter hoops tracking the bulge, cream bung).
import math
import bmesh
from mathutils import Matrix, Vector
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_metal"], PALETTE["ranch_plaza"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]

WOOD_LO = mix(WOOD_D, WOOD, 0.55)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO = mix(METAL, WOOD_D, 0.2)
CREAM_LO = mix(CREAM, WOOD, 0.2)

R, H, SEGS, BULGE = 1.05, 2.55, 12, 0.16
RIM_IN, DIP = 0.16, 0.22          # open top: wood rim width, goo floor depth
GX = 1.34                         # bottom barrels at x = +-GX
TILT = 7.0                        # top barrel lean toward -Y (deg)
parts = []


def radius_at(t):
    return R * (1.0 + BULGE * math.sin(math.pi * max(0.0, min(1.0, t))))


def barrel(prefix, open_top=False, bung=True):
    out = []
    body = cylinder(prefix + "Body", R, H, (0, 0, 0), WOOD, segs=SEGS)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for v in bm.verts:
        b = 1.0 + BULGE * math.sin(math.pi * max(0.0, min(1.0, v.co.z / H)))
        v.co.x *= b
        v.co.y *= b
    inner = set()
    if open_top:  # inset the top cap into a wood rim + sunken goo floor
        top = [f for f in bm.faces if f.normal.z > 0.9][0]
        r = bmesh.ops.inset_region(bm, faces=[top], thickness=RIM_IN, depth=0)
        bmesh.ops.translate(bm, vec=(0, 0, -DIP), verts=top.verts)
        inner = {top}
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        c = f.calc_center_median()
        stave = int(((math.atan2(c.y, c.x) + math.pi) / (2 * math.pi)) * SEGS) % 2
        col = mix(WOOD_LO, WOOD_HI, max(0.0, min(1.0, c.z / H)))
        if stave:
            col = shade(col, 0.93)
        if f in inner:
            col = GOO
        elif f.normal.z > 0.85:
            col = mix(PLAZA, WOOD, 0.2)
        elif f.normal.z < -0.85:
            col = WOOD_LO
        for lp in f.loops:
            lp[layer] = (*col[:3], 1.0)
    bm.to_mesh(body.data)
    bm.free()
    out.append(body)
    if not open_top:
        out.append(cylinder(prefix + "Lid", R * 0.9, 0.14, (0, 0, H - 0.06), PLAZA, segs=SEGS))
        gradient(out[-1], mix(PLAZA, WOOD, 0.15), PLAZA)
    out.append(cylinder(prefix + "Bot", R * 0.9, 0.12, (0, 0, 0.02), WOOD_LO, segs=SEGS))
    gradient(out[-1], WOOD_D, WOOD_LO)
    for i, t in enumerate((0.18, 0.5, 0.82)):
        hoop = cylinder(f"{prefix}Hoop{i}", radius_at(t) + 0.05, 0.18, (0, 0, t * H - 0.1), METAL, segs=SEGS)
        gradient(hoop, METAL_LO, METAL)
        out.append(hoop)
    if bung:
        b = cylinder(prefix + "Bung", 0.18, 0.2, (0, -(radius_at(0.55) + 0.06), H * 0.55 - 0.1), CREAM, segs=8, rot=(90, 0, 0))
        gradient(b, CREAM_LO, CREAM)
        out.append(b)
    return out


def place(objs, M):
    for o in objs:
        o.data.transform(M)
    return objs


# bottom pair: slight yaw so the bungs don't line up like CAD
parts += place(barrel("BL"), Matrix.Translation((-GX, 0.0, 0)) @ Matrix.Rotation(math.radians(-12), 4, "Z"))
parts += place(barrel("BR"), Matrix.Translation((GX, 0.05, 0)) @ Matrix.Rotation(math.radians(9), 4, "Z"))

# top barrel: stands on both lids (lid top z = H + 0.08), leans toward -Y
TOPM = Matrix.Translation((0.08, 0.1, H + 0.06)) @ Matrix.Rotation(math.radians(TILT), 4, "X")
parts += place(barrel("TP", open_top=True, bung=False), TOPM)
ROT3 = TOPM.to_3x3()


def surf(a, t, off, M=TOPM):
    """barrel surface point (world) at angle a (0 = -Y front), height fraction t, offset off along n."""
    n = Vector((math.sin(a), -math.cos(a), 0))
    p = n * (radius_at(t) + off) + Vector((0, 0, t * H))
    return M @ p, (M.to_3x3() @ n).normalized()


def drip(balls, a_deg, t0, ln, w, M=TOPM, rim=True):
    """flat lens chain down the barrel side from height t0 for ln (fraction of H), round tip."""
    a = math.radians(a_deg)
    down = (M.to_3x3() @ Vector((0, 0, -1))).normalized()
    if rim:
        lip, n = surf(a, t0, 0.0, M)
        balls.append(Ball(lip + Vector((0, 0, 0.04)), (0.36, 0.36, 0.17)))   # roll over the rim
    steps = max(3, int(ln * H / 0.18))
    for j in range(steps + 1):
        t = t0 - ln * j / steps
        p, n = surf(a, t, 0.0, M)
        lat = n.cross(down).normalized()
        balls.append(Ball(p, (0.3, w * (1.0 - 0.3 * j / steps), 0.13), rot=frame_quat(down, lat, n)))
    p, n = surf(a, t0 - ln, 0.04, M)
    balls.append(Ball(p, w * 0.85))                                        # fat round tip


balls = []
# goo surface brimming in the open top, bulging over the front rim
zt = H - DIP
balls.append(Ball(TOPM @ Vector((0, 0, zt + 0.12)), (R * 0.85, R * 0.85, 0.28)))
balls.append(Ball(TOPM @ Vector((0, -0.55, zt + 0.2)), (0.7, 0.55, 0.3)))
# drips down the front of the top barrel: (angle deg, length as fraction of H, width)
for a_deg, ln, w in [(-34, 0.36, 0.26), (-4, 0.7, 0.32), (36, 0.5, 0.26)]:
    drip(balls, a_deg, 1.0, ln, w)
top_goo = metaball_mesh("GooTop", balls, resolution=0.16, tris=560)


def goo_col(co, n):
    k = max(0.0, n.z) ** 6 * 0.3 + (0.45 if co.z < H + 0.2 and n.z < 0.3 else 0.0) * max(0.0, -n.z + 0.4)
    return mix(GOO, GOO_HI, min(0.55, k))


parts.append(paint_goo(top_goo, goo_col))

# puddle on the ground in front, fed by a drip off the left barrel's lid edge
# drip off the left barrel's lid running down its front into the puddle
BLM = Matrix.Translation((-GX, 0.0, 0)) @ Matrix.Rotation(math.radians(-12), 4, "Z")
pb = []
drip(pb, 18, 1.0, 1.0, 0.28, M=BLM)
pb += [Ball((-0.6, -2.0, 0.0), (1.9, 1.1, 0.24)), Ball((0.9, -2.3, 0.0), (1.0, 0.8, 0.2)),
      Ball((-1.2, -1.45, 0.0), (0.9, 0.7, 0.22)), Ball((0.3, -3.0, 0.0), (0.45, 0.4, 0.14))]
puddle = metaball_mesh("GooPuddle", pb, resolution=0.16, tris=320, clamp_z=0.02)
parts.append(paint_goo(puddle, lambda co, n: mix(GOO, GOO_HI, 0.12 * max(0.0, n.z) ** 4)))

finish("ranch_barrel_stack", parts)
