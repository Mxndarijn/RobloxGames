# ranch_pumpkin_patch: low mounded soil bed with chunky pumpkins on curly vines (Slime Ranch farm / plaza prop).
# ~6 x 6 rounded soil mound (closed polar heightfield, light crown -> dark foot, shallow furrow rings),
# 4 ribbed pumpkins (closed lathe, lobes = radius modulated per column; orange = mix of butter + roof,
# dark lows / butter highs, valleys a step darker) with chunky curved wood_dark stems, curly vines
# (tubes) + slab leaves + spiral tendrils across the soil. The biggest pumpkin has goo spilled over
# its crown: metaball lens collar round the stem, drips down rib valleys, puddle at its foot (lib/goo.py).
# Medium prop, target 500-2000 tris, ~2-3 studs tall. cylinder() pos = base; lib rot= is in DEGREES.
import math, random
import bmesh
from mathutils import Matrix, Vector
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, PATH = PALETTE["ranch_cream"], PALETTE["ranch_path"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
BUTTER = PALETTE["ranch_butter"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
FIELD, FIELD_D, FIELD_L = PALETTE["ranch_field"], PALETTE["ranch_field_dark"], PALETTE["ranch_field_light"]
ORANGE = mix(BUTTER, ROOF, 0.5)
PUMP_LO, PUMP_HI = mix(ORANGE, ROOF, 0.35), mix(ORANGE, BUTTER, 0.55)
SOIL_LO, SOIL_HI = WOOD_D, mix(WOOD_D, WOOD, 0.4)
R = random.Random(11)
parts = []

# --- dimensions --------------------------------------------------------------------------
BED, BH = 3.0, 0.45        # soil half-width (superellipse "radius"), crown height


def bed_r(a):
    """rounded-square outline (superellipse n=4) with a little wobble."""
    c, s = abs(math.cos(a)), abs(math.sin(a))
    r = (c ** 4 + s ** 4) ** -0.25
    return BED * r * (1 + 0.035 * math.sin(5 * a + 1.0) + 0.025 * math.cos(3 * a))


def bed_z(t):
    """crown height at fraction t of the outline radius (0 centre, 1 edge)."""
    return 0.06 + BH * (1 - t ** 2.2) ** 0.6


# --- soil mound: centre fan + rings + side band + bottom fan (closed) -------------------------
SEG, RINGS = 20, 4
bm = bmesh.new()
col = bm.loops.layers.color.new("Col")
ctop = bm.verts.new((0, 0, bed_z(0)))
cbot = bm.verts.new((0, 0, 0))
rings = []
for k in range(1, RINGS + 1):
    t = k / RINGS
    ring = []
    for i in range(SEG):
        a = i * math.tau / SEG
        r = bed_r(a) * t
        ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), bed_z(t) + (0.04 if k == 2 else 0))))
    rings.append(ring)
foot = [bm.verts.new((v.co.x * 1.03, v.co.y * 1.03, 0)) for v in rings[-1]]
faces = []
for i in range(SEG):
    j = (i + 1) % SEG
    faces.append(bm.faces.new((ctop, rings[0][i], rings[0][j])))
    for a, b in zip(rings, rings[1:]):
        faces.append(bm.faces.new((a[i], b[i], b[j], a[j])))
    faces.append(bm.faces.new((rings[-1][i], foot[i], foot[j], rings[-1][j])))
    faces.append(bm.faces.new((cbot, foot[j], foot[i])))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
for f in bm.faces:
    for lp in f.loops:
        z = lp.vert.co.z / (BH + 0.06)
        lp[col] = mix(SOIL_LO, SOIL_HI, min(1, z ** 0.8))
parts.append(obj_from_bm("Soil", bm))


def soil_z(x, y):
    a = math.atan2(y, x)
    t = min(1.0, math.hypot(x, y) / bed_r(a))
    return bed_z(t)


# --- pumpkins --------------------------------------------------------------------------------
def pumpkin(name, c, rad, h, ribs, yaw, rows=6):
    """closed ribbed lathe: SEG = 3 per rib (lobe, lobe, valley), sunken crown + base dimples."""
    seg = ribs * 3
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    top = bm.verts.new(c + Vector((0, 0, h * 0.86)))
    bot = bm.verts.new(c + Vector((0, 0, h * 0.06)))
    rr, vset = [], set()
    for k in range(1, rows):
        phi = -math.pi / 2 + math.pi * k / rows
        ring = []
        for i in range(seg):
            a = yaw + i * math.tau / seg
            lobe = 1 - 0.11 * (1 if i % 3 == 0 else 0)          # valley column
            r = rad * math.cos(phi) ** 0.85 * lobe
            z = h * 0.5 + h * 0.5 * math.sin(phi)
            if k == rows - 1:
                z -= h * 0.04                                    # shoulder rolls into the crown dimple
            ring.append(bm.verts.new(c + Vector((r * math.cos(a), r * math.sin(a), z))))
            if i % 3 == 0:
                vset.add(ring[-1])
        rr.append(ring)
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((bot, rr[0][j], rr[0][i]))
        for a, b in zip(rr, rr[1:]):
            bm.faces.new((a[i], a[j], b[j], b[i]))
        bm.faces.new((rr[-1][i], rr[-1][j], top))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        valley = any(v in vset for v in f.verts)
        for lp in f.loops:
            t = (lp.vert.co.z - c.z) / h
            cc = mix(PUMP_LO, PUMP_HI, min(1, max(0, t)) ** 0.9)
            lp[col] = shade(cc, 0.93 if valley else 1.0)
    o = obj_from_bm(name, bm, smooth=True)
    return o


PUMPKINS = [  # (x, y, radius, height, ribs)
    (0.35, -0.55, 1.35, 1.75, 8),   # big one, goo on top
    (-1.75, 0.55, 1.05, 1.35, 8),
    (1.75, 1.15, 0.95, 1.2, 7),
    (-0.7, -2.1, 0.68, 0.85, 6),
]
crowns = []
for n, (x, y, rad, h, ribs) in enumerate(PUMPKINS):
    c = Vector((x, y, soil_z(x, y) - 0.12))
    parts.append(pumpkin(f"Pumpkin{n}", c, rad, h, ribs, R.uniform(0, 1), rows=6 if n == 0 else 5))
    crown = c + Vector((0, 0, h * 0.86))
    crowns.append((crown, rad, h, c))
    # stem: chunky, tapers, curls over to one side
    side = Vector((math.cos(n * 2.1 + 0.5), math.sin(n * 2.1 + 0.5), 0))
    sr = 0.15 + 0.06 * rad
    pts = [crown - Vector((0, 0, 0.12)), crown + Vector((0, 0, 0.3 * rad)), crown + Vector((0, 0, 0.48 * rad)) + side * 0.18 * rad,
           crown + Vector((0, 0, 0.5 * rad)) + side * 0.38 * rad]
    parts.append(tube(f"Stem{n}", pts, [sr * 1.25, sr, sr * 0.9, sr * 0.75], WOOD_D, segs=6))
    gradient(parts[-1], WOOD_D, mix(WOOD_D, WOOD, 0.6))

# --- vines: curly tubes along the soil joining the stems, slab leaves + spiral tendrils -----------


def paint(o, fn):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            lp[layer] = (*fn(lp.vert.co)[:3], 1.0)
    bm.to_mesh(o.data)
    bm.free()
    return o


def slab(name, pts2d, thick, M, color_fn):
    bm = bmesh.new()
    f = bm.faces.new([bm.verts.new((x, y, -thick / 2)) for x, y in pts2d])
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, 0, thick), verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[x for x in bm.faces if len(x.verts) > 4])
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return paint(obj_from_bm(name, bm), color_fn)


def on_soil(x, y, lift=0.08):
    return Vector((x, y, soil_z(x, y) + lift))


VINES = [  # polyline control points (x, y) across the bed
    [(0.35, -0.55), (-0.6, -0.4), (-1.2, 0.0), (-1.75, 0.55)],
    [(0.35, -0.55), (1.3, -0.2), (1.9, 0.3), (1.75, 1.15)],
    [(-1.75, 0.55), (-1.9, -0.6), (-1.4, -1.6), (-0.7, -2.1)],
    [(1.75, 1.15), (0.6, 1.9), (-0.6, 2.1), (-1.6, 1.9)],
]
leaf_spots = []
for vi, ctrl in enumerate(VINES):
    pts = []
    for (x0, y0), (x1, y1) in zip(ctrl, ctrl[1:]):
        for s in range(2):
            t = s / 2
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            w = 0.18 * math.sin(t * math.pi * 2 + vi)       # wavy, not a ruler line
            nx, ny = -(y1 - y0), (x1 - x0)
            ln = math.hypot(nx, ny) or 1
            pts.append(on_soil(x + w * nx / ln, y + w * ny / ln))
    pts.append(on_soil(*ctrl[-1]))
    # pull the vine ends under the pumpkins so they read as growing from them
    parts.append(tube(f"Vine{vi}", pts, [0.11] * len(pts), FIELD_D, segs=4))
    gradient(parts[-1], FIELD_D, FIELD)
    for k in (1, 4):
        if k < len(pts) - 1:
            leaf_spots.append((pts[k], (pts[k + 1] - pts[k - 1]).normalized(), vi * 7 + k))

LEAF = [(0, 0), (0.25, 0.42), (0.6, 0.55), (0.95, 0.4), (1.15, 0.0), (0.95, -0.4), (0.6, -0.55), (0.25, -0.42)]
for li, (p, d, seed) in enumerate(leaf_spots):
    s = 1 if seed % 2 else -1
    xa = (d.cross(Vector((0, 0, 1))) * s + d * 0.4).normalized()
    xa = (xa + Vector((0, 0, 0.35))).normalized()
    za = Vector((0, -0.3, 1)).normalized()
    za = (za - xa * za.dot(xa)).normalized()
    ya = za.cross(xa)
    sc = 1.15 + 0.25 * ((seed * 37) % 5) / 4
    M = Matrix.Translation(p) @ Matrix((xa, ya, za)).transposed().to_4x4() @ Matrix.Diagonal((sc, sc, 1, 1))
    parts.append(slab(f"Leaf{li}", LEAF, 0.09, M,
                      lambda co: mix(FIELD, FIELD_L, min(1, math.hypot(co.x, co.y) / 1.1) * 0.85)))

# spiral tendrils (curly-q) standing up off the vines
for ti, (x, y, turn) in enumerate(((-1.0, 0.1, 1), (-0.1, 2.0, 1), (1.9, -0.2, -1))):
    base = on_soil(x, y, 0.05)
    pts = []
    for s in range(7):
        t = s / 6
        a = turn * t * math.tau * 1.4
        rr = 0.32 * (1 - 0.6 * t)
        pts.append(base + Vector((rr * math.cos(a) - 0.32, rr * math.sin(a), 0.1 + 0.55 * t)))
    parts.append(tube(f"Tendril{ti}", pts, [0.08] * 6 + [0.065], FIELD_D, segs=4))
    gradient(parts[-1], FIELD_D, FIELD_L)

# --- goo spilled over the big pumpkin's crown --------------------------------------------------
crown, rad, h, c = crowns[0]


def surf(a, frac):
    """point on the big pumpkin's lobe surface at azimuth a, height frac (0 base .. 1 crown) + outward normal."""
    phi = math.asin(max(-1, min(1, frac * 2 - 1)))
    r = rad * math.cos(phi) ** 0.85
    p = c + Vector((r * math.cos(a), r * math.sin(a), h * frac))
    n = Vector((math.cos(a) * math.cos(phi), math.sin(a) * math.cos(phi), math.sin(phi) * 0.9)).normalized()
    return p, n


balls = [Ball(crown + Vector((0, 0, -0.02)), (0.42, 0.42, 0.13))]   # pool round the stem
for k in range(10):  # collar of flat lenses on the shoulder
    a = k * math.tau / 10 + 0.2
    p, n = surf(a, 0.86 + 0.06 * math.sin(3 * a + 1) * math.cos(2 * a))
    x = Vector((-math.sin(a), math.cos(a), 0))
    q = frame_quat(x, n.cross(x), n)
    balls.append(Ball(p - n * 0.05, (0.3, 0.2, 0.1), rot=q))
# drips down the front (toward -Y and the sun at front-left): lens chains with a fat drop
for a0, length in ((-math.pi / 2 - 0.15, 0.5), (-math.pi / 2 + 0.7, 0.28)):
    steps = 4
    for s in range(1, steps + 1):
        t = s / steps
        p, n = surf(a0, 0.86 - t * length)
        x = Vector((-math.sin(a0), math.cos(a0), 0))
        q = frame_quat(x, n.cross(x), n)
        w = 0.2 - 0.06 * t
        balls.append(Ball(p - n * 0.03, (w, 0.22, 0.1), rot=q))
    p, n = surf(a0, 0.86 - length - 0.06)
    balls.append(Ball(p + n * 0.03, (0.19, 0.19, 0.22)))
goo = metaball_mesh("PumpkinGoo", balls, resolution=0.07, tris=170)
print("goo nm", goo["nm"])
paint_goo(goo, lambda co, n: (*mix(GOO, GOO_HI, 0.12 + 0.45 * max(0.0, n.z) ** 2)[:3], 1.0))
parts.append(goo)
# puddle at the big pumpkin's foot under the main drip
pb = [Ball(c + Vector((x, y - rad * 0.95, 0.12)), (rr, rr * 0.75, 0.1)) for x, y, rr in ((-0.15, -0.15, 0.6), (0.35, -0.35, 0.38))]
pud = metaball_mesh("PumpkinPuddle", pb, resolution=0.08, tris=60)
print("puddle nm", pud["nm"])
paint_goo(pud, lambda co, n: mix(GOO, GOO_HI, 0.3 * max(0.0, n.z)))
parts.append(pud)

finish("ranch_pumpkin_patch", parts)
