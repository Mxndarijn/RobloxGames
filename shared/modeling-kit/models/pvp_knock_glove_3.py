# pvp_knock_glove_3 "Boom Glove" (Knockback line, rank 3): orange mitt with a row of brass studs across the knuckles,
# a bomb fuse sprouting from the back of the hand with a butter/red spark, red cuff with butter stripes.
# Held tool, built upright like ranch_bat: see models/_pvp_glove.py for axes, grip and the shared builders.
from models._pvp_glove import *

S, FIST = 1.10, 1.06
OR_LO, OR, OR_HI = rgb(232, 108, 40), rgb(250, 142, 48), rgb(255, 192, 92)
RED, RED_LO, HOLE = rgb(212, 62, 50), rgb(180, 52, 46), rgb(140, 58, 44)
BUTTER, BUTTER_HI = rgb(252, 214, 96), rgb(255, 240, 160)
BRASS_LO, BRASS_HI = rgb(150, 150, 158), rgb(222, 224, 230)  # steel studs: lighter ones read as white teeth
ROPE_LO, ROPE_HI = rgb(158, 108, 68), rgb(196, 138, 86)  # wood-brown rope: tan vanished against the orange
COLLAR = rgb(150, 140, 136)
SPARK_CORE = rgb(255, 120, 48)  # orange-red: a full RED core went brown on the roblox-look shadow side

parts = mitt("Mitt", mitt_colour(OR_LO, OR, OR_HI, S), S=S, fist=FIST)
body = parts[0]

pal = {"hole": HOLE, "lip": BUTTER, "band_lo": RED, "band": BUTTER, "band_hi": RED, "top": RED_LO}
parts.append(cuff("Cuff", lambda row, k: pal[row], S=S, segs=14))

# brass studs across the knuckle roll (rays from the front, -Y)
STUD = [(0.00, -0.06), (0.17, -0.06), (0.17, 0.03), (0.09, 0.15), (0.00, 0.24)]  # short rounded cone studs
for i, x in enumerate((-0.40, -0.135, 0.135, 0.40)):
    z = 1.50 - 0.05 * abs(x) / 0.38
    p, q, n = on_surface(body, (x * S, -3, z * S), (0, 1, 0), sink=0.01)
    parts.append(lathe("Stud%d" % i, [(r * S, h * S) for r, h in STUD],
                       lambda row, k, zz: mix(BRASS_LO, BRASS_HI, min(1.0, row / 3)), segs=8, pos=p, rot=q))

# fuse: collar, a rope that curls toward the fist end, a spark at its tip
# fuse on the back of the hand, pinky side, low: it points out of the back (up when the glove is held fist-forward,
# back of the hand up) and curls toward the fist; the sheet's front view sees it in profile from the side
aim = Vector((0.42, -0.30, 1.08)) * S
top, qt, nt = on_surface(body, aim + Vector((0.6, -1, 0.2)) * 3, (-0.6, 1, -0.2), sink=0.03)
parts.append(lathe("Collar", [(0, 0), (0.17 * S, 0), (0.17 * S, 0.12 * S), (0.12 * S, 0.16 * S), (0, 0.16 * S)],
                   lambda row, k, z: shade(COLLAR, 0.9 + 0.1 * row), segs=10, pos=top, rot=qt))
up, side = Vector((0, 0, 1)), (nt + Vector((0.5, 0, 0))).normalized()
fuse_pts = [top + (side * d + up * (d * d * 1.5)) * S for d in (0.10, 0.22, 0.34, 0.46, 0.56)]  # out of the back, curling to the fist
parts.append(sweep("Fuse", fuse_pts, 0.065 * S, lambda t: mix(ROPE_LO, ROPE_HI, t), segs=6))
tip = fuse_pts[-1]
for j, w in enumerate(((0, -1, 0), (1, 0, 0))):  # two crossed stars read from front and side
    outer = slab("Spark%d" % j, star_pts(0.27 * S, 0.11 * S, 6), 0.06 * S, lambda c, nn: BUTTER_HI if nn.z > 0.3 else BUTTER, frame_at(tip, w), bevel_w=0.0)
    inner = slab("SparkCore%d" % j, star_pts(0.11 * S, 0.06 * S, 6, phase=0.0), 0.10 * S, lambda c, nn: SPARK_CORE, frame_at(tip, w), bevel_w=0.0)
    parts += [outer, inner]
parts.append(sphere_core := blob("SparkBall", 0.09 * S, pos=tip, color=BUTTER_HI, subdiv=1, jitter=0.0))
for f in sphere_core.data.polygons:
    f.use_smooth = False

ship("pvp_knock_glove_3", parts, grip=(0, 0, GRIP_Z * S))
