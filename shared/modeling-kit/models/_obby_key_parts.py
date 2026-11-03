# Shared helpers for the obby key options (obby_key_a/b/c), not an asset.
# The old key (KeyRun `key`, ObbyParts look "key") is a 1.5 x 1.5 x 1.5 Neon gold cube (255,205,60) floating 2.5 studs
# over the floor, no spin, a few sparkles; you grab it by touch (the 1.5 box + ObbyFx.KEY_PAD 1.5). Every option
# stands upright in about that box (height 1.5-1.65, bow on top, the key's flat face to -Y) so it can drop into the
# same slot. 1 BU = 1 stud, Z up, front -Y.
import math
import bmesh
from mathutils import Matrix, Vector
from lib import *
from lib.shapes import obj_from_bm, _place
from models._obby_cannon_parts import lathe, finish_smooth, smooth

# Gold, lifted for the Roblox look (LESSONS: gold darker than ~f2b440 goes brown; lows stay orange, not brown).
GOLD_LO = rgb(246, 166, 50)
GOLD = rgb(255, 196, 58)
GOLD_HI = rgb(255, 232, 140)
GOLD_SHINE = rgb(255, 250, 214)
RIM = rgb(232, 118, 36)        # a darker orange outline / edge band
GOO_DEEP = rgb(40, 162, 126)   # gameplay goo (teal-green, LESSONS pvp traps)
GOO = rgb(72, 218, 170)
GOO_HI = rgb(170, 250, 220)
GATE = rgb(150, 90, 220)       # the gate's purple (ObbyParts `gate`)
GATE_LO = rgb(112, 72, 186)
GATE_HI = rgb(214, 182, 255)
WHITE = rgb(255, 255, 255)
INK = rgb(40, 30, 56)

LIGHT = Vector((-0.45, -0.55, 0.7)).normalized()   # where the painted highlight sits (front-left-up)


def metal(co, n, lo=GOLD_LO, mid=GOLD, hi=GOLD_HI, shine=GOLD_SHINE):
    """Painted cartoon metal by normal: down-facing -> lo, sideways -> mid, toward LIGHT -> hi, a tight shine spot."""
    d = n.dot(LIGHT)
    up = n.z
    c = mix(lo, mid, min(1.0, max(0.0, 0.55 + up * 0.6)))
    if d > 0.25:
        c = mix(c, hi, min(1.0, (d - 0.25) / 0.5))
    if d > 0.86:
        c = mix(c, shine, min(1.0, (d - 0.86) / 0.1))
    return c


def paint(o, fn, smooth_faces=True):
    """Per-corner colour from fn(world co, normal); flat faces use the face normal, smooth ones the vertex normal."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.normal_update()
    col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    sm = bm.faces.layers.int.get("keep_smooth") or bm.faces.layers.int.new("keep_smooth")
    mw = o.matrix_world
    r3 = mw.to_3x3()
    for f in bm.faces:
        f.smooth = smooth_faces
        f[sm] = int(smooth_faces)
        for lp in f.loops:
            nn = lp.vert.normal if smooth_faces else f.normal
            lp[col] = fn(mw @ lp.vert.co, (r3 @ nn).normalized())
    bm.to_mesh(o.data)
    bm.free()
    return o


def torus_xz(name, R, r, pos=(0, 0, 0), segs=24, sides=10, sy=1.0, rot=(0, 0, 0)):
    """A standing torus in the XZ plane (its hole faces -Y). sy squashes the tube's depth (a flatter, coin-like ring)."""
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = i * math.tau / segs
        c = Vector((math.cos(a) * R, 0, math.sin(a) * R))
        out = Vector((math.cos(a), 0, math.sin(a)))
        ring = []
        for k in range(sides):
            b = k * math.tau / sides
            p = c + out * (math.cos(b) * r) + Vector((0, math.sin(b) * r * sy, 0))
            ring.append(bm.verts.new(p))
        rings.append(ring)
    for i in range(segs):
        A, B = rings[i], rings[(i + 1) % segs]
        for k in range(sides):
            bm.faces.new((A[k], A[(k + 1) % sides], B[(k + 1) % sides], B[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm)


def rbox(name, size, pos, bev=0.06, rot=(0, 0, 0)):
    o = box(name, size, pos, GOLD, rot=rot)
    if bev:
        bevel(o, bev, segments=2)
    return o


def slab(name, pts, thick, pos=(0, 0, 0), bev=0.0):
    """Flat shape from a 2D outline (x, z), extruded `thick` along Y and centred on y=0 (faces -Y). Concave is fine."""
    bm = bmesh.new()
    vs = [bm.verts.new((u, -thick / 2, v)) for u, v in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, thick, 0)), verts=nv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[g for g in bm.faces if len(g.verts) > 4])
    bmesh.ops.translate(bm, vec=Vector(pos), verts=bm.verts)
    o = obj_from_bm(name, bm)
    if bev:
        bevel(o, bev, segments=1, angle=30)
    return o


def offset_pts(pts, d):
    """Push a closed CCW outline out by d along the averaged edge normals (a rim/outline behind a face)."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e0 = (p1 - p0).normalized()
        e1 = (p2 - p1).normalized()
        n0 = Vector((e0.y, -e0.x))
        n1 = Vector((e1.y, -e1.x))
        m = (n0 + n1)
        if m.length < 1e-6:
            m = n1
        m.normalize()
        k = d / max(0.35, m.dot(n1))
        q = p1 + m * k
        out.append((q.x, q.y))
    return out


def star_pts(n=5, r_out=1.0, r_in=0.5, cx=0.0, cz=0.0, phase=math.pi / 2, round_=0):
    pts = []
    for k in range(2 * n):
        r = r_out if k % 2 == 0 else r_in
        a = phase + k * math.pi / n
        pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def circle_pts(r, n=16, cx=0.0, cz=0.0, a0=0.0):
    return [(cx + r * math.cos(a0 + k * math.tau / n), cz + r * math.sin(a0 + k * math.tau / n)) for k in range(n)]


def blade(top, shaft_r=0.13, depth=0.2, tooth=1.0):
    """The key's lower half: a round shaft from the tip (z=0) up to `top` and a two-tooth bit to +X. Returns parts."""
    t = top
    out = [paint(lathe("Shaft", [(0, 0.0), (shaft_r * 0.75, 0.02), (shaft_r, 0.1), (shaft_r, t), (0, t)], GOLD, segs=12),
                 metal)]
    out.append(paint(rbox("Spine", (0.2, depth * 0.85, 0.5), (shaft_r + 0.02, 0, 0.3), bev=0.05), metal, False))
    out.append(paint(rbox("ToothLow", (0.4 * tooth, depth, 0.17), (shaft_r + 0.16 * tooth, 0, 0.13), bev=0.05), metal, False))
    out.append(paint(rbox("ToothHigh", (0.3 * tooth, depth, 0.15), (shaft_r + 0.11 * tooth, 0, 0.46), bev=0.05), metal, False))
    return out


def squash(o, s, about=(0, 0, 0)):
    """Scale an object's mesh about a point (bake it in; the builders keep identity matrices)."""
    a = Vector(about)
    for v in o.data.vertices:
        p = v.co - a
        v.co = a + Vector((p.x * s[0], p.y * s[1], p.z * s[2]))
    return o


def prof_r(prof, z):
    """Radius of a lathe profile [(r, z)] (z rising) at height z, linear in between."""
    for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
        if z0 <= z <= z1 and z1 > z0:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return 0.0
