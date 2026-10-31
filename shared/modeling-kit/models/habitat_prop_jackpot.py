# habitat_prop_jackpot: a red bucket with gold bands, overflowing with gold coins, a few spilled on the ground.
import math, random
from models._habitat_prop5 import *

RED, RED_HI = rgb(210, 40, 56), rgb(255, 90, 90)
GOLD, GOLD_LO, GOLD_HI = rgb(255, 204, 64), rgb(246, 168, 44), rgb(255, 238, 150)
R0, R1, H = 0.3, 0.4, 0.5
parts = [
    lathe("Bucket", [(0, 0), (R0, 0), (R1, H), (R1 - 0.04, H), (0, H - 0.02)], segs=14, color_fn=vgrad(shade(RED, 0.85), RED_HI, 0, H)),
    gcyl("BandLo", R0 + 0.045, 0.07, (0, 0, 0.06), GOLD_LO, segs=14, r_top=R0 + 0.06),
    gcyl("Rim", R1 + 0.035, 0.07, (0, 0, H - 0.04), GOLD, segs=14),
]
# coin mound: a golden dome plus coins stuck in it at angles
parts.append(gradient(blob("Mound", R1 - 0.02, (0, 0, H - 0.04), GOLD, subdiv=2, jitter=0.06, squash=(1, 1, 0.62), seed=4), GOLD_LO, GOLD_HI))
R = random.Random(7)
for k in range(11):
    a = k * math.tau / 11 + R.uniform(-0.2, 0.2)
    rr = 0.12 + 0.2 * (k % 3) / 2
    z = H - 0.02 + 0.24 * math.sqrt(max(0, 1 - (rr / R1) ** 2))
    c = gcyl(f"C{k}", 0.09, 0.03, (0, 0, -0.015), GOLD, GOLD_HI, segs=10)
    parts.append(xf(c, (math.cos(a) * rr, math.sin(a) * rr, z), (R.uniform(-35, 35), R.uniform(-35, 35), 0)))
top = gcyl("CTop", 0.11, 0.035, (0, 0, -0.017), GOLD, GOLD_HI, segs=12)
parts.append(xf(top, (0.02, -0.06, H + 0.3), (70, 0, 10)))
# spilled coins
for k, (x, y) in enumerate(((-0.55, -0.3), (-0.42, -0.45), (0.56, -0.25), (0.5, 0.2), (-0.6, 0.15))):
    parts.append(gcyl(f"S{k}", 0.09, 0.03, (x, y, 0), GOLD_LO, GOLD, segs=10))
lean = gcyl("SUp", 0.1, 0.03, (0, 0, -0.015), GOLD, GOLD_HI, segs=10)
parts.append(xf(lean, (0.66, -0.4, 0.09), (70, 0, -25)))
ship("habitat_prop_jackpot", parts)
