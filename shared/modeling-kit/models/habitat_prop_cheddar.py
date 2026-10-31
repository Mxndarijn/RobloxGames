# habitat_prop_cheddar: a cartoon cheese wedge for the Cheddar slime: a triangular wedge seen from the front
# (tall rind side on the right, sloping down to the left), round holes on the faces and a little mouse-hole arch.
import math
import bmesh
from mathutils import Matrix, Vector
from lib import *
from lib.shapes import obj_from_bm
from models._habitat_prop import *

CHEESE, CHEESE_LO = rgb(255, 204, 64), rgb(240, 170, 40)
RIND = rgb(246, 156, 40)
HOLE = rgb(214, 132, 24)
ARCH = rgb(92, 56, 36)
W, D, H = 1.72, 0.86, 0.98
X0, X1 = -W / 2, W / 2

bm = bmesh.new()
col = bm.loops.layers.color.new("Col")
f_pts = [(X0, -D / 2, 0), (X1, -D / 2, 0), (X1, -D / 2, H)]
b_pts = [(x, D / 2, z) for x, _, z in f_pts]
fv = [bm.verts.new(p) for p in f_pts]
bv = [bm.verts.new(p) for p in b_pts]


def face(vs, c):
    f = bm.faces.new(vs)
    for lp in f.loops:
        lp[col] = c


face(fv, CHEESE)  # front triangle
face(list(reversed(bv)), CHEESE)  # back triangle
face([fv[0], bv[0], bv[1], fv[1]], CHEESE_LO)  # bottom
face([fv[1], bv[1], bv[2], fv[2]], RIND)  # right end: rind
face([fv[2], bv[2], bv[0], fv[0]], mix(CHEESE, CREAM, 0.15))  # sloped top
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
parts = [obj_from_bm("Wedge", bm)]


def hole(name, centre, normal, r, depth=0.012):
    """A flat darker disc just proud of a face (reads as a hole), turned to the face normal."""
    n = Vector(normal).normalized()
    d = cylinder(name, r, depth, (0, 0, 0), HOLE, segs=10)
    q = n.to_track_quat("Z", "Y")
    d.data.transform(q.to_matrix().to_4x4())
    d.data.transform(Matrix.Translation(Vector(centre)))
    return d


# front-face holes (normal -Y)
for n, (x, z, r) in enumerate([(0.42, 0.62, 0.13), (0.62, 0.30, 0.09), (0.05, 0.22, 0.08), (0.36, 0.30, 0.05)]):
    parts.append(hole(f"HoleF{n}", (x, -D / 2, z), (0, -1, 0), r))
# sloped-top holes
slope_n = Vector((-H, 0, W)).normalized()
for n, (t, y, r) in enumerate([(0.35, -0.12, 0.11), (0.65, 0.18, 0.09), (0.15, 0.2, 0.06), (0.8, -0.2, 0.06)]):
    x = X0 + t * W
    parts.append(hole(f"HoleT{n}", (x, y, t * H), slope_n, r))
# rind holes (normal +X)
parts.append(hole("HoleR0", (X1, 0.1, 0.55), (1, 0, 0), 0.1))

# mouse-hole arch at the bottom of the front face: dark half-disc on a rectangle
ax, aw, ah = -0.18, 0.26, 0.16
arch_pts = [(-aw / 2, 0), (aw / 2, 0)] + [(aw / 2 * math.cos(a), ah + aw / 2 * math.sin(a)) for a in
                                          [math.pi * j / 6 for j in range(7)]]
bm2 = bmesh.new()
c2 = bm2.loops.layers.color.new("Col")
ring = [(ax + px, -D / 2 - 0.004, pz) for px, pz in arch_pts]
fr = [bm2.verts.new(p) for p in ring]
bk = [bm2.verts.new((p[0], p[1] + 0.02, p[2])) for p in ring]
for f in [bm2.faces.new(fr), bm2.faces.new(list(reversed(bk)))] + [bm2.faces.new((fr[i], fr[(i + 1) % len(fr)], bk[(i + 1) % len(fr)], bk[i])) for i in range(len(fr))]:
    for lp in f.loops:
        lp[c2] = ARCH
bmesh.ops.recalc_face_normals(bm2, faces=bm2.faces)
parts.append(obj_from_bm("MouseHole", bm2))

ship("habitat_prop_cheddar", parts)
