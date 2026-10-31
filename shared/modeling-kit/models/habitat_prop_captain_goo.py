# habitat_prop_captain_goo: signature prop for Captain Goo: a closed pirate treasure chest (wood, gold bands and
# lock, a few coins spilling out under the lid) with a small iron anchor leaning on its right side. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

WOOD, WOOD_D = rgb(186, 112, 64), rgb(140, 80, 48)
GOLD, GOLD_D = rgb(255, 200, 60), rgb(232, 150, 36)
IRON, IRON_D = rgb(120, 140, 170), rgb(88, 104, 132)

parts = []
W, D, H = 0.95, 0.62, 0.45      # chest body
cx = -0.3
body = box("Body", (W, D, H), (cx, 0, H / 2), WOOD)
bevel(body, 0.03)
paint(body, lambda c, n: WOOD if int((c.z + 0.001) / (H / 3)) % 2 == 0 else shade(WOOD, 0.88))
parts.append(body)
# domed lid: a half cylinder along X
lid = cylinder("Lid", D / 2, W, rot=(0, 90, 0), segs=12, color=WOOD)
move(lid, (cx - W / 2, 0, H + 0.02))
for v in lid.data.vertices:  # keep only the top half (squash the lower half flat onto the seam)
    v.co.z = max(v.co.z, H + 0.02)
    v.co.z = H + 0.02 + (v.co.z - H - 0.02) * 0.85
gradient(lid, shade(WOOD, 0.95), shade(WOOD, 1.12))
parts.append(lid)
# gold bands over body + lid, gold corner trim and lock
for k, x in enumerate((cx - W / 2 + 0.16, cx + W / 2 - 0.16)):
    parts.append(box(f"BandB{k}", (0.09, D + 0.04, H + 0.02), (x, 0, H / 2), GOLD_D))
    band = torus(f"BandL{k}", D / 2 * 0.95, 0.05, seg=12, seg2=4, rot=(0, 90, 0), color=GOLD, arc=(0, math.pi))
    move(band, (x, 0, H + 0.02), (0, 0, 0))
    for v in band.data.vertices:
        v.co.z = H + 0.02 + max(0, v.co.z - H - 0.02) * 0.85
    parts.append(band)
parts.append(box("Rim", (W + 0.04, D + 0.04, 0.07), (cx, 0, H), GOLD_D))
lock = box("Lock", (0.2, 0.08, 0.24), (cx, -D / 2 - 0.03, H - 0.02), GOLD)
bevel(lock, 0.03)
parts.append(lock)
parts.append(cylinder("Keyhole", 0.035, 0.03, (cx, -D / 2 - 0.08, H - 0.04), rgb(70, 50, 40), segs=6, rot=(90, 0, 0)))
# coins spilling: a few flat gold discs in front
for i, (x, y, z, rx) in enumerate([(cx - 0.32, -0.43, 0.02, 0), (cx - 0.15, -0.5, 0.02, 0), (cx - 0.25, -0.38, 0.06, 20),
                                   (cx + 0.3, -0.45, 0.02, 0)]):
    parts.append(cylinder(f"Coin{i}", 0.08, 0.035, (x, y, z), GOLD, segs=8, rot=(rx, 0, 0)))
parts.append(cylinder("CoinPeek", 0.08, 0.03, (cx + 0.2, -D / 2 + 0.05, H + 0.06), GOLD, segs=8, rot=(70, 0, 0)))

# anchor leaning on the chest's right side (in the XZ plane, slightly tilted)
ax, tilt = 0.55, -14
anc = []
anc.append(cylinder("Shank", 0.055, 0.85, (0, 0, 0.12), IRON, segs=6))
anc.append(torus("Ring", 0.1, 0.035, seg=10, seg2=4, rot=(90, 0, 0), pos=(0, 0, 1.06), color=IRON))
anc.append(box("Stock", (0.42, 0.08, 0.08), (0, 0, 0.82), IRON_D))
arm = torus("Arm", 0.34, 0.055, seg=12, seg2=5, rot=(90, 0, 0), arc=(math.radians(200), math.radians(340)), color=IRON)
move(arm, (0, 0, 0.42))
anc.append(arm)
for s in (-1, 1):  # flukes: arrow tips at the arm ends
    a = math.radians(200 if s < 0 else 340)
    tx, tz = math.cos(a) * 0.34, 0.42 + math.sin(a) * 0.34
    anc.append(slab(f"Fluke{s}", [(0, -0.02), (0.1 * s, 0.16), (-0.05 * s, 0.1)][::s], 0.06, pos=(tx, 0, tz), color=IRON_D))
for o in anc:
    move(o, (ax, 0.05, 0), (0, tilt, 0))
    gradient(o, IRON_D, IRON, 0, 1.1)
parts += anc
prop_finish("habitat_prop_captain_goo", parts)
