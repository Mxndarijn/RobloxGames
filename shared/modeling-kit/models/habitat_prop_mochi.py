# habitat_prop_mochi: a little pink sleeping pillow for the Mochi slime: puffy cushion, a tufted button in the
# middle and a tassel on each corner.
import math
import bmesh
from lib import *
from lib.shapes import obj_from_bm
from models._habitat_prop import *

PINK = rgb(252, 150, 186)
PINK_LO, PINK_HI = rgb(236, 100, 152), rgb(255, 172, 208)  # r02: more saturated
GOLD = rgb(252, 204, 92)
W, D, H = 1.42, 0.84, 1.08  # pillow body (r02: taller, puffier)

bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=5, use_grid_fill=True)
for v in bm.verts:
    x, y, z = v.co.x * 2, v.co.y * 2, v.co.z * 2  # -1..1
    puff = (1 - x * x * 0.55) * (1 - y * y * 0.55)  # thick middle, thin seams at the edge
    corner = 1 - 0.18 * (x * x * y * y)  # pinch the corners in
    v.co.x = x * W / 2 * (1 - 0.06 * y * y)
    v.co.y = y * D / 2 * (1 - 0.06 * x * x)
    v.co.z = z * H / 2 * puff * corner * (1.0 if z > 0 else 0.14) + H / 2  # r03: near-flat bottom: it sits on the deck, seam low
    # dimple at the button
    v.co.z -= 0.07 * max(0.0, 1 - math.hypot(x, y) * 2.6) * (1 if z > 0 else 0)
# smooth the boxy look a bit
bmesh.ops.smooth_vert(bm, verts=bm.verts[:], factor=0.4, use_axis_x=True, use_axis_y=True, use_axis_z=True)
zmin = min(v.co.z for v in bm.verts)
for v in bm.verts:
    v.co.z -= zmin
pillow = obj_from_bm("Pillow", bm)
regrad(pillow, PINK_LO, PINK_HI)
parts = [pillow]
top = max(v.co.z for v in pillow.data.vertices)

# seam piping round the middle
pts = []
for j in range(25):
    a = math.tau * j / 24
    c, s = math.cos(a), math.sin(a)
    k = 1 / max(abs(c) / (W / 2), abs(s) / (D / 2)) * 0.985
    pts.append((c * k, s * k, H / 2 - zmin))
parts.append(tube("Piping", pts, [0.035] * 25, shade(PINK_LO, 0.95), segs=5))
# tufted button
parts.append(lathe("Button", [(0, top - 0.09), (0.08, top - 0.09), (0.09, top - 0.05), (0.05, top - 0.02), (0, top - 0.02)], segs=8,
                   color_fn=lambda i, k, z: GOLD))
# corner tassels: a knot bead and a little skirt cone
for sx in (-1, 1):
    for sy in (-1, 1):
        x, y = sx * (W / 2 + 0.0), sy * (D / 2 - 0.0)
        z = H / 2 - zmin
        # r02: the tassel hangs from the corner knot down onto the deck just outside the corner (was read as legs)
        parts.append(blob(f"Knot{sx}{sy}", 0.065, (x, y, z), GOLD, subdiv=1, jitter=0))
        # r03: the tassel lies on the deck, pointing out from the corner (standing tassels read as table legs)
        tas = lathe(f"Tassel{sx}{sy}", [(0, 0), (0.035, 0.01), (0.06, 0.09), (0.075, 0.17), (0, 0.17)], segs=6,
                    color_fn=lambda i, k, zz: shade(GOLD, 1.0 if i < 2 else 0.9))
        ang = math.degrees(math.atan2(sy * 0.3, sx * 1.0))
        parts.append(xf(tas, (x + sx * 0.02, y + sy * 0.01, 0.075), (0, 90, ang)))

ship("habitat_prop_mochi", parts)
