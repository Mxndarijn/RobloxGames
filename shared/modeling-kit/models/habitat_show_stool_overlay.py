# habitat_show_stool_overlay: show-ring dressing for the crate pad: a royal blue velvet frame with gold piping and
# blue velvet bolsters on the rim band, gold stanchion posts on the four corners with crimson velvet ropes
# sagging between them (rope ends tucked into the post shafts), gold tassels under the ropes and a blue-and-gold prize rosette on the front-left post.
# Everything stays on the rim band (|x| or |y| > 2.6) and above the deck (no drop).
import math, os
from lib import *
from models._habitat_overlay import *
from models._phoenix_pad import lathe

BLUE, BLUE_D, BLUE_HI = rgb(84, 124, 218), rgb(76, 112, 204), rgb(122, 160, 240)
GOLD, GOLD_D = rgb(255, 214, 90), rgb(218, 160, 52)
ROPE, ROPE_D = rgb(226, 62, 78), rgb(198, 50, 66)
P = BAND + 0.02  # post / rope line (studs from the centre)
TOP_Z, SAG_Z = 1.55, 1.05  # rope height at the posts and at mid span

parts = [frame("Velvet", BLUE, BLUE_D, seed=1, wobble=0.0, segs=1)]
# gold piping on the frame's outer edge + a velvet bolster along each side between the posts
for side in range(4):
    a = side * math.pi / 2
    ox, oy = math.cos(a - math.pi / 2), math.sin(a - math.pi / 2)  # outward: -Y, +X, +Y, -X
    lx, ly = -oy, ox
    e = HALF - 0.08
    parts.append(tube(f"Pipe{side}", [(ox * e - lx * e, oy * e - ly * e, 0.16), (ox * e + lx * e, oy * e + ly * e, 0.16)],
                      [0.08, 0.08], GOLD, segs=5))
    b, L = 3.05, 2.55
    bol = tube(f"Bolster{side}", [(ox * b - lx * L, oy * b - ly * L, 0.32), (ox * b + lx * L, oy * b + ly * L, 0.32)],
               [0.27, 0.27], BLUE, segs=8)
    gradient(bol, BLUE_D, BLUE_HI)
    parts.append(bol)

# gold stanchion posts on the corners
POST = [(0, 0.1), (0.46, 0.1), (0.46, 0.2), (0.13, 0.42), (0.11, 1.45), (0.18, 1.52), (0.11, 1.62), (0, 1.62)]
for i, (s, t) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
    x, y = s * P, t * P
    parts.append(lathe(f"Post{i}", POST, segs=6, pos=(x, y, 0),
                       color_fn=lambda r, k, z: mix(GOLD_D, GOLD, min(1.0, 0.25 + z / 1.6)) if r < 4 else GOLD))
    parts.append(blob(f"Ball{i}", 0.25, (x, y, 1.82), GOLD, subdiv=2, jitter=0))

# crimson velvet ropes between the posts (catenary-ish sag), gold clasps at the ends
N = 7
for side in range(4):
    a = side * math.pi / 2
    ox, oy = math.cos(a - math.pi / 2), math.sin(a - math.pi / 2)
    lx, ly = -oy, ox
    pts = []
    for j in range(N):
        u = -1 + 2 * j / (N - 1)
        L = P - 0.22
        z = SAG_Z + (TOP_Z - SAG_Z) * u * u
        pts.append((ox * P + lx * L * u, oy * P + ly * L * u, z))
    rope = tube(f"Rope{side}", pts, [0.13] * N, ROPE, segs=6)
    gradient(rope, ROPE_D, ROPE)
    parts.append(rope)
    if True:  # gold tassel under the mid span of every rope
        tx, ty = ox * P, oy * P
        parts.append(blob(f"TasKnot{side}", 0.14, (tx, ty, SAG_Z - 0.16), GOLD, subdiv=1, jitter=0))
        parts.append(cylinder(f"Tas{side}", 0.16, 0.42, (tx, ty, SAG_Z - 0.62), GOLD_D, segs=6, r_top=0.06))

# prize rosette on the front-left post (front centre would hide the slime): blue ruffle, gold ring, blue centre with a gold button, two ribbon tails
rx, ry, rz = -HALF + 0.68, -P - 0.2, 1.1  # ruffle edge stays inside the frame (bbox centred)
ruff = lathe("Ruffle", [(0, 0), (0.62, 0), (0.66, 0.06), (0.62, 0.12), (0, 0.12)], segs=14,
             color_fn=lambda r, k, z: BLUE_HI if k % 2 else BLUE)
ruff.data.transform(__import__("mathutils").Matrix.Translation((rx, ry + 0.06, rz)) @ __import__("mathutils").Matrix.Rotation(math.radians(90), 4, "X"))
parts.append(ruff)
parts.append(cylinder("RosGold", 0.42, 0.08, (rx, ry, rz), GOLD, segs=12, rot=(90, 0, 0)))
parts.append(cylinder("RosBlue", 0.28, 0.08, (rx, ry - 0.06, rz), BLUE, segs=12, rot=(90, 0, 0)))
parts.append(blob("RosBtn", 0.14, (rx, ry - 0.14, rz), GOLD, subdiv=1, squash=(1, 0.6, 1), jitter=0))
for k, s in enumerate((-1, 1)):
    parts.append(box(f"Tail{k}", (0.24, 0.05, 0.62), (rx + s * 0.17, ry + 0.02, rz - 0.62), BLUE, rot=(0, s * 14, 0)))
    gradient(parts[-1], BLUE_D, BLUE)
if PREVIEW and os.environ.get("OV_SLIME") == "1":  # temporary 3-stud slime stand-in for a sight-line check
    parts.append(blob("SlimeStandIn", 1.5, (0, 0, 1.6), rgb(120, 220, 120), subdiv=2, jitter=0))
overlay_finish("habitat_show_stool_overlay", parts)
