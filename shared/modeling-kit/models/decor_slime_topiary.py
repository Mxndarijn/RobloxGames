# decor_slime_topiary: a garden hedge clipped into a cute gumdrop slime, in a small wooden tub,
# pink bow on top. Ground decor between plots (no collision), ~3.4 x 3.4 x 4.0 studs.
import math, random
import bmesh
from mathutils import Matrix, Vector, noise
from lib import *

FIELD = PALETTE["ranch_field"]
FIELD_L = PALETTE["ranch_field_light"]
FIELD_D = PALETTE["ranch_field_dark"]
WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
PINK = PALETTE["ranch_pink"]
METAL = PALETTE["ranch_metal"]
CREAM = PALETTE["ranch_cream"]
WOOD_LO = mix(WOOD_D, WOOD, 0.45)
PINK_D = mix(PINK, PALETTE["ranch_roof"], 0.3)

R = random.Random(731)
parts = []


def lathe(name, rows, segs, color_fn, disp=None, smooth=False):
    """Closed surface of revolution. rows: [(r, z)] bottom->top; r=0 at an end makes a pole.
    color_fn(face_center, ring_index, column) -> colour. disp(v_co) -> Vector offset."""
    bm = bmesh.new()
    rings = []
    for i, (r, z) in enumerate(rows):
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((math.cos(k * math.tau / segs) * r, math.sin(k * math.tau / segs) * r, z))
                          for k in range(segs)])
    faces = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segs):
            if len(a) == 1:
                f = bm.faces.new((a[0], b[k], b[(k + 1) % segs]))
            elif len(b) == 1:
                f = bm.faces.new((a[k], a[(k + 1) % segs], b[0]))
            else:
                f = bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
            faces.append((f, i, k))
    if len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if disp:
        for v in bm.verts:
            v.co += disp(v.co)
    layer = bm.loops.layers.color.new("Col")
    idx = {f: (i, k) for f, i, k in faces}
    for f in bm.faces:
        i, k = idx.get(f, (-1, -1))
        c = color_fn(f.calc_center_median(), i, k)
        for loop in f.loops:
            loop[layer] = c
    return obj_from_bm(name, bm, smooth=smooth)


# ---- wooden tub (staves, two pewter-brass hoops, rolled rim) ----
TUB_H, TUB_R0, TUB_R1 = 0.8, 1.3, 1.52
tub_rows = [(0.0, 0.0), (TUB_R0, 0.0)]
for z in (0.18, 0.42, 0.49, 0.56, 0.7):
    tub_rows.append((TUB_R0 + (TUB_R1 - TUB_R0) * z / TUB_H + (0.05 if z == 0.49 else 0.0), z))
tub_rows += [(TUB_R1 + 0.06, TUB_H), (TUB_R1 - 0.12, TUB_H + 0.04), (TUB_R1 - 0.2, TUB_H - 0.06), (0.0, TUB_H - 0.06)]
SEGS_T = 18


def tub_col(c, i, k):
    if c.z > TUB_H - 0.1 and math.hypot(c.x, c.y) < TUB_R1 - 0.15:
        return mix(WOOD_D, rgb(130, 96, 70), 0.3)  # mulch (hidden under the bush mostly)
    if 0.42 <= c.z <= 0.56:
        if 0.47 < c.z < 0.52:
            return mix(METAL, CREAM, 0.15)
        return METAL
    base = WOOD if k % 2 == 0 else mix(WOOD, WOOD_D, 0.45)
    t = min(1.0, c.z / TUB_H)
    return mix(shade(base, 0.93), base, t)


parts.append(lathe("Tub", tub_rows, SEGS_T, tub_col))

# ---- the slime hedge: gumdrop lathe with leafy noise ----
Z0, H, RB = TUB_H - 0.1, 2.7, 1.62
NR, SEGS_B = 13, 26


def prof(t):
    tuck = 0.8 + 0.2 * math.sin(min(1.0, t / 0.24) * math.pi / 2)
    return RB * tuck * max(0.0, 1 - t ** 2.3) ** 0.5


body_rows = [(0.0, Z0)]
for j in range(NR):
    t = j / NR
    body_rows.append((prof(t), Z0 + H * t))
body_rows.append((0.0, Z0 + H))
OFF = Vector((3.1, 7.3, 1.9))


def leafy(co):
    rr = math.hypot(co.x, co.y)
    if co.z <= Z0 + 1e-4:
        return Vector((0, 0, 0))
    n = Vector((co.x, co.y, (co.z - Z0 - 0.35 * H) * 0.9)).normalized()
    a = noise.noise(co * 2.2 + OFF) * 0.11 + noise.noise(co * 5.5 + OFF * 2) * 0.035
    return n * a


def body_col(c, i, k):
    t = min(1.0, max(0.0, (c.z - Z0) / H))
    lo, top = mix(FIELD_D, FIELD, 0.45), mix(FIELD_L, PALETTE["ranch_butter"], 0.14)
    if t < 0.4:
        base = mix(lo, FIELD, t / 0.4)
    elif t < 0.75:
        base = mix(FIELD, FIELD_L, (t - 0.4) / 0.35)
    else:
        base = mix(FIELD_L, top, (t - 0.75) / 0.25)
    return shade(base, R.uniform(0.94, 1.06))


parts.append(lathe("Body", body_rows, SEGS_B, body_col, disp=leafy))


def surf(theta, t, inset=0.0):
    """Point + outward normal on the (undisplaced) body at angle theta, height fraction t."""
    r = prof(t) - inset
    p = Vector((math.cos(theta) * r, math.sin(theta) * r, Z0 + H * t))
    dt = 0.01
    dr = (prof(t + dt) - prof(t - dt)) / (2 * dt * H)
    n = Vector((math.cos(theta), math.sin(theta), -dr)).normalized()
    return p, n


# ---- face: two dark clipped eye dimples, pink cheek blooms ----
for sx in (-1, 1):
    th = -math.pi / 2 + sx * 0.36
    p, n = surf(th, 0.47, 0.0)
    p = p + leafy(p) + n * 0.01
    e = blob(f"Eye{sx}", 1.0, (0, 0, 0), shade(FIELD_D, 0.86), subdiv=2, squash=(0.22, 0.33, 0.1), jitter=0.0)
    q = n.to_track_quat("Z", "Y")
    e.data.transform(Matrix.Translation(p) @ q.to_matrix().to_4x4())
    parts.append(e)

# ---- pink bow on top (faces -Y) ----
TOP = Z0 + H
for sx in (-1, 1):
    lobe = blob(f"Bow{sx}", 1.0, (0, 0, 0), PINK, seed=R.randint(0, 99), subdiv=2, squash=(0.42, 0.16, 0.27), jitter=0.02)
    lobe.data.transform(Matrix.Translation((sx * 0.38, -0.15, TOP + 0.12)) @ Matrix.Rotation(math.radians(sx * -22), 4, "Y"))
    gradient(lobe, PINK_D, PINK)
    parts.append(lobe)
knot = blob("Knot", 0.17, (0, -0.24, TOP + 0.1), PINK, subdiv=2, squash=(1, 0.9, 1.1), jitter=0.0)
parts.append(knot)

finish("decor_slime_topiary", parts)
