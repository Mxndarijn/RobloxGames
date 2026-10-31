# decor_wildflower_clump: lush clump of wildflowers growing straight out of the grass (Slime Ranch ground decor).
# Low mound of broad, arching, cupped leaves (field_dark below -> field_light above) with 6 big chunky
# cosmos-style blooms (6 fat cupped petals + domed contrasting centre) on short curved stems at 1.2-2.8 studs,
# in ranch_pink / ranch_lilac / ranch_butter, plus 2 closed buds. Uneven cluster, ~3.3 studs across.
# Pure decor (no collision). Target 600-1500 tris. lib rot= is in DEGREES; cylinder() pos = base.
import math, random
import bmesh
from mathutils import Matrix, Vector
from lib import *

PINK, LILAC, BUTTER = PALETTE["ranch_pink"], PALETTE["ranch_lilac"], PALETTE["ranch_butter"]
CREAM, ROOF, WOOD = PALETTE["ranch_cream"], PALETTE["ranch_roof"], PALETTE["ranch_wood"]
FIELD, FIELD_D, FIELD_L = PALETTE["ranch_field"], PALETTE["ranch_field_dark"], PALETTE["ranch_field_light"]
ORANGE = mix(BUTTER, ROOF, 0.45)
R = random.Random(11)
parts = []


def paint(o, fn):
    """per-corner colour from fn(local co, face normal)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.normal_update()
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            lp[layer] = (*fn(lp.vert.co, f.normal)[:3], 1.0)
    bm.to_mesh(o.data)
    bm.free()
    return o


def frame(origin, z_axis, x_hint):
    z = Vector(z_axis).normalized()
    x = (Vector(x_hint) - z * Vector(x_hint).dot(z)).normalized()
    y = z.cross(x)
    return Matrix.Translation(Vector(origin)) @ Matrix((x, y, z)).transposed().to_4x4()


# --- leaves: arching, cupped closed blades -------------------------------------------------
def leaf(name, base, yaw, L, W, rise, droop, thick=0.07, n=5):
    """blade along local +x from base, width profile sin, arcs up by `rise` then down by `droop` at the tip,
    edges cupped up. Closed (top/bottom/sides/caps)."""
    bm = bmesh.new()
    top, bot = [], []
    for i in range(n + 1):
        u = i / n
        w = W * (math.sin(math.pi * min(1.0, u * 0.92 + 0.08)) ** 0.8) * (1 - 0.35 * u) + 0.02
        z = rise * math.sin(math.pi * u * 0.8) - droop * u ** 2.2
        x = L * u
        rowt, rowb = [], []
        for s in (-1, 0, 1):
            cz = 0.0 if s == 0 else 0.13 * W  # cup: edges up
            yy = s * w / 2
            if s == 0:
                yy = 0.0
            rowt.append(bm.verts.new((x, yy, z + cz + thick / 2)))
            rowb.append(bm.verts.new((x, yy, z + cz - thick / 2)))
        top.append(rowt)
        bot.append(rowb)
    for i in range(n):
        for k in range(2):
            bm.faces.new((top[i][k], top[i][k + 1], top[i + 1][k + 1], top[i + 1][k]))
            bm.faces.new((bot[i][k], bot[i + 1][k], bot[i + 1][k + 1], bot[i][k + 1]))
        for k in (0, 2):  # side walls
            bm.faces.new((top[i][k], top[i + 1][k], bot[i + 1][k], bot[i][k]))
    for i in (0, n):  # end caps
        bm.faces.new((top[i][0], top[i][1], top[i][2], bot[i][2], bot[i][1], bot[i][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    M = Matrix.Translation(Vector(base)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    o = obj_from_bm(name, bm)
    zt = base[2] + rise
    return paint(o, lambda co, nrm: mix(mix(FIELD_D, FIELD, 0.35), mix(FIELD_L, CREAM, 0.12), max(0.0, min(1.0, co.z / max(0.3, zt + 0.1))) ** 0.7)
                 if nrm.z > -0.3 else mix(FIELD_D, FIELD, 0.5))


# --- mound core ------------------------------------------------------------------------------
for k, (x, y, r, sq, sd) in enumerate(((0.0, 0.1, 0.95, 0.55, 1), (-0.6, -0.35, 0.6, 0.55, 1), (0.65, 0.25, 0.65, 0.5, 1))):
    parts.append(blob(f"Mound{k}", r, (x, y, 0.08), FIELD_D, subdiv=sd, squash=(1.15, 1.0, sq), jitter=0.06, seed=k + 2))
    gradient(parts[-1], FIELD_D, FIELD, z0=0.0, z1=0.6)

# 11 leaves radiating out of the mound, uneven yaw and length
LEAVES = []
for k in range(8):
    yaw = k * 360 / 8 + R.uniform(-16, 16)
    L = R.uniform(1.15, 1.45) * (1 - 0.14 * abs(math.sin(math.radians(yaw))))
    LEAVES.append((yaw, L))
for k, (yaw, L) in enumerate(LEAVES):
    a = math.radians(yaw)
    base = (0.25 * math.cos(a) + R.uniform(-0.1, 0.1), 0.25 * math.sin(a) + R.uniform(-0.1, 0.1), 0.15)
    parts.append(leaf(f"Leaf{k}", base, yaw, L, R.uniform(0.78, 0.95), R.uniform(0.35, 0.55), R.uniform(0.45, 0.6), n=4))

# inner ring: 4 shorter, more upright leaves to fill round the stems
for k in range(4):
    yaw = 45 + k * 90 + R.uniform(-20, 20)
    a = math.radians(yaw)
    parts.append(leaf(f"Inner{k}", (0.1 * math.cos(a), 0.1 * math.sin(a), 0.3), yaw, R.uniform(0.85, 1.0),
                      R.uniform(0.6, 0.7), R.uniform(0.6, 0.8), 0.55, n=3))

# --- blooms ----------------------------------------------------------------------------------
NP = 6
BLOOMS = [  # (x, y, head z, radius, petal colour, centre colour)
    (-0.35, -0.15, 2.55, 0.78, PINK, BUTTER),
    (0.6, 0.2, 2.15, 0.72, BUTTER, ORANGE),
    (-0.95, 0.45, 1.85, 0.66, LILAC, BUTTER),
    (0.9, -0.75, 1.45, 0.64, PINK, BUTTER),
    (-0.05, 0.85, 1.6, 0.66, LILAC, BUTTER),
    (-1.05, -0.8, 1.25, 0.6, BUTTER, ORANGE),
]
CX, CY = -0.05, 0.0


def bloom(i, x, y, hz, r, pc, cc):
    out = Vector((x - CX, y - CY, 0))
    out = out.normalized() if out.length > 1e-3 else Vector((0, -1, 0))
    lean = 0.55 if hz < 2.5 else 0.35
    if out.y > 0:  # back blooms: turn their outward lean sideways so they still show to the front
        out = Vector((out.x, out.y * 0.25, 0)).normalized()
    face = (Vector((0, 0, 1)) + out * lean + Vector((-0.15, -0.45, 0))).normalized()
    head = Vector((x, y, hz))
    M = frame(head, face, (math.cos(i * 1.7), math.sin(i * 1.7), 0))
    # petal disc: centre fan + ring (valley, shoulder, tip, shoulder per petal), cupped, closed
    ring = []
    rot0 = R.uniform(0, math.tau)
    for k in range(NP):
        a = rot0 + k * math.tau / NP
        rr = r * R.uniform(0.94, 1.06)
        for da, f in ((-math.pi / NP, 0.42), (-0.3, 0.86), (0.0, 1.0), (0.3, 0.86)):
            ring.append((a + da, rr * f))
    th = 0.13
    bm = bmesh.new()
    def cup(rad):
        return 0.32 * r * (rad / r) ** 2
    ct = bm.verts.new((0, 0, th / 2))
    cb = bm.verts.new((0, 0, -th / 2))
    rt = [bm.verts.new((math.cos(a) * rad, math.sin(a) * rad, cup(rad) + th / 2)) for a, rad in ring]
    rb = [bm.verts.new((math.cos(a) * rad, math.sin(a) * rad, cup(rad) - th / 2)) for a, rad in ring]
    m = len(ring)
    for k in range(m):
        k2 = (k + 1) % m
        bm.faces.new((ct, rt[k], rt[k2]))
        bm.faces.new((cb, rb[k2], rb[k]))
        bm.faces.new((rt[k], rb[k], rb[k2], rt[k2]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    o = obj_from_bm(f"Petals{i}", bm)
    lo, hi = mix(pc, shade(pc, 0.9), 0.5), mix(pc, CREAM, 0.3)
    under = mix(pc, CREAM, 0.22)  # lifted: the underside is in shade in the game light
    paint(o, lambda co, n: mix(lo, hi, min(1.0, (co - head).length / r) ** 1.2) if n.dot(face) > -0.2 else under)
    parts.append(o)
    # domed centre
    c = cylinder(f"Centre{i}", r * 0.36, 0.2, (0, 0, th / 2 - 0.02), cc, segs=6, r_top=r * 0.24)
    c.data.transform(M)
    paint(c, lambda co, n: mix(shade(cc, 0.88), mix(cc, CREAM, 0.25), max(0.0, n.dot(face))))
    parts.append(c)
    # green calyx under the head
    # stem: from inside the mound, slight bow, into the calyx
    back = head - face * 0.25
    p0 = Vector((x * 0.6 + CX * 0.4, y * 0.6, 0.2))
    mid = p0.lerp(back, 0.5) + out * 0.12
    parts.append(tube(f"Stem{i}", [p0, mid, back], [0.09, 0.08, 0.07], FIELD_D, segs=3))
    gradient(parts[-1], mix(FIELD_D, FIELD, 0.3), FIELD_L)


for i, b in enumerate(BLOOMS):
    bloom(i, *b)

# 2 closed buds
for k, (x, y, hz, col) in enumerate(((0.35, -0.25, 1.9, PINK), (1.2, 0.6, 1.2, LILAC))):
    p = Vector((x, y, hz))
    parts.append(blob(f"Bud{k}", 0.2, p, col, subdiv=1, squash=(1, 1, 1.45), jitter=0.05, seed=20 + k))
    gradient(parts[-1], shade(col, 0.88), mix(col, CREAM, 0.2))
    parts.append(tube(f"BudStem{k}", [(x * 0.6, y * 0.6, 0.2), (x * 0.9, y * 0.9, hz * 0.55), (x, y, hz - 0.2)], [0.07, 0.06, 0.06], FIELD_D, segs=3))
    gradient(parts[-1], mix(FIELD_D, FIELD, 0.3), FIELD_L)

finish("decor_wildflower_clump", parts)
