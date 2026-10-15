# phoenix_gate: plot entrance, 20 studs wide on the fence grid: 14 clear opening (x -7..7),
# 1.6 gate posts, 1.4-stud wall stubs to x=+-10 (8 tall). Arch beam underside 11, sign board
# front face at y=-0.8 (blank cream panel, game puts the owner name on it).
from lib import *
from models._phoenix_ranch import *
H = GATE_CLEAR / 2
PW = 1.8
PX = H + PW / 2
TOP = 11.6  # r02: post knobs poked through the roof at 13
parts = []
for i, s in enumerate((-1, 1)):
    parts.append(bbox(f"GFoot{i}", (PW + 0.7, PW + 0.7, 0.7), (s * (PX + 0.35), 0, 0.35), shade(WOOD_D, 0.88), WOOD_D, bev=0.15))
    parts += rpost(f"G{i}", s * PX, 0, TOP, w=PW)
    parts += board_wall(f"S{i}", *sorted((s * (PX + PW / 2), s * 10.0)), WALL_H - 0.3, seed=10 + i)
    parts.append(strut_box := bbox(f"Knee{i}", (2.6, 0.6, 0.6), (s * (H - 0.9), 0, 10.3), shade(WOOD_D, 0.9), WOOD_D,
                                    bev=0.08, rot=(0, s * 40, 0)))
parts.append(bbox("Beam", (2 * PX + 2.6, 1.2, 1.0), (0, 0, 11.5), shade(WOOD, 0.85), WOOD, bev=0.15))
roof = prism_x = None
# little red roof over the sign
bm_pts = [(-1.3, 12.0), (1.3, 12.0), (0.0, 13.4)]
import bmesh
def prism(name, prof, x0, x1, col):
    bm = bmesh.new(); a = [bm.verts.new((x0, y, z)) for y, z in prof]; b = [bm.verts.new((x1, y, z)) for y, z in prof]
    bm.faces.new(a); bm.faces.new(list(reversed(b)))
    for k in range(3):
        j = (k + 1) % 3; bm.faces.new((a[k], b[k], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces); return obj_from_bm(name, bm, col)
r = prism("Roof", bm_pts, -PX - 1.6, PX + 1.6, ROOF); gradient(r, ROOF_D, ROOF); parts.append(r)
parts.append(bbox("Sign", (9.0, 0.5, 2.4), (0, -0.85, 13.1 - 2.6), shade(CREAM, 0.9), CREAM, bev=0.15))
parts.append(bbox("SignRim", (9.6, 0.4, 2.9), (0, -0.6, 10.5), shade(WOOD_D, 0.9), WOOD_D, bev=0.1))
# goo drip blobs on the beam front (indented look: sunk into the beam)
for k, x in enumerate((-5.6, -4.9, 5.2, 6.0)):
    parts.append(blob(f"Goo{k}", 0.45 + 0.1 * (k % 2), (x, -0.55, 11.05 - 0.15 * (k % 2)), GOO, subdiv=2, squash=(1, 0.6, 1.3), jitter=0.05, seed=k))
finish("phoenix_gate", parts)
