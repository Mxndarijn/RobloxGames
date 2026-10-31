# habitat_prop_steam: a tiny hot-spring pool: a ring of round rocks round turquoise water, the three wavy steam lines of the hot-spring sign rising.
import math, random
from models._habitat_prop3 import *

WATER, WATER_HI = rgb(64, 206, 230), rgb(150, 236, 248)
STEAM, STEAM_LO = rgb(255, 255, 255), rgb(222, 232, 240)
R = random.Random(3)
parts = []
RX, RY = 0.66, 0.32  # pool half-size (ellipse): rocks sit on it
# water: shallow ellipse disc with a lighter ripple ring
water = lathe("Water", [(0, 0), (1.0, 0.0), (1.0, 0.14), (0.62, 0.15), (0, 0.15)], segs=16,
              color_fn=lambda i, k, z: WATER_HI if i == 2 else WATER)
parts.append(xf(water, (0, 0, 0), (0, 0, 0), (RX, RY, 1)))
parts.append(xf(lathe("Ripple", [(0, 0.15), (0.32, 0.15), (0.32, 0.165), (0, 0.165)], segs=12, color_fn=lambda i, k, z: WATER_HI),
                (0.1, 0.02, 0), (0, 0, 0), (RX, RY, 1)))
# rocks: a ring of chunky rounded stones, bigger at the back
n = 11
for i in range(n):
    a = i / n * math.tau + 0.15
    back = 0.5 + 0.5 * math.sin(a)  # 1 at the back (+Y)
    s = 0.15 + 0.06 * back + R.uniform(-0.02, 0.02)
    x, y = math.cos(a) * (RX + 0.06), math.sin(a) * (RY + 0.06)
    parts.append(floor(blob(f"Rock{i}", s, (x, y, s * 0.4), shade(ROCK, R.uniform(0.92, 1.1)), subdiv=1,
                            squash=(1.0, 1.25, 0.8), jitter=0.1, seed=i, rot=(0, 0, math.degrees(a)))))
# steam: the hot-spring sign's three wavy lines rising out of the water, thick and tapering, the middle one tallest
for i, (x, h, ph) in enumerate(((-0.24, 0.85, 0.0), (0.0, 1.05, 1.4), (0.24, 0.8, 2.6))):
    N = 10
    pts = [(x + 0.075 * math.sin(ph + 2.0 * math.pi * t / N * 1.5), 0.02 + 0.06 * t / N, 0.1 + h * t / N) for t in range(N + 1)]
    rad = [0.09 - 0.045 * (t / N) ** 1.5 for t in range(N + 1)]
    st = tube(f"Steam{i}", pts, rad, STEAM, segs=5, twist_free=True)
    parts.append(grad(st, STEAM_LO, STEAM))
ship("habitat_prop_steam", parts)
