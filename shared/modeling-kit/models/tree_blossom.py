# tree_blossom: cherry blossom (replaces v17 tree_blossom, ~9.6 x 10.8 x 7.3 studs; trunk r 0.7 at the origin).
import math, random
from lib import *

R = random.Random(23)
BARK, BARK_D = rgb(128, 86, 72), rgb(100, 66, 58)  # cherry bark: redder than oak (r03: lighter for the game sun)
PINK_D, PINK, PINK_L = rgb(232, 116, 166), rgb(244, 156, 190), rgb(255, 210, 226)
parts = []

parts.append(tube("Trunk", [(0, 0, -0.1), (0, 0, 0.6), (0.25, 0, 2.2), (0.0, 0, 3.6), (-0.2, 0, 4.6)],
                  [1.1, 0.72, 0.58, 0.55, 0.45], BARK, segs=7, seed=R, jitter=0.05))
gradient(parts[-1], BARK_D, shade(BARK, 1.15), z0=0, z1=4.6)
for k in range(4):
    a = k * math.tau / 4 + 0.6
    c, s = math.cos(a), math.sin(a)
    parts.append(tube(f"Root{k}", [(c * 0.3, s * 0.3, 0.7), (c * 1.0, s * 1.0, 0.25), (c * 1.6, s * 1.6, -0.05)],
                      [0.36, 0.24, 0.1], BARK_D, segs=5, seed=R))
# forked limbs reaching sideways (+-X): the wide, low, spreading cherry shape
LIMBS = [((-0.2, 0, 4.4), (-1.6, 0.2, 5.6), (-2.4, 0.3, 6.6)),
         ((-0.1, 0, 4.2), (1.5, -0.2, 5.4), (2.4, -0.5, 6.4)),
         ((-0.2, 0, 4.5), (-0.3, 0.6, 6.0), (0.0, 0.8, 7.2))]
for k, pts in enumerate(LIMBS):
    parts.append(tube(f"Limb{k}", pts, [0.4, 0.3, 0.18], BARK, segs=5, seed=R))
    gradient(parts[-1], BARK, shade(BARK, 1.2))

# blossom clouds: one cluster per limb end + a crown, uneven puffs, dark pink below / pale on top
CL = [(-2.45, 0.3, 7.2, 1.0), (2.45, -0.5, 7.0, 1.0), (0.0, 0.5, 8.3, 1.1)]
for ci, (cx, cy, cz, sc) in enumerate(CL):
    for k in range(5):
        a = k * math.tau / 5 + R.uniform(-0.4, 0.4) + ci
        d = R.uniform(0.9, 1.5) * sc
        rr = R.uniform(1.3, 1.8) * sc
        dz = R.uniform(-0.5, 0.7)
        o = blob(f"Puff{ci}_{k}", rr, (cx + math.cos(a) * d, cy + math.sin(a) * d * 1.25, cz + dz), seed=R,
                 subdiv=2, squash=(1, 1, 0.82), jitter=0.07)
        gradient(o, PINK_D, PINK_L if dz > 0 else PINK)
        parts.append(o)
finish("tree_blossom", parts)
