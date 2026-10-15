# ranch_plaza_signpost: Slime Ranch hub/plaza wayfinding post. Chunky wood post with a small
# barn-red roof cap, three arrow boards (cream / butter faces, wood or red frames) pointing
# different ways above head height, foot block and a goo puddle. Faces are blank for SurfaceGui.
# Front faces -Y. Boards: (yaw, centre z) = (0, 10.0), (150, 8.1), (-35, 6.2); face 6 x 1.9.
import math
import bmesh
from mathutils import Matrix
from lib import *
from models._phoenix_ranch import *

BUTTER_LO = mix(BUTTER, WOOD, 0.25)
CREAM_LO = mix(CREAM, WOOD, 0.25)
ROOF_LO = mix(ROOF_D, ROOF, 0.5)
PW, PH = 1.7, 12.0          # post width / height
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
parts = []


def arrow(name, L, H, T, tip, yaw, x0, z, lo, hi, bev=0.08):
    """Arrow-shaped slab: from x0 out to x0+L along the yaw direction, pointed end, thickness T."""
    bm = bmesh.new()
    prof = [(x0, -H / 2), (x0 + L - tip, -H / 2), (x0 + L, 0), (x0 + L - tip, H / 2), (x0, H / 2)]
    f = bm.faces.new([bm.verts.new((x, -T / 2, z + v)) for x, v in prof])
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, T, 0), verts=[e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(yaw), 3, "Z"), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, hi)
    if bev:
        bevel(o, bev)
    gradient(o, lo, hi)
    return o


# post, foot and goo puddle
parts.append(bbox("Post", (PW, PW, PH), (0, 0, PH / 2), WOOD_LO, WOOD, bev=0.18))   # r03: was WOOD_D, went near-black
parts.append(bbox("PostCap", (PW + 0.4, PW + 0.4, 0.4), (0, 0, PH + 0.2), CREAM_LO, CREAM, bev=0.12))
parts.append(bbox("Foot", (PW + 1.4, PW + 1.4, 0.8), (0, 0, 0.4), shade(WOOD_D, 0.88), WOOD_D, bev=0.18))
for k, rot in enumerate((0, 90)):   # cross feet
    parts.append(bbox(f"Brace{k}", (4.2, 0.7, 0.5), (0, 0, 0.25), shade(WOOD_D, 0.9), WOOD_D, bev=0.12, rot=(0, 0, rot)))
parts.append(blob("Goo", 1.4, (1.6, -1.4, 0.05), GOO, subdiv=2, squash=(1.3, 1.0, 0.12), jitter=0.03, seed=3))

# arrow boards: (yaw deg, centre z, face colour lo/hi, frame lo/hi)
BOARDS = [
    (0, 10.0, CREAM_LO, CREAM, ROOF_LO, ROOF),
    (150, 8.1, BUTTER_LO, BUTTER, shade(WOOD_D, 0.9), WOOD_D),
    (-35, 6.2, CREAM_LO, CREAM, shade(WOOD_D, 0.9), WOOD_D),
]
for i, (yaw, z, flo, fhi, rlo, rhi) in enumerate(BOARDS):
    parts.append(arrow(f"Frame{i}", 7.2, 2.5, 0.45, 1.45, yaw, -0.4, z, rlo, rhi))
    parts.append(arrow(f"Face{i}", 6.0, 1.9, 0.65, 1.1, yaw, 0.6, z, flo, fhi, bev=0.06))

# little barn roof cap over the post top
TOP = PH + 0.4
bm = bmesh.new()
prof = [(-1.5, TOP + 0.6), (1.5, TOP + 0.6), (0.0, TOP + 2.0)]
a = [bm.verts.new((-1.4, y, z)) for y, z in prof]
b = [bm.verts.new((1.4, y, z)) for y, z in prof]
bm.faces.new(a); bm.faces.new(list(reversed(b)))
for k in range(3):
    j = (k + 1) % 3
    bm.faces.new((a[k], b[k], b[j], a[j]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
roof = obj_from_bm("Roof", bm, ROOF)
gradient(roof, ROOF_LO, ROOF)
parts.append(roof)
parts.append(bbox("Eave", (3.0, 3.2, 0.4), (0, 0, TOP + 0.45), CREAM_LO, CREAM, bev=0.1))

finish("ranch_plaza_signpost", parts)
