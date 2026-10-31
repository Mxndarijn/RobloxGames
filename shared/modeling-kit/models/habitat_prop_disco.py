# habitat_prop_disco: a speaker stack (big two-woofer box, smaller box on top) crowned by a little disco ball.
import math, random
import bmesh
from models._habitat_prop5 import *
from lib.shapes import obj_from_bm

BOX, BOX_HI = rgb(100, 84, 150), rgb(146, 126, 200)
CONE, CONE_IN = rgb(40, 36, 60), rgb(120, 110, 160)
PINK, CYAN = rgb(255, 80, 200), rgb(70, 230, 255)
parts = [
    gbox("Low", (1.2, 0.6, 0.52), (0, 0.06, 0.26), BOX, BOX_HI, bev=0.05),
    gbox("High", (0.8, 0.5, 0.38), (0, 0.08, 0.52 + 0.19), BOX, BOX_HI, bev=0.05),
]


def woofer(name, x, z, r, y):
    return [ring_xz(name + "Rim", r * 0.82, r, 0.05, PINK if r > 0.15 else CYAN, (x, y, z), segs=16),
            slab(name + "Cone", circle_pts(r * 0.84, 14, cx=x, cz=z), 0.03, CONE, (0, y + 0.01, 0)),
            slab(name + "Cap", circle_pts(r * 0.3, 8, cx=x, cz=z), 0.05, CONE_IN, (0, y - 0.01, 0))]


parts += woofer("WL", -0.3, 0.26, 0.2, -0.25) + woofer("WR", 0.3, 0.26, 0.2, -0.25)
parts += woofer("WT", -0.15, 0.71, 0.13, -0.18) + woofer("Tw", 0.22, 0.71, 0.08, -0.18)
# disco ball: faceted sphere, each face a random light grey/blue/pink tile
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.18)
col = bm.loops.layers.color.new("Col")
R = random.Random(5)
TILES = [rgb(240, 244, 255), rgb(200, 206, 226), rgb(170, 220, 255), rgb(255, 190, 240), rgb(255, 255, 255)]
for f in bm.faces:
    c = TILES[R.randrange(len(TILES))]
    for lp in f.loops:
        lp[col] = c
ball = obj_from_bm("Ball", bm)
parts.append(xf(ball, (0, 0.08, 0.9 + 0.2)))
parts.append(gcyl("BallCup", 0.07, 0.04, (0, 0.08, 0.9), CYAN, segs=8))
ship("habitat_prop_disco", parts)
