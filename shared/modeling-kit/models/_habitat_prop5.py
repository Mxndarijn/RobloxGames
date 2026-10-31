# Signature-prop helpers, batch 5 (not an asset): small extruded shapes and gradient primitives for the
# habitat_prop_<species> scripts (cosmo ... glitch). Contract and ship() live in _habitat_prop.py.
import math
import bmesh
from mathutils import Matrix, Vector
from lib import *
from lib.shapes import obj_from_bm
from models._habitat_prop import *
from models._habitat import lathe, P


def gbox(name, size, pos, lo, hi=None, bev=0.04, rot=(0, 0, 0)):
    """Box with a small bevel and a lo -> hi vertical gradient."""
    o = box(name, size, pos, hi or lo, rot=rot)
    if bev:
        bevel(o, bev)
    if hi is not None:
        gradient(o, lo, hi)
    return o


def gcyl(name, r, h, pos, lo, hi=None, segs=10, r_top=None, rot=(0, 0, 0)):
    o = cylinder(name, r, h, pos, hi or lo, segs=segs, r_top=r_top, rot=rot)
    if hi is not None:
        gradient(o, lo, hi)
    return o


def slab(name, pts, thick, color, pos=(0, 0, 0), rot_z=0.0, plane="xz", hi=None):
    """Flat shape from a 2D outline (any simple polygon, concave ok), extruded `thick` and centred on its
    thickness. plane "xz": outline in (x, z), faces -Y (signs, banners); "xy": lying flat, thickness up."""
    bm = bmesh.new()
    vs = []
    for u, v in pts:
        vs.append(bm.verts.new((u, -thick / 2, v) if plane == "xz" else (u, v, 0)))
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, thick, 0)) if plane == "xz" else Vector((0, 0, thick)), verts=nv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[g for g in bm.faces if len(g.verts) > 4])
    if rot_z:
        bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(math.radians(rot_z), 3, "Z"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(pos), verts=bm.verts)
    o = obj_from_bm(name, bm, color)
    if hi is not None:
        gradient(o, color, hi)
    return o


def star_pts(n=5, r_out=1.0, r_in=0.45, cx=0.0, cz=0.0, phase=math.pi / 2):
    return [(cx + (r_out if k % 2 == 0 else r_in) * math.cos(phase + k * math.pi / n),
             cz + (r_out if k % 2 == 0 else r_in) * math.sin(phase + k * math.pi / n)) for k in range(2 * n)]


def circle_pts(r, n=16, cx=0.0, cz=0.0, a0=0.0, a1=math.tau):
    full = abs(a1 - a0 - math.tau) < 1e-6
    m = n if full else n + 1
    return [(cx + r * math.cos(a0 + (a1 - a0) * k / n), cz + r * math.sin(a0 + (a1 - a0) * k / n)) for k in range(m)]


def ring_xz(name, r_in, r_out, thick, color, pos=(0, 0, 0), segs=24, hi=None):
    """Flat annulus standing up, facing -Y (closed, manifold)."""
    bm = bmesh.new()
    rings = []
    for y in (-thick / 2, thick / 2):
        for r in (r_in, r_out):
            rings.append([bm.verts.new((r * math.cos(k * math.tau / segs), y, r * math.sin(k * math.tau / segs))) for k in range(segs)])
    fi, fo, bi, bo = rings
    for k in range(segs):
        k1 = (k + 1) % segs
        bm.faces.new((fi[k], fo[k], fo[k1], fi[k1]))
        bm.faces.new((bi[k], bi[k1], bo[k1], bo[k]))
        bm.faces.new((fo[k], bo[k], bo[k1], fo[k1]))
        bm.faces.new((fi[k], fi[k1], bi[k1], bi[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.translate(bm, vec=Vector(pos), verts=bm.verts)
    o = obj_from_bm(name, bm, color)
    if hi is not None:
        gradient(o, color, hi)
    return o


def rod(name, a, b, r, color, segs=6):
    """Straight round rod from point a to point b."""
    return tube(name, [a, b], [r, r], color, segs=segs)


def crescent_pts(R, r, off, n=12, cx=0.0, cz=0.0, rot=0.0):
    """Crescent outline: outer circle R at the centre minus inner circle r shifted `off` up (horns point up).
    rot (radians) turns the whole crescent about its centre."""
    zi = (R * R - r * r + off * off) / (2 * off)
    xi = math.sqrt(max(R * R - zi * zi, 0.0))
    ao0, ao1 = math.atan2(zi, xi), math.atan2(zi, -xi)            # outer arc: right horn -> round bottom -> left horn
    outer = [(R * math.cos(ao0 - (ao0 - (ao1 - math.tau)) * k / n), R * math.sin(ao0 - (ao0 - (ao1 - math.tau)) * k / n)) for k in range(n + 1)]
    a_s, a_e = math.atan2(zi - off, -xi), math.atan2(zi - off, xi)
    # walk the inner circle the short way through its bottom (angles near -pi/2)
    if a_s > 0:
        a_s -= math.tau
    if a_e > 0:
        a_e -= math.tau
    if a_e < a_s:
        a_e += math.tau
    inner = [(r * math.cos(a_s + (a_e - a_s) * k / n), off + r * math.sin(a_s + (a_e - a_s) * k / n)) for k in range(1, n)]
    pts = outer + inner
    c, s = math.cos(rot), math.sin(rot)
    return [(cx + u * c - v * s, cz + u * s + v * c) for u, v in pts]


def bolt_pts(h=1.0, w=0.6, cx=0.0, cz=0.0):
    """Lightning bolt outline, h tall, centred."""
    raw = [(0.15, 0.5), (-0.35, -0.05), (-0.02, -0.05), (-0.15, -0.5), (0.35, 0.08), (0.03, 0.08)]
    return [(cx + u * w / 0.7, cz + v * h) for u, v in raw]
