# slime_hat_flower_crown: paid slime hat cosmetic, a ring of small flowers and leaves.
# A green vine torus (~2.0 wide) with five petal-slab flowers (each tilted out and up, one at the front -Y)
# and pairs of leaves between them. Flat bottom: the vine rests on z=0.
# Origin bottom centre, Z up, front -Y. HAT_PREVIEW=1 adds a stand-in slime.
import math
import os
from models._pvp_fun import *
from models._pvp_fun import _paint

LEAF = P["ranch_field_light"]
LEAF_D = mix(P["ranch_field_dark"], LEAF, 0.6)
VINE = mix(P["ranch_field"], P["ranch_field_light"], 0.25)
BLUE = rgb(120, 196, 246)
R = 0.84            # vine ring radius
RT = 0.11           # vine tube radius
FLOWERS = [         # (angle deg, petal colour, centre colour, size)
    (-90, PINK, BUTTER, 1.0),
    (-18, mix(BUTTER, WHITE, 0.25), mix(RED, PINK, 0.4), 0.92),
    (54, BLUE, BUTTER, 0.95),
    (126, WHITE, BUTTER, 0.92),
    (198, LILAC, BUTTER, 0.95),
]


def frame(p, n, up_hint=Vector((0, 0, 1))):
    n = Vector(n).normalized()
    t = up_hint.cross(n)
    if t.length < 1e-4:
        t = Vector((1, 0, 0))
    t.normalize()
    b = n.cross(t)
    M = Matrix((t, b, n)).transposed().to_4x4()
    M.translation = Vector(p)
    return M


def slab(name, pts, thick, M, top, side):
    """Closed slab from a 2D outline (local z = thickness), placed by M. Flat shaded."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, -thick / 2)) for x, y in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.z += thick
    bmesh.ops.triangulate(bm, faces=[g for g in bm.faces if len(g.verts) > 4])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    bm.faces.ensure_lookup_table()
    nz = M.to_3x3() @ Vector((0, 0, 1))
    keys = []
    for g in bm.faces:
        d = g.normal.dot(nz)
        keys.append((0 if d > 0.5 else (2 if d < -0.5 else 1), 0))
    _paint(bm, keys, lambda i, k, c: (top, side, side)[i], False)
    return obj_from_bm(name, bm)


def petals(n=5, rc=0.13, rp=0.36, samples=20):
    pts = []
    for j in range(samples):
        th = j * math.tau / samples + math.pi / 2
        lobe = abs(math.cos(n * (th - math.pi / 2) / 2)) ** 0.5
        r = rc + (rp - rc) * lobe
        pts.append((r * math.cos(th), r * math.sin(th)))
    return pts


def leaf_pts(L=0.52, w=0.15):
    return [(0, 0), (L * 0.35, -w), (L * 0.75, -w * 0.7), (L, 0), (L * 0.75, w * 0.7), (L * 0.35, w)]


parts = [torus("Vine", R, RT, lambda i, k, c: mix(VINE, mix(VINE, LEAF, 0.6), max(0, min(1, (c.z) / (2 * RT)))),
               segs=14, rsegs=4, M=place((0, 0, RT)))]

for idx, (deg, pc, cc, s) in enumerate(FLOWERS):
    a = math.radians(deg)
    radial = Vector((math.cos(a), math.sin(a), 0))
    n = (radial * 0.7 + Vector((0, 0, 1)) * 0.7).normalized()
    pos = radial * (R + 0.06) + Vector((0, 0, 2 * RT + 0.1))
    M = frame(pos, n) @ Matrix.Rotation(idx * 0.6, 4, "Z") @ Matrix.Diagonal((s, s, s, 1))
    parts.append(slab("Flower%d" % idx, petals(), 0.07, M, mix(pc, WHITE, 0.12), mix(pc, LILAC, 0.25)))
    parts.append(ico("Centre%d" % idx, 0.1 * s, cc, subdiv=1, squash=(1, 1, 0.6),
                     M=Matrix.Translation(pos + n * 0.045 * s)))

for idx, (deg, _, _, _) in enumerate(FLOWERS):
    mid = deg + 36
    for sgn in (1,):
        a = math.radians(mid)
        radial = Vector((math.cos(a), math.sin(a), 0))
        tang = Vector((-math.sin(a), math.cos(a), 0)) * sgn
        n = (radial * 0.45 + Vector((0, 0, 1)) * 0.9).normalized()
        pos = radial * (R + 0.03) + Vector((0, 0, 2 * RT - 0.01)) - tang * 0.26
        M = frame(pos, n, up_hint=n.cross(tang))
        parts.append(slab("Leaf%d_%d" % (idx, sgn), leaf_pts(), 0.05, M, LEAF, LEAF_D))

BUDS = [mix(PINK, WHITE, 0.3), mix(BLUE, WHITE, 0.3), mix(BUTTER, WHITE, 0.2), mix(LILAC, WHITE, 0.2), mix(PINK, WHITE, 0.4)]
for idx, (deg, _, _, _) in enumerate(FLOWERS):
    a = math.radians(deg + 36 + 13)
    radial = Vector((math.cos(a), math.sin(a), 0))
    pos = radial * (R + 0.05) + Vector((0, 0, 2 * RT + 0.02))
    parts.append(ico("Bud%d" % idx, 0.12, BUDS[idx], subdiv=1, squash=(1, 1, 0.8), M=Matrix.Translation(pos)))

if os.environ.get("HAT_PREVIEW"):
    SL = mix(GOO, P["ranch_field_dark"], 0.15)
    prof = [(0, -1.6), (0.9, -1.58), (1.15, -1.3), (1.2, -0.8), (1.05, -0.3), (0.7, -0.03), (0.0, 0.06)]
    parts.append(lathe("PreviewSlime", prof, lambda i, k, c: mix(SL, GOO, min(1, (c.z + 1.6) / 1.6)), segs=24))

o = finish("slime_hat_flower_crown", parts)
a = o.data.attributes.get("keep_smooth")
if a is not None:
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
o["smooth_normals"] = 1
