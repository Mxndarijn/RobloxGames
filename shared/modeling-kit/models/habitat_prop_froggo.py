# habitat_prop_froggo: a lily pad with a cattail reed bending up out of it and a cartoon fly sitting on the tip.
import math
from lib import *
from models._habitat_prop2 import *

PAD, PAD_D = rgb(96, 192, 88), rgb(66, 150, 74)
REED = rgb(116, 190, 80)
CAT = rgb(158, 96, 58)
FLY = rgb(70, 76, 96)
EYE = rgb(240, 60, 60)
WING = rgb(214, 240, 255)

# lily pad: flat disc with a wedge notch toward the front-right
pad = []
import bmesh
bm = bmesh.new()
N = 16
gap = 0.5  # radians of the notch
top, bot = [], []
c0t = bm.verts.new((0, 0, 0.06))
c0b = bm.verts.new((0, 0, 0.0))
for k in range(N + 1):
    a = -math.pi / 3 + gap / 2 + (math.tau - gap) * k / N
    top.append(bm.verts.new((math.cos(a) * 0.55, math.sin(a) * 0.42, 0.06)))
    bot.append(bm.verts.new((math.cos(a) * 0.55, math.sin(a) * 0.42, 0.0)))
for k in range(N):
    bm.faces.new((c0t, top[k], top[k + 1]))
    bm.faces.new((c0b, bot[k + 1], bot[k]))
    bm.faces.new((bot[k], bot[k + 1], top[k + 1], top[k]))
bm.faces.new((c0b, bot[0], top[0], c0t))
bm.faces.new((c0t, top[N], bot[N], c0b))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
padobj = obj_from_bm("Pad", bm, PAD)
paint(padobj, lambda c, n: PAD if n.z > 0.5 else PAD_D)
parts = [padobj]
# reed: slightly curved stalk, two long leaves, brown cattail head
stalk = [(-0.1, 0.05, 0.04), (-0.1, 0.05, 0.36), (-0.06, 0.03, 0.66), (0.02, 0.0, 0.9)]
parts.append(tube("Stalk", stalk, [0.04, 0.035, 0.03, 0.028], REED, segs=6))
parts.append(lathe("Cattail", [(0.0, 0.0), (0.055, 0.02), (0.07, 0.08), (0.07, 0.2), (0.055, 0.25), (0.0, 0.27)], segs=8, col=CAT))
move(parts[-1], (0.02, 0.0, 0.88), (0, 12, 0))
# a second, shorter cattail leaning out to the right
parts.append(tube("Stalk2", [(0.12, 0.12, 0.04), (0.2, 0.1, 0.35), (0.3, 0.08, 0.56)], [0.03, 0.026, 0.022], REED, segs=5))
parts.append(lathe("Cattail2", [(0.0, 0.0), (0.045, 0.02), (0.055, 0.06), (0.055, 0.15), (0.04, 0.19), (0.0, 0.21)], segs=7, col=CAT))
move(parts[-1], (0.3, 0.08, 0.54), (0, 28, 0))

for s, h in ((-1, 0.62), (1, 0.48)):
    pts = [(-0.1, 0.05, 0.04), (-0.1 + s * 0.08, 0.04, h * 0.5), (-0.1 + s * 0.2, 0.02, h)]
    parts.append(tube(f"Leaf{s}", pts, [0.05, 0.04, 0.008], REED, segs=4))
# fly sitting on top of the cattail, facing front: round body, big red eyes, white wings angled up
FZ = 1.19
FC = (0.08, -0.02, FZ)
parts.append(blob("FlyBody", 0.105, FC, FLY, subdiv=2, squash=(0.9, 1.25, 0.85), jitter=0))
parts.append(blob("FlyHead", 0.075, (FC[0], FC[1] - 0.125, FZ + 0.02), FLY, subdiv=2, jitter=0))
for s in (-1, 1):
    parts.append(blob(f"FlyEye{s}", 0.052, (FC[0] + s * 0.058, FC[1] - 0.17, FZ + 0.045), EYE, subdiv=2, jitter=0))
    parts.append(blob(f"FlyGlint{s}", 0.014, (FC[0] + s * 0.058 - 0.014, FC[1] - 0.215, FZ + 0.07), WHITE, subdiv=1, jitter=0))
    w = blob(f"FlyWing{s}", 0.13, (0, 0, 0), WING, subdiv=2, squash=(0.55, 1.0, 0.12), jitter=0)
    parts.append(move(w, (FC[0] + s * 0.1, FC[1] + 0.07, FZ + 0.1), (0, s * 30, s * 18)))
ship("habitat_prop_froggo", parts)
