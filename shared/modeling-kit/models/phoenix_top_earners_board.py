# phoenix_top_earners_board: two-sided Slime Ranch "Top Earners" board for the plaza edge.
# Old WorldLayout board: 14 x 16 panel, top at y 19. New: 2 chunky posts, wood frame, IDENTICAL
# blank cream face panels on both sides (front -Y and back +Y) for SurfaceGui title + 10 rows,
# red barn-roof cap, goo puddle feet. Face panels: 13 wide x 11.6 tall, centre z 11.4, faces y=+-0.75.
import bmesh
from lib import *
from models._phoenix_ranch import *
PW, PX = 1.8, 8.4          # post width, post centre x
FW, FH, FZ = 13.0, 11.6, 11.4   # face panel w/h/centre z
TOP = FZ + FH / 2          # 17.2 panel top
parts = []
for i, s in enumerate((-1, 1)):
    parts.append(bbox(f"Foot{i}", (PW + 1.0, PW + 1.4, 0.8), (s * PX, 0, 0.4), shade(WOOD_D, 0.88), WOOD_D, bev=0.18))
    parts += rpost(f"P{i}", s * PX, 0, TOP + 0.6, w=PW)
    # knee braces under the board, both sides of the post
    parts.append(bbox(f"Knee{i}", (2.4, 0.6, 0.6), (s * (PX - 1.5), 0, FZ - FH / 2 - 0.9), shade(WOOD_D, 0.9), WOOD_D,
                      bev=0.08, rot=(0, -s * 40, 0)))
    # goo puddle at each foot (flat, sits on ground)
    parts.append(blob(f"Goo{i}", 1.5, (s * (PX + 0.6 * s), -0.9, 0.05), GOO, subdiv=2, squash=(1.3, 1.0, 0.12), jitter=0.03, seed=i))
# wood back-board core (thinner than faces so faces never z-fight)
parts.append(bbox("Core", (FW + 1.2, 1.0, FH + 1.2), (0, 0, FZ), shade(WOOD, 0.85), WOOD, bev=0.12))
# cream face panels, identical both sides
for j, y in enumerate((-0.6, 0.6)):
    parts.append(bbox(f"Face{j}", (FW, 0.3, FH), (0, y, FZ), shade(CREAM, 0.94), CREAM, bev=0.06))
# bottom frame rail, both sides. No title divider: the SurfaceGui draws its own title banner,
# and a mesh strip showed through the GUI across the first row.
for j, y in enumerate((-0.75, 0.75)):
    parts.append(bbox(f"RailB{j}", (FW + 1.4, 0.5, 0.7), (0, y, FZ - FH / 2 - 0.2), shade(WOOD_D, 0.9), WOOD_D, bev=0.12))
# red barn roof cap over the board
def prism(name, prof, x0, x1, col):
    bm = bmesh.new(); a = [bm.verts.new((x0, y, z)) for y, z in prof]; b = [bm.verts.new((x1, y, z)) for y, z in prof]
    bm.faces.new(a); bm.faces.new(list(reversed(b)))
    for k in range(3):
        j = (k + 1) % 3; bm.faces.new((a[k], b[k], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces); return obj_from_bm(name, bm, col)
r = prism("Roof", [(-1.7, TOP + 0.9), (1.7, TOP + 0.9), (0.0, TOP + 2.6)], -PX - 1.8, PX + 1.8, ROOF)
gradient(r, mix(ROOF_D, ROOF, 0.5), ROOF); parts.append(r)
parts.append(bbox("Eave", (2 * PX + 3.4, 2.2, 0.5), (0, 0, TOP + 0.75), shade(CREAM, 0.88), CREAM, bev=0.12))
parts.append(bbox("TopRail", (FW + 1.4, 1.4, 0.5), (0, 0, TOP + 0.3), shade(WOOD_D, 0.9), WOOD_D, bev=0.1))
# small goo drips sunk into the eave, both sides
for k, (x, y) in enumerate(((-6.2, -1.0), (5.4, -1.0), (-4.8, 1.0), (6.6, 1.0))):
    parts.append(blob(f"Drip{k}", 0.4, (x, y, TOP + 0.5), GOO, subdiv=2, squash=(1, 0.6, 1.3), jitter=0.04, seed=k + 5))
finish("phoenix_top_earners_board", parts)
