# ranch_log_pile: stacked firewood pile beside a chopping stump (Slime Ranch plaza/farm prop).
# 4/3/2 pyramid of chunky logs running along Y, so the ring ends (bark rim, light heartwood, darker
# core) face the front (-Y); two stakes per side pin the bottom row. Green goo "sap" oozes out of
# the top log's front end, runs down over the ends below (metaball lens chain, lib/goo.py) and pools
# in front. Chopping stump on +X with a pewter-headed axe bitten into its top.
# Medium prop, target 500-2000 tris. cylinder() pos = base; lib rot= is in DEGREES.
import math, random
import bmesh
from mathutils import Matrix, Vector
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL = PALETTE["ranch_cream"], PALETTE["ranch_metal"]
PATH, BUTTER = PALETTE["ranch_path"], PALETTE["ranch_butter"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
FIELD_D, FIELD_L = PALETTE["ranch_field_dark"], PALETTE["ranch_field_light"]
BARK_LO, BARK_HI = mix(WOOD_D, WOOD, 0.35), mix(WOOD_D, WOOD, 0.85)
HEART, CORE = mix(PATH, CREAM, 0.15), mix(PATH, WOOD, 0.45)
METAL_LO, METAL_HI = mix(METAL, WOOD_D, 0.15), mix(METAL, CREAM, 0.25)
R = random.Random(7)
parts = []

# --- dimensions --------------------------------------------------------------------------
LR, LL, SEG = 0.7, 4.6, 8       # log radius, length (along Y), sides
ROWS = (4, 3, 2)                 # logs per row, bottom up
FRONT = -LL / 2                  # front end plane (y)


def log(name, cx, cz, r, length, y0, seed):
    """closed log along +Y from y0: 2 bark rings (+ a mid ring for a slight bulge), each end cap =
    bark rim band -> heartwood ring -> darker core fan, the core sunk a hair so the rings read."""
    rr = random.Random(seed)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    ph = rr.random() * math.tau
    wob = [1 + 0.06 * (rr.random() * 2 - 1) for _ in range(SEG)]

    def ring(y, k=1.0, dy=0.0):
        return [bm.verts.new((cx + math.cos(ph + i * math.tau / SEG) * r * k * wob[i], y + dy,
                              cz + math.sin(ph + i * math.tau / SEG) * r * k * wob[i])) for i in range(SEG)]

    y1 = y0 + length
    tilt = 0.12 * (rr.random() * 2 - 1)  # uneven saw cut
    a0, am, a1 = ring(y0), ring((y0 + y1) / 2, 1.04), ring(y1)
    for a, b in ((a0, am), (am, a1)):
        for i in range(SEG):
            j = (i + 1) % SEG
            f = bm.faces.new((a[i], a[j], b[j], b[i]))
            for lp in f.loops:
                t = (lp.vert.co.z - (cz - r)) / (2 * r)
                lp[col] = shade(mix(BARK_LO, BARK_HI, t), 0.94 if i % 2 else 1.0)

    def cap(rim, y, s):
        """s = -1 front cap (normal -Y), +1 back cap."""
        mid = [bm.verts.new(Vector((cx, y, cz)) + (v.co - Vector((cx, v.co.y, cz))) * 0.8 + Vector((0, -s * 0.0, 0))) for v in rim]
        inn = [bm.verts.new(Vector((cx, y + s * 0.04, cz)) + (v.co - Vector((cx, v.co.y, cz))) * 0.42) for v in rim]
        c = bm.verts.new((cx, y + s * 0.05, cz))
        for v in mid + inn + [c]:
            v.co.y += tilt * (v.co.x - cx)
        out = []
        for i in range(SEG):
            j = (i + 1) % SEG
            q = (rim[i], rim[j], mid[j], mid[i])
            out.append((bm.faces.new(q if s > 0 else q[::-1]), WOOD_D))
            q = (mid[i], mid[j], inn[j], inn[i])
            out.append((bm.faces.new(q if s > 0 else q[::-1]), HEART))
            q = (inn[i], inn[j], c)
            out.append((bm.faces.new(q if s > 0 else q[::-1]), CORE))
        for f, cc in out:
            for lp in f.loops:
                lp[col] = cc

    for v in a0 + a1:
        v.co.y += tilt * (v.co.x - cx)
    cap(a0, y0, -1)
    cap(a1, y1, 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


# --- the pile: rows nest in the valleys of the row below ----------------------------------
logs = []  # (cx, cz, y0) for the goo
for ri, n in enumerate(ROWS):
    cz = LR + ri * LR * math.sqrt(3) * 0.98
    for k in range(n):
        cx = (k - (n - 1) / 2) * 2 * LR * 1.01
        L = LL + R.uniform(-0.25, 0.2)
        y0 = FRONT + R.uniform(-0.18, 0.12)
        r = LR * R.uniform(0.94, 1.04)
        parts.append(log(f"Log{ri}_{k}", cx, cz, r, L, y0, 100 + ri * 10 + k))
        logs.append((cx, cz, y0, r))

# --- stakes pinning the bottom row (2 per side) --------------------------------------------
SX = ROWS[0] * LR + 0.35
for sx in (-1, 1):
    for i, y in enumerate((-1.1, 1.1)):
        h = 3.0 + 0.25 * i
        parts.append(box(f"Stake{sx}_{i}", (0.42, 0.42, h), (sx * SX, y, h / 2), WOOD, rot=(0, -sx * 4, 0)))
        bevel(parts[-1], 0.08)
        gradient(parts[-1], mix(WOOD_D, WOOD, 0.4), mix(WOOD, CREAM, 0.12))

# --- chopping stump + axe on +X -------------------------------------------------------------
STX, STY, STR, STH = SX + 2.2, -0.9, 1.05, 1.55
parts.append(cylinder("Stump", STR, STH, (STX, STY, 0), WOOD, segs=9, r_top=STR * 0.94, jitter=0.04, seed=3))
gradient(parts[-1], BARK_LO, BARK_HI)
parts.append(cylinder("StumpTop", STR * 0.86, 0.06, (STX, STY, STH - 0.02), HEART, segs=9))
parts.append(cylinder("StumpCore", STR * 0.36, 0.08, (STX, STY, STH - 0.02), CORE, segs=7))
for k, a in enumerate((0.4, 2.3, 4.2)):  # root flares
    d = Vector((math.cos(a), math.sin(a), 0))
    p0 = Vector((STX, STY, 0.45)) + d * (STR * 0.8)
    parts.append(tube(f"Root{k}", [p0, p0 + d * 0.55 + Vector((0, 0, -0.3)), p0 + d * 0.9 + Vector((0, 0, -0.42))],
                      [0.32, 0.22, 0.12], WOOD, segs=5))
    gradient(parts[-1], BARK_LO, BARK_HI)
# axe: head bitten into the top, handle leaning toward the front-right
AX = Vector((STX - 0.15, STY + 0.1, STH + 0.05))
hdir = Vector((0.55, -0.35, 0.76)).normalized()
parts.append(tube("AxeHandle", [AX, AX + hdir * 1.4, AX + hdir * 2.6], [0.11, 0.1, 0.12], WOOD, segs=5))
gradient(parts[-1], mix(WOOD, CREAM, 0.1), mix(WOOD, CREAM, 0.3))
bm = bmesh.new()  # wedge blade: 2D profile (in the handle plane) extruded across
side = hdir.cross(Vector((0, 0, 1))).normalized()
perp = side.cross(hdir).normalized()  # blade direction, points down into the stump
prof = [AX + hdir * 0.4 - perp * 0.3, AX + hdir * 0.4 + perp * 0.12, AX + hdir * -0.45 + perp * 0.5,
        AX + hdir * -0.65 + perp * 0.15, AX + hdir * -0.5 - perp * 0.3]
f = bm.faces.new([bm.verts.new(p - side * 0.17) for p in prof])
ext = bmesh.ops.extrude_face_region(bm, geom=[f])
bmesh.ops.translate(bm, vec=side * 0.34, verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)])
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bmesh.ops.triangulate(bm, faces=[x for x in bm.faces if len(x.verts) > 4])
o = obj_from_bm("AxeHead", bm, METAL)
gradient(o, METAL_LO, METAL_HI)
parts.append(o)

# --- goo sap: out of the top log's front heartwood, down the ends, into a front puddle -------
top = max(logs, key=lambda l: (l[1], l[0]))
cx, cz, y0, r = top
balls = [Ball((cx + 0.05, y0 - 0.06, cz + 0.08), (0.3, 0.1, 0.26))]   # bead on the core
# short thin ooze over the lower rim of the top log's end, ending in a fat hanging drop
for s in range(1, 5):
    t = s / 4
    balls.append(Ball((cx + 0.05 + 0.06 * t, y0 - 0.06, cz - t * (r + 0.15)), (0.2 - 0.05 * t, 0.08, 0.2)))
balls.append(Ball((cx + 0.11, y0 - 0.12, cz - r - 0.35), (0.2, 0.17, 0.24)))
# second, smaller ooze on a bottom-row end (left of centre)
lo = min((l for l in logs if l[1] < LR * 1.2), key=lambda l: abs(l[0] + 2 * LR))
balls.append(Ball((lo[0] - 0.1, lo[2] - 0.06, lo[1] + 0.05), (0.24, 0.1, 0.2)))
for s in range(1, 3):
    balls.append(Ball((lo[0] - 0.1, lo[2] - 0.06, lo[1] - s * 0.25), (0.15, 0.08, 0.18)))
balls.append(Ball((lo[0] - 0.1, lo[2] - 0.1, 0.12), (0.4, 0.32, 0.12)))
# ground puddle where the drops land, with a couple of splash beads
for x, y, rr in ((cx, FRONT - 0.85, 0.85), (cx - 0.65, FRONT - 1.2, 0.55), (cx + 0.6, FRONT - 1.3, 0.45)):
    balls.append(Ball((x, y, 0.02), (rr, rr * 0.8, 0.13)))
for x, y in ((cx - 0.2, FRONT - 0.6), (cx + 0.45, FRONT - 1.0)):
    balls.append(Ball((x, y, 0.14), (0.14, 0.14, 0.12)))
goo = metaball_mesh("SapGoo", balls, resolution=0.08, tris=300, clamp_z=0.0)
print("goo nm", goo["nm"])
paint_goo(goo, lambda co, n: (*mix(GOO, GOO_HI, 0.12 + 0.4 * max(0.0, n.z if co.z < 0.4 else -n.y) ** 2)[:3], 1.0))
parts.append(goo)
# a few wood chips + grass tufts round the base
for k, (x, y) in enumerate(((STX - 1.4, STY - 1.3), (STX + 1.2, STY - 1.0), (STX + 0.3, STY + 1.6))):
    parts.append(box(f"Chip{k}", (0.45, 0.28, 0.1), (x, y, 0.05), HEART, rot=(0, 0, 37 * k + 15)))
for k, (x, y) in enumerate(((-SX - 0.4, -1.9), (SX + 0.3, 1.9), (-SX + 0.6, 2.4))):
    parts.append(blob(f"Tuft{k}", 0.45, (x, y, 0.15), FIELD_L, subdiv=1, squash=(1, 1, 0.7), jitter=0.15, seed=k))
    gradient(parts[-1], FIELD_D, FIELD_L)

finish("ranch_log_pile", parts)
