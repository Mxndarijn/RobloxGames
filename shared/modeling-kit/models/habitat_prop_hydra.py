# habitat_prop_hydra: signature prop for Hydra: a broken Greek column (fluted marble shaft on a square plinth, the
# top snapped off jagged) on a sand patch, green seaweed curling round it, the fallen capital lying beside it.
# Front faces -Y.
import math
import bmesh
from lib import *
from models._habitat_prop4 import *

MARBLE, MARBLE_D, MARBLE_HI = rgb(244, 238, 226), rgb(222, 216, 212), rgb(255, 252, 244)
BREAK = rgb(226, 214, 200)
SAND, SAND_HI = rgb(236, 200, 134), rgb(255, 230, 172)
WEED, WEED_HI = rgb(96, 224, 112), rgb(176, 248, 130)


def tri(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(o.data)
    bm.free()
    return o


parts = []
sand = blob("Sand", 0.55, (0.05, 0.05, 0), SAND, subdiv=2, squash=(1.55, 1.0, 0.22), jitter=0.05, seed=11)
gradient(sand, shade(SAND, 0.92), SAND_HI)
parts.append(floor(sand))

CX, CY = -0.22, 0.05
plinth = box("Plinth", (0.6, 0.6, 0.14), (CX, CY, 0.07), MARBLE_D)
bevel(plinth, 0.02)
gradient(plinth, MARBLE_D, MARBLE)
parts.append(plinth)
parts.append(torus("Base", 0.24, 0.05, seg=16, seg2=5, pos=(CX, CY, 0.18), color=MARBLE))
# shaft with a jagged broken top
SH, SR = 0.88, 0.21
shaft = cylinder("Shaft", SR, SH, (CX, CY, 0.16), MARBLE, segs=16, r_top=SR * 0.92)
top = 0.16 + SH
for v in shaft.data.vertices:
    if v.co.z > top - 0.01:
        a = math.atan2(v.co.y - CY, v.co.x - CX)
        v.co.z = top - 0.22 * (0.5 + 0.5 * math.sin(a * 2 + 0.6)) - 0.07 * (0.5 + 0.5 * math.sin(a * 5))
tri(shaft)
paint(shaft, lambda c, n: BREAK if n.z > 0.5 else
      (MARBLE_HI if int((math.atan2(c.y - CY, c.x - CX) + math.pi) / math.tau * 16 + 0.5) % 2 == 0 else MARBLE_D))
parts.append(shaft)
# seaweed spiralling up the shaft
sp = []
for i in range(17):
    t = i / 16
    a = -math.pi / 2 - 0.6 + t * math.tau * 1.35
    sp.append((CX + math.cos(a) * (SR + 0.04), CY + math.sin(a) * (SR + 0.04), 0.2 + t * 0.78 + 0.03 * math.sin(t * 20)))
weed = ribbon("Weed", sp, [0.1 - 0.05 * i / 16 for i in range(17)], thick=0.035, color=WEED)
gradient(weed, WEED, WEED_HI)
parts.append(weed)
for k, (x, y, h, ph) in enumerate(((CX - 0.38, CY - 0.22, 0.55, 0.0), (CX + 0.32, CY + 0.25, 0.45, 1.5))):  # fronds
    pts = [(x + 0.06 * math.sin(ph + j * 1.3), y, 0.04 + h * j / 6) for j in range(7)]
    f = ribbon(f"Frond{k}", pts, [0.08 * (1 - j / 8) for j in range(7)], thick=0.03, up=(1, 0, 0), color=WEED)
    gradient(f, WEED, WEED_HI)
    parts.append(f)
# fallen capital on the sand, front right, tipped on its side
drum = cylinder("Drum", 0.18, 0.34, (0, 0, -0.17), MARBLE, segs=12)
paint(drum, lambda c, n: BREAK if abs(n.z) > 0.5 else (MARBLE_HI if int((math.atan2(c.y, c.x) + math.pi) / math.tau * 12 + 0.5) % 2 == 0 else MARBLE_D))
move(drum, (0.5, -0.2, 0.18), (0, 90, 30))
parts.append(drum)
for i, (x, y, r) in enumerate(((0.22, -0.4, 0.07), (0.78, 0.12, 0.06))):  # rubble
    parts.append(blob(f"Rub{i}", r, (x, y, 0.05), MARBLE_D, subdiv=1, jitter=0.15, seed=i))
prop_finish("habitat_prop_hydra", parts)
