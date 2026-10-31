# habitat_prop_bubbles: a pastel soap dish with a pink soap bar and foam, a bubble wand leaning out of it, and a
# few round bubbles floating up.
import math
from lib import *
from models._habitat_prop2 import *

DISH, DISH_D = rgb(130, 210, 250), rgb(90, 176, 230)
SOAP = rgb(255, 160, 200)
FOAM = rgb(252, 252, 255)
WAND = rgb(255, 120, 170)
BUB, BUB_HI = rgb(140, 218, 255), rgb(222, 176, 255)  # saturated: pale blue-grey goes slate in the Roblox look

# dish: shallow oval bowl on a little foot (lathe squashed in y)
parts = [lathe("Dish", [(0.3, 0.0), (0.34, 0.04), (0.5, 0.08), (0.6, 0.16), (0.62, 0.2), (0.56, 0.2), (0.46, 0.12), (0.0, 0.11)],
               segs=16, col=lambda c, i, k: DISH_D if c.z < 0.07 else DISH, sy=0.72)]
# soap bar and foam
sb = box("Soap", (0.42, 0.26, 0.12), (-0.12, 0.04, 0.17), SOAP, rot=(0, 0, 12))
bevel(sb, 0.04)
parts.append(sb)
for j, (x, y, r) in enumerate([(-0.3, 0.0, 0.08), (-0.18, -0.05, 0.1), (0.02, 0.1, 0.07), (0.25, -0.08, 0.09), (0.36, 0.06, 0.07)]):
    parts.append(blob(f"Foam{j}", r, (x, y, 0.2 + (0.04 if j in (1, 2) else 0)), FOAM, subdiv=2, squash=(1.2, 1.0, 0.8), jitter=0.05, seed=j))
# wand: stick leaning from the dish up to the right, ring loop at the top facing the front
base = (0.18, 0.02, 0.14)
tip = (0.5, -0.02, 0.78)
parts.append(tube("Stick", [base, tip], [0.035, 0.035], WAND, segs=6))
RC = (0.58, -0.03, 0.95)
ring = []
for j in range(13):
    a = j * math.tau / 12 + math.radians(-115)
    ring.append((RC[0] + math.cos(a) * 0.17, RC[1], RC[2] + math.sin(a) * 0.17))
parts.append(smooth(tube("Loop", ring, [0.03] * len(ring), WAND, segs=6)))
# bubbles: pale cyan/lilac spheres with a white glint, floating left and up
for j, (x, y, z, r) in enumerate([(0.18, -0.12, 1.2, 0.14), (-0.14, -0.05, 1.27, 0.1), (-0.4, 0.0, 1.0, 0.12), (0.0, 0.05, 0.72, 0.07)]):
    parts.append(smooth(blob(f"Bub{j}", r, (x, y, z), BUB if j % 2 == 0 else BUB_HI, subdiv=2, jitter=0)))
    parts.append(blob(f"Glint{j}", r * 0.28, (x - r * 0.4, y - r * 0.82, z + r * 0.35), WHITE, subdiv=1, squash=(1, 0.5, 1), jitter=0))
ship("habitat_prop_bubbles", parts)
