# slime_hat_bow: paid slime hat cosmetic, a big ribbon bow standing on the slime's head.
# Two ribbon loops (closed sweeps of a flat section along a pinched teardrop path in the XY plane, ribbon width
# along Z, so the front view -Y shows the ribbon's wide face), white polka dots, a round knot and two notched tails.
# Origin bottom centre, Z up, front -Y, ~2.0 wide. HAT_PREVIEW=1 adds a stand-in slime.
import math
import os
from models._pvp_fun import *
from models._pvp_fun import _paint

RIB = mix(RED, PINK, 0.45)              # bright pink-red ribbon
RIB_HI = mix(PINK, WHITE, 0.2)
RIB_LO = mix(RED, PINK, 0.3)
KNOT_Z = 0.3
N_PATH, N_SEC = 16, 8


def ribbon_loop(name, side):
    """Closed ribbon loop: path in the XY plane (flattened loop, pinched at the knot), the ribbon width along Z,
    so the front view -Y sees the wide face of the ribbon as a teardrop."""
    bm = bmesh.new()
    rings = []
    pts = []
    for i in range(N_PATH):
        t = i * math.tau / N_PATH
        f = 0.35 + 0.65 * (1 + math.cos(t)) / 2          # pinch toward the knot (t = pi)
        x = 0.57 + 0.43 * math.cos(t)
        y = 0.2 * math.sin(t) * f
        pts.append(Vector((side * x, y, 0)))
    for i, p in enumerate(pts):
        d = (pts[(i + 1) % N_PATH] - pts[i - 1]).normalized()
        n = d.cross(Vector((0, 0, 1))).normalized()
        x = abs(p.x)
        u = min(1, max(0, (x - 0.14) / 0.86))
        h = 0.17 + 0.27 * u ** 0.8 - 0.06 * u ** 6         # half height: narrow at the knot, round outer end
        zc = KNOT_Z + 0.04 + 0.3 * u                        # loops rise outward
        ring = []
        for k in range(N_SEC):
            b = k * math.tau / N_SEC
            ring.append(bm.verts.new(Vector((p.x, p.y, zc)) + Vector((0, 0, h * math.cos(b))) + n * 0.05 * math.sin(b)))
        rings.append(ring)
    keys = []
    for i in range(N_PATH):
        r0, r1 = rings[i], rings[(i + 1) % N_PATH]
        for k in range(N_SEC):
            j = (k + 1) % N_SEC
            bm.faces.new((r0[k], r0[j], r1[j], r1[k]))
            keys.append((i, k))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    nrm = {key: f.normal.copy() for key, f in zip(keys, bm.faces)}

    def col(i, k, c):
        n = nrm[(i, k)]
        radial = Vector((c.x - side * 0.57, c.y, 0))
        t = min(1, max(0, (c.z - 0.05) / 1.0))
        if radial.length > 1e-4 and n.dot(radial.normalized()) < -0.3:   # inside of the loop: shadowed
            return mix(RIB_LO, RIB, 0.25)
        if n.z > 0.55:
            return mix(RIB, RIB_HI, 0.75)                                  # top edge catches the light
        return mix(RIB_LO, RIB_HI, 0.2 + 0.55 * t)
    _paint(bm, keys, col, True)
    return obj_from_bm(name, bm, smooth=True)


def knot():
    prof = [(0.0, -0.26), (0.18, -0.25), (0.24, -0.16), (0.26, 0.0), (0.24, 0.16), (0.18, 0.25), (0.0, 0.26)]
    return lathe("Knot", prof, lambda i, k, c: mix(RIB_LO, mix(RIB, RIB_HI, 0.4), min(1, max(0, (c.z - 0.1) / 0.5))),
                 segs=8, phase=math.pi / 8, M=place((0, 0, KNOT_Z), (90, 0, 0)), rx=1.0, ry=1.15)


def tail(name, side):
    """Flat notched tail from under the knot, down and out to the side, leaning forward."""
    L, w = 0.56, 0.17
    pts = [(0, -w * 0.7), (L, -w), (L - 0.12, 0), (L, w), (0, w * 0.7)]
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, -0.035)) for x, y in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.z += 0.07
    bmesh.ops.triangulate(bm, faces=[g for g in bm.faces if len(g.verts) > 4])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # local x = along the tail, local z = slab normal (toward the front -Y, tilted up)
    along = Vector((side * 0.75, -0.18, -0.45)).normalized()
    nrm = Vector((0, -1, 0.35))
    nrm = (nrm - along * nrm.dot(along)).normalized()
    side_v = nrm.cross(along)
    M = Matrix((along, side_v, nrm)).transposed().to_4x4()
    M.translation = Vector((side * 0.08, -0.08, KNOT_Z - 0.02))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    _paint(bm, [(0, 0)] * len(bm.faces), lambda i, k, c: mix(RIB_LO, RIB, min(1, max(0, c.z / 0.4))), False)
    return obj_from_bm(name, bm)


def loop_point(side, t):
    f = 0.35 + 0.65 * (1 + math.cos(t)) / 2
    x = 0.57 + 0.43 * math.cos(t)
    y = 0.2 * math.sin(t) * f
    u = min(1, max(0, (x - 0.14) / 0.86))
    return Vector((side * x, y, KNOT_Z + 0.04 + 0.3 * u))


def dots(side):
    """Flat white polka dots lying flush on the front face of a loop (raised dots read as stuck-on gems)."""
    out = []
    for j, (t, dz) in enumerate([(1.62 * math.pi, 0.16), (1.8 * math.pi, -0.13), (1.36 * math.pi, -0.03)]):
        p = loop_point(side, t)
        d = (loop_point(side, t + 0.05) - loop_point(side, t - 0.05))
        d.z = 0
        n = d.normalized().cross(Vector((0, 0, 1)))
        if n.y > 0:
            n = -n
        r = 0.095 if j < 2 else 0.075
        c = p + Vector((0, 0, dz)) + n * 0.035
        M = frame_to(c, n)
        out.append(lathe("Dot%d_%d" % (side, j), [(0.0, 0.0), (r, 0.0), (r, 0.03), (0.0, 0.03)],
                         mix(WHITE, PINK, 0.08), segs=7, smooth=False, M=M))
    return out


def frame_to(p, n):
    n = n.normalized()
    t = Vector((0, 0, 1)).cross(n).normalized()
    b = n.cross(t)
    M = Matrix((t, b, n)).transposed().to_4x4()
    M.translation = p
    return M


parts = [ribbon_loop("LoopR", 1), ribbon_loop("LoopL", -1), knot(), tail("TailR", 1), tail("TailL", -1)]
parts += dots(1) + dots(-1)

if os.environ.get("HAT_PREVIEW"):
    SL = mix(GOO, P["ranch_field_dark"], 0.15)
    prof = [(0, -1.6), (0.9, -1.58), (1.15, -1.3), (1.2, -0.8), (1.05, -0.3), (0.7, -0.03), (0.0, 0.06)]
    parts.append(lathe("PreviewSlime", prof, lambda i, k, c: mix(SL, GOO, min(1, (c.z + 1.6) / 1.6)), segs=24))

o = finish("slime_hat_bow", parts)
a = o.data.attributes.get("keep_smooth")
if a is not None:
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
o["smooth_normals"] = 1
