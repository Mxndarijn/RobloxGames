# obby_finish_c (option C): a party FINISH GATE with big CROSSED CHEQUERED FLAGS (steal-a-slime obby).
# Two tall candy-striped gate posts stand just outside the lane at the front of the finish slab, bunting strung
# between their tops (lowest pennant 12.5 studs up) and a bunch of balloons tied to each post. At the back in the
# middle, two big waving chequered flags cross on a gold stand: the racing "finish" sign everyone knows.
# Slab coordinates (models/_obby_finish_parts).
import math
from mathutils import Matrix, Vector
from lib import *
from models._obby_finish_parts import *

GY = -4.4  # gate plane, near the slab's front edge
GX = 12.8  # post centre x: outside the 24-stud lane
GH = 16.0  # post height
parts = []

# -- gate posts: a violet foot on the slab corner, a candy-striped post, a gold ball on top
for s in (-1, 1):
    parts.append(bb(f"GateFoot{s}", (2.0, 2.0, 0.7), (s * (GX - 0.1), GY, -0.1), VIOLET_LO, VIOLET, bev=0.18))
    parts.append(pole(f"Post{s}", (s * GX, GY, 0.2), GH, 0.5, WHITE, WHITE, stripes=8, c2=CYAN, segs=10))
    parts.append(ball(f"PostTop{s}", 0.85, (s * GX, GY, GH + 0.75), GOLD_LO, GOLD_HI))

# -- bunting across the gate: rope sags to 13.9, pennants 1.3 long, so the lowest tip is 12.6 up
COLS = [CYAN, GOLD, VIOLET, LIME, WHITE]
a, b = (-GX, GY, GH - 0.3), (GX, GY, GH - 0.3)
SAG = 1.8
parts.append(rope("GateRope", catenary(a, b, SAG, 18), 0.09, WHITE))
pts = catenary(a, b, SAG, 16)[1:-1]
for i, p in enumerate(pts):
    parts.append(pennant(f"Pen{i}", tuple(p), 1.45, 1.3, COLS[i % len(COLS)], depth=0.14))

# -- balloon bunches tied to each post (outside the lane), strings down to a bow on the post
for s in (-1, 1):
    tie = Vector((s * GX, GY, 6.0))
    bunch = [(1.9, 0.2, 10.9, CYAN), (3.6, -0.5, 9.5, GOLD), (2.6, 1.1, 8.4, VIOLET), (1.2, -0.8, 8.6, LIME),
             (4.0, 0.8, 11.6, VIOLET_HI)]
    for k, (dx, dy, z, c) in enumerate(bunch):
        cpos = Vector((s * (GX + dx), GY + dy, z))
        parts += balloon(f"Bal{s}_{k}", tuple(cpos), 1.3, c)
        bottom = cpos - Vector((0, 0, 1.3 * 1.12 + 0.36))
        mid = tie.lerp(bottom, 0.5) + Vector((s * 0.3, 0, 0))
        parts.append(tube(f"Str{s}_{k}", [tuple(bottom), tuple(mid), tuple(tie)], [0.04] * 3, WHITE, segs=4))
    parts.append(ball(f"Bow{s}", 0.32, tuple(tie), VIOLET_LO, VIOLET, subdiv=1))

# -- crossed chequered flags at the back in the middle, each pole on its own gold stand
FY = 4.6
PL, TILT = 19.5, 25.0
FW, FH = 10.0, 6.6
BX = 2.6  # the poles stand this far either side of the middle and cross ~5.5 studs up
for s in (-1, 1):
    ang = s * TILT
    base = Vector((-s * BX, FY + s * 0.3, 0.9))  # one pole a little behind the other so they cross, not merge
    parts.append(bb(f"StandBase{s}", (2.0, 2.0, 0.6), (base.x, base.y, 0.3), VIOLET_LO, VIOLET, bev=0.18))
    parts.append(lathe(f"Stand{s}", [(0, 0.6), (0.85, 0.6), (0.7, 0.95), (0.45, 1.2), (0, 1.25)],
                       [GOLD_LO, GOLD, GOLD, GOLD_HI], segs=12, pos=(base.x, base.y, 0)))
    up = Vector((math.sin(math.radians(ang)), 0, math.cos(math.radians(ang))))
    parts.append(pole(f"FlagPole{s}", tuple(base), PL, 0.32, rgb(220, 220, 232), WHITE, segs=8,
                      tilt=(0, ang, 0)))
    top = base + up * PL
    parts.append(ball(f"FlagTop{s}", 0.6, tuple(top + up * 0.4), GOLD_LO, GOLD_HI))
    # the flag's inner edge runs down the pole from just under the top; it flies outward (away from the middle)
    side = Vector((up.z, 0, -up.x)) * s  # perpendicular to the pole, pointing outward
    centre = top - up * (0.3 + FH / 2) + side * (FW / 2 + 0.25)
    parts.append(checker(f"Flag{s}", FW, FH, 5, 3, thick=0.18, sub=3,
                         wave=lambda u, v, s=s: 0.6 * math.sin((u if s > 0 else 1 - u) * math.pi * 1.6)
                         * (u if s > 0 else 1 - u) + 0.15 * math.sin(v * math.pi),
                         pos=tuple(centre), rot=(0, ang, 0)))

report("obby_finish_c", parts)
finish_smooth("obby_finish_c", parts)
