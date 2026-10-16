# Habitat look helpers (not an asset). Habitat meshes swap into the pad slot (HABITATS.md "Mesh slots"):
# footprint 7.8 x 7.8, origin bottom-centre (finish()), slime seat = flat top at SEAT studs above the bottom.
import math
from mathutils import Matrix, Vector
from lib import *
from models._phoenix_pad import *

SEAT = 2.4


def fit(o, w, h, d, seat=SEAT):
    """After finish(): stretch X/Y about the bbox centre to exactly w x d, and stretch only the verts
    above the seat so the top lands on h (the seat plane and everything under it stay put)."""
    vs = o.data.vertices
    xs, ys, zs = [v.co.x for v in vs], [v.co.y for v in vs], [v.co.z for v in vs]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    sx, sy = w / (max(xs) - min(xs)), d / (max(ys) - min(ys))
    z0, sz = min(zs), (h - seat) / (max(zs) - min(zs) - seat)
    for v in vs:
        z = v.co.z - z0
        v.co = Vector(((v.co.x - cx) * sx, (v.co.y - cy) * sy, seat + (z - seat) * sz if z > seat else z))
    o.data.update()
    origin_bottom_center(o)
    report(o, w, h, d, seat)
    return o


def report(o, w, h, d, seat):
    """Print FIT (bbox) and SEAT (flat up-facing area at the seat height round the centre)."""
    vs = o.data.vertices
    ext = [max(v.co[i] for v in vs) - min(v.co[i] for v in vs) for i in range(3)]
    flat = [p for p in o.data.polygons if p.normal.z > 0.999 and abs(p.center.z - seat) < 1e-4]
    rad = max((Vector((vs[i].co.x, vs[i].co.y)).length for p in flat for i in p.vertices), default=0)
    above = [v for v in vs if v.co.z > seat + 1e-4 and Vector((v.co.x, v.co.y)).length < 1.6]
    print(f"FIT {ext[0]:.3f} x {ext[2]:.3f} x {ext[1]:.3f} (want {w} x {h} x {d})")
    print(f"SEAT z={seat} flat_faces={len(flat)} radius={rad:.2f} verts_above_r1.6={len(above)}")


def frame_obj(o, m):
    """Bake matrix m into a part built at the origin."""
    o.data.transform(m)
    o.data.update()
    return o


def prism_crystal(name, r, length, sides=6, tip=0.35, lo=None, hi=None, face_k=(1.0, 0.86, 0.94, 1.08, 0.9, 1.0)):
    """Closed hexagonal crystal standing on the origin along +Z: prism + pointed tip (tip = tip length / length).
    Per-face colour: side faces get a facet shade (face_k) on a lo->hi gradient; tip facets lightest."""
    import bmesh
    from lib.shapes import obj_from_bm
    bm = bmesh.new()
    zb, zt = -0.3, length * (1 - tip)
    ring = lambda z, s: [bm.verts.new((r * s * math.cos(k * math.tau / sides), r * s * math.sin(k * math.tau / sides), z)) for k in range(sides)]
    a, b = ring(zb, 0.85), ring(zt, 1.0)
    apex = bm.verts.new((0, 0, length))
    col = bm.loops.layers.color.new("Col")
    def paint(f, c):
        for lp in f.loops:
            lp[col] = c
    paint(bm.faces.new(list(reversed(a))), lo)
    for k in range(sides):
        k1 = (k + 1) % sides
        paint(bm.faces.new((a[k], a[k1], b[k1], b[k])), shade(mix(lo, hi, 0.45), face_k[k % len(face_k)]))
        paint(bm.faces.new((b[k], b[k1], apex)), shade(hi, face_k[k % len(face_k)] * 1.04))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def place(o, pos, tilt_deg, toward_deg, spin_deg=0.0):
    """Lean a +Z-standing part by tilt_deg toward the horizontal direction toward_deg, then move it to pos."""
    m = (Matrix.Translation(Vector(pos)) @ Matrix.Rotation(math.radians(toward_deg), 4, "Z")
         @ Matrix.Rotation(math.radians(tilt_deg), 4, "Y") @ Matrix.Rotation(math.radians(spin_deg), 4, "Z"))
    return frame_obj(o, m)


def seat_disc(name, r, col, edge=None, z0=1.9, segs=14):
    """Flat round seat: top face exactly at SEAT, slightly bevelled rim. col = top colour, edge = rim colour."""
    edge = edge or shade(col, 0.8)
    return lathe(name, [(0, z0), (r, z0), (r + 0.05, SEAT - 0.18), (r - 0.12, SEAT), (0, SEAT)], segs=segs,
                 color_fn=lambda i, k, z: col if i >= 3 else edge)
