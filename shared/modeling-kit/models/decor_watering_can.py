# decor_watering_can: chunky red watering can left standing by three flowers, rose dripping
# goo into a little puddle (Slime Ranch ground decoration, no collision).
# Can at -X, spout reaching +X over the flowers, puddle under the rose. Front faces -Y.
# Target 600-1500 tris. All parts closed shells (0 nm).
import math
import bmesh
from mathutils import Matrix, Vector
from lib import *

ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
CREAM, METAL = PALETTE["ranch_cream"], PALETTE["ranch_metal"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
PINK, LILAC, BUTTER = PALETTE["ranch_pink"], PALETTE["ranch_lilac"], PALETTE["ranch_butter"]
LEAF, LEAF_L, LEAF_D = PALETTE["ranch_field"], PALETTE["ranch_field_light"], PALETTE["ranch_field_dark"]
WOOD_D = PALETTE["ranch_wood_dark"]

RED_LO = mix(ROOF_D, ROOF, 0.65)
RED_HI = mix(ROOF, CREAM, 0.12)
TRIM_LO, TRIM_HI = mix(CREAM, METAL, 0.35), CREAM
METAL_LO, METAL_HI = METAL, mix(METAL, CREAM, 0.35)
parts = []

CX = -0.72          # can axis x
SEGS = 14


def lathe(name, profile, segs, color_fn, M=None, phase=0.0):
    """Closed surface of revolution about local Z; color_fn(row, z) per face. M places it."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(phase + k * math.tau / segs),
                                        r * math.sin(phase + k * math.tau / segs), z)) for k in range(segs)])
    faces = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segs):
            k1 = (k + 1) % segs
            if len(a) == 1:
                vs = (a[0], b[k1], b[k])
            elif len(b) == 1:
                vs = (a[k], a[k1], b[0])
            else:
                vs = (a[k], a[k1], b[k1], b[k])
            faces.append((bm.faces.new(vs), i))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    for f, i in faces:
        c = color_fn(i, f.calc_center_median())
        for lp in f.loops:
            lp[layer] = (*c[:3], 1.0)
    if M is not None:
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return obj_from_bm(name, bm)


def axis_matrix(origin, direction):
    """local +Z -> direction, placed at origin."""
    q = Vector(direction).normalized().to_track_quat("Z", "Y")
    return Matrix.Translation(Vector(origin)) @ q.to_matrix().to_4x4()


# ---------------- can body: bulged lathe, cream bands, goo-filled mouth ----------------
H = 2.05
body_prof = [
    (0.0, 0.0), (0.70, 0.0), (0.80, 0.08),          # foot
    (0.90, 0.30), (0.96, 0.72), (0.97, 0.98),        # bulge
    (0.97, 1.16), (0.93, 1.38),                      # belly band row 4 (0.98-1.16)
    (0.84, 1.60), (0.68, 1.82), (0.56, 1.92),        # shoulder
    (0.56, 2.05), (0.47, 2.05),                      # rim lip top
    (0.46, 1.96), (0.0, 1.96),                       # goo inside mouth
]
BAND_ROWS = {1, 4, 9, 10}     # foot bevel, belly band, rim lip in cream


def body_col(i, c):
    if i >= 12:
        d = math.hypot(c.x, c.y) / 0.46
        return mix(GOO, GOO_HI, min(1.0, d * d))
    if i in BAND_ROWS:
        return mix(TRIM_LO, TRIM_HI, min(1.0, c.z / H + 0.2))
    if i == 0:
        return RED_LO
    t = min(1.0, max(0.0, c.z / 1.8))
    col = mix(RED_LO, RED_HI, t)
    return col


body = lathe("Body", body_prof, SEGS, body_col, Matrix.Translation((CX, 0, 0)))
parts.append(body)

# ---------------- arched top handle (thick tube) ----------------
hp = []
for i in range(9):
    a = math.pi * i / 8
    # arch from the spout-side shoulder over to the back, rising ~0.85 above the rim
    x = CX + 0.62 * math.cos(a) - 0.05
    z = 1.72 + 0.95 * math.sin(a) + (0.0 if i < 8 else 0.0)
    hp.append((x, 0, z))
# back end drops down the body side so it reads as a classic can handle
hp[-1] = (CX - 0.80, 0, 1.45)
hp.insert(len(hp) - 1, (CX - 0.72, 0, 1.95))
handle = tube("Handle", hp, [0.19] * len(hp), ROOF, segs=8, twist_free=True)
gradient(handle, RED_LO, RED_HI)
parts.append(handle)

# ---------------- spout: sturdy tube from the low belly up and out to +X ----------------
sp = [(CX + 0.75, 0, 0.55), (CX + 1.15, 0, 0.85), (CX + 1.65, 0, 1.30), (CX + 2.05, 0, 1.70)]
spout = tube("Spout", sp, [0.30, 0.25, 0.22, 0.21], ROOF, segs=8)
gradient(spout, RED_LO, RED_HI)
parts.append(spout)

# rose head: flared lathe at the spout tip, tilted down toward the flowers
tip = Vector(sp[-1])
rdir = Vector((1.0, 0.0, -0.15)).normalized()
rose_prof = [(0.0, -0.05), (0.22, -0.05), (0.26, 0.12), (0.42, 0.32), (0.46, 0.40), (0.40, 0.44), (0.0, 0.44)]


def rose_col(i, c):
    if i >= 5:                       # perforated face
        return mix(METAL, CREAM, 0.15) if (int((c.x + 1) * 9) + int((c.y + 1) * 9)) % 2 else METAL_HI
    if i == 0:
        return METAL_LO
    return mix(TRIM_LO, TRIM_HI, 0.3 + 0.2 * i)


parts.append(lathe("Rose", rose_prof, 10, rose_col, axis_matrix(tip - rdir * 0.05, rdir)))

# cream collar where spout meets rose
parts.append(lathe("Collar", [(0, -0.08), (0.27, -0.08), (0.27, 0.08), (0, 0.08)], 8,
                   lambda i, c: TRIM_HI, axis_matrix(tip - rdir * 0.12, rdir)))


# ---------------- goo puddle: closed flat disc under the rose (r >= 1.8) ----------------
PX, PY = 1.05, -0.05
PRX, PRY, SEG = 1.8, 1.35, 16
bm = bmesh.new()
top_c = bm.verts.new((PX, PY, 0.09)); bot_c = bm.verts.new((PX, PY, 0.0))
tops, bots = [], []
for i in range(SEG):
    a = math.tau * i / SEG
    w = 1 + 0.12 * math.sin(3 * a + 0.6) + 0.06 * math.cos(5 * a)
    x, y = PX + PRX * w * math.cos(a), PY + PRY * w * math.sin(a)
    tops.append(bm.verts.new((x, y, 0.07))); bots.append(bm.verts.new((x, y, 0.0)))
for i in range(SEG):
    j = (i + 1) % SEG
    bm.faces.new((top_c, tops[i], tops[j])); bm.faces.new((bot_c, bots[j], bots[i]))
    bm.faces.new((tops[i], bots[i], bots[j], tops[j]))
bm.normal_update()
layer = bm.loops.layers.color.new("Col")
for f in bm.faces:
    col = mix(GOO, GOO_HI, 0.35) if f.normal.z > 0.5 else shade(GOO, 0.9)
    for lp in f.loops:
        lp[layer] = (*col[:3], 1.0)
bm.normal_update()
parts.append(obj_from_bm("Puddle", bm))
# glossy spots on the puddle
parts.append(blob("PudHi1", 0.42, (PX + 0.55, PY - 0.35, 0.08), GOO_HI, subdiv=1, squash=(1.3, 1.0, 0.18), jitter=0.05, seed=4))
parts.append(blob("PudHi2", 0.28, (PX - 0.55, PY + 0.45, 0.08), GOO_HI, subdiv=1, squash=(1.2, 1.0, 0.18), jitter=0.05, seed=9))

# goo drops falling from the rose
rose_face = tip + rdir * 0.42
for k, (dx, dz, r) in enumerate(((0.12, -0.45, 0.19), (0.02, -0.95, 0.16))):
    parts.append(blob(f"Drop{k}", r, (rose_face.x + dx, 0.0, rose_face.z + dz), GOO, subdiv=1,
                      squash=(0.85, 0.85, 1.35), jitter=0.02, seed=k + 3))
    gradient(parts[-1], shade(GOO, 0.9), GOO_HI)


# ---------------- three flowers being watered ----------------
def flower_head(name, center, normal, radius, petals, col, seed):
    """Closed petal slab (shoulder-tip-shoulder-valley per petal) + butter/cream centre bead."""
    bm = bmesh.new()
    pts = []
    for p in range(petals):
        a0 = math.tau * p / petals
        step = math.tau / petals
        for da, rr in ((0.12, 0.78), (0.5, 1.0), (0.88, 0.78), (1.0, 0.42)):
            a = a0 + da * step
            pts.append((radius * rr * math.cos(a), radius * rr * math.sin(a)))
    th = 0.13
    bot = [bm.verts.new((x, y, -th / 2)) for x, y in pts]
    top = [bm.verts.new((x, y, th / 2)) for x, y in pts]
    n = len(pts)
    ft = bm.faces.new(top); fb = bm.faces.new(list(reversed(bot)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.triangulate(bm, faces=[ft, fb])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    lo, hi = shade(col, 0.88), mix(col, CREAM, 0.25)
    for f in bm.faces:
        c = f.calc_center_median()
        d = min(1.0, math.hypot(c.x, c.y) / radius)
        cc = mix(hi, col, d) if f.normal.z > 0.3 else lo
        for lp in f.loops:
            lp[layer] = (*cc[:3], 1.0)
    bmesh.ops.transform(bm, matrix=axis_matrix(center, normal), verts=bm.verts)
    out = [obj_from_bm(name, bm)]
    nrm = Vector(normal).normalized()
    out.append(blob(name + "Eye", radius * 0.32, tuple(Vector(center) + nrm * 0.07), BUTTER if col != BUTTER else mix(BUTTER, ROOF, 0.35),
                    subdiv=1, squash=(1, 1, 0.7), jitter=0.03, seed=seed))
    return out


FLOWERS = [  # base (x, y), head height, colour, petals, head radius, head tilt
    ((2.25, 0.45), 1.60, PINK, 5, 0.62, (0.15, -0.8, 1.0)),
    ((1.75, -0.45), 1.00, BUTTER, 6, 0.55, (0.1, -0.75, 1.0)),
    ((0.75, 0.70), 1.20, LILAC, 5, 0.52, (-0.3, -0.75, 1.0)),
]
for n, ((bx, by), hz, col, pet, hr, tilt) in enumerate(FLOWERS):
    head = Vector((bx + tilt[0] * 0.15, by + tilt[1] * 0.15, hz))
    stem = tube(f"Stem{n}", [(bx, by, 0.02), (bx + tilt[0] * 0.05, by + tilt[1] * 0.05, hz * 0.55), tuple(head)],
                [0.09, 0.08, 0.07], LEAF_D, segs=5)
    gradient(stem, LEAF_D, LEAF)
    parts.append(stem)
    parts += flower_head(f"Flower{n}", head, tilt, hr, pet, col, seed=n + 11)
    # two leaves at the base
    for s, (ang, c) in enumerate(((0.6 + n, LEAF_L), (3.4 + n, LEAF))):
        lx, ly = bx + 0.28 * math.cos(ang), by + 0.28 * math.sin(ang)
        parts.append(blob(f"Leaf{n}{s}", 0.30, (lx, ly, 0.18), c, subdiv=1,
                          squash=(1.5, 0.75, 0.45), jitter=0.06, seed=n * 7 + s,
                          rot=(0, 25 if s else -25, math.degrees(ang))))
        gradient(parts[-1], LEAF_D, c)

finish("decor_watering_can", parts)
