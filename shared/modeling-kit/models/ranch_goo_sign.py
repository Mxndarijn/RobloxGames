# ranch_goo_sign: Slime Ranch plaza notice sign. Two chunky wood posts carry a wide barn-red
# (ranch_roof) board in a darker ranch_roof_dark frame; metaball goo oozes along the top edge and
# runs down the face in drips of mixed length, with a small goo puddle at the foot. Distinct from
# ranch_plaza_signpost (one post, arrow boards). Face is -Y, blank for a SurfaceGui.
# Face: 7.4 x 2.9 at centre z ZC, 0.2 proud of the frame front.
import math
from mathutils import Vector
from lib import *
from models._phoenix_ranch import *

ROOF_LO = mix(ROOF_D, ROOF, 0.65)
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
PW, PH = 1.0, 7.6            # post width / height
PX = 3.5                     # posts at x = +-PX
ZC = 5.2                     # board centre height
FW, FH, FD = 8.4, 3.7, 0.45  # frame
BW, BH, BD = 7.4, 2.9, 0.4   # face board
YF = -(PW / 2 + FD / 2)      # frame centre y (in front of the posts)
Y_FRAME = YF - FD / 2        # frame front
Y_FACE = Y_FRAME - 0.2       # face front (0.2 proud)
parts = []

for s in (-1, 1):
    x = s * PX
    parts.append(bbox(f"Post{s}", (PW, PW, PH), (x, 0, PH / 2), WOOD_LO, WOOD, bev=0.14))
    parts.append(blob(f"Knob{s}", 0.55, (x, 0, PH + 0.15), WOOD, subdiv=2, squash=(1, 1, 0.7), jitter=0))
    parts.append(bbox(f"Foot{s}", (1.8, 2.2, 0.5), (x, -0.1, 0.25), shade(WOOD_D, 0.9), WOOD_D, bev=0.12))
parts.append(bbox("Frame", (FW, FD, FH), (0, YF, ZC), shade(ROOF_D, 0.93), ROOF_D, bev=0.12))
parts.append(bbox("Face", (BW, BD, BH), (0, Y_FRAME - 0.2 + BD / 2, ZC), ROOF_LO, ROOF, bev=0.08))
# back battens so the back reads as wood boards, not a flat red slab
parts.append(bbox("BackRail", (FW - 0.4, 0.3, 0.6), (0, YF + FD / 2 + 0.1, ZC + 0.9), WOOD_LO, WOOD, bev=0.08))
parts.append(bbox("BackRail2", (FW - 0.4, 0.3, 0.6), (0, YF + FD / 2 + 0.1, ZC - 0.9), WOOD_LO, WOOD, bev=0.08))

# goo: a soft ridge along the top edge + drips running down the face
ZT = ZC + FH / 2
balls = []
for i in range(21):
    x = -FW / 2 + 0.35 + i * (FW - 0.7) / 20
    h = 0.24 + 0.05 * math.sin(i * 1.3)
    balls.append(Ball((x, YF - 0.05, ZT + 0.02), (0.55, FD / 2 + 0.22, h)))
DOWN, LAT, N = Vector((0, 0, -1)), Vector((1, 0, 0)), Vector((0, -1, 0))
Q = frame_quat(DOWN, LAT, N)
# (x, length below top, width)
for x, ln, w in [(-3.2, 1.1, 0.3), (-1.9, 2.3, 0.36), (-0.4, 0.8, 0.28), (1.0, 1.8, 0.34), (2.3, 1.0, 0.28)]:
    steps = max(3, int(ln / 0.18))
    for j in range(steps + 1):
        z = ZT - ln * j / steps
        y = (Y_FRAME if z > ZC + BH / 2 else Y_FACE)
        balls.append(Ball((x, y, z), (0.3, w * (1.0 - 0.3 * j / steps), 0.13), rot=Q))
    balls.append(Ball((x, Y_FACE - 0.04, ZT - ln), w * 0.85))
# one long run off the right end: down the face, then the right post front, into the puddle
ZB = ZC - FH / 2
for z in [ZT - k * 0.18 for k in range(int((ZT - 0.1) / 0.18) + 1)]:
    y = Y_FACE if z > ZC - BH / 2 else (Y_FRAME if z > ZB else -PW / 2)
    xx = 3.35 if z > ZB else PX + 0.05
    balls.append(Ball((xx, y, z), (0.3, 0.3, 0.13), rot=Q))
balls.append(Ball((3.35, Y_FRAME - 0.05, ZB + 0.05), 0.32))   # bead where it leaves the frame
goo = metaball_mesh("GooTop", balls, resolution=0.16, tris=760)
parts.append(paint_goo(goo, lambda co, n: mix(GOO, GOO_HI, min(0.5, 0.35 * max(0.0, n.z) ** 6))))

# small puddle at the foot of the right post, -Y side
pb = [Ball((2.7, -1.9, 0), (1.3, 0.9, 0.22)), Ball((3.5, -1.0, 0), (0.7, 0.6, 0.2)), Ball((1.7, -2.4, 0), (0.4, 0.35, 0.12))]
puddle = metaball_mesh("GooPuddle", pb, resolution=0.16, tris=220, clamp_z=0.02)
parts.append(paint_goo(puddle, lambda co, n: mix(GOO, GOO_HI, 0.12 * max(0.0, n.z) ** 4)))

finish("ranch_goo_sign", parts)
