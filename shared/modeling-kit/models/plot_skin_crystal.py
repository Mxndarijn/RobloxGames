# plot_skin_crystal: Crystal Grotto plot decor (replaces the plot's mailbox slot in game).
# A warm sandstone knoll with a cluster of lilac / aqua crystal spires, the tallest leaning in.
# ~4.6 x 7.0 x 4.2 studs, origin bottom-centre. Target < ~900 tris.
import math, random
from lib import *
from models._phoenix_pad import lathe
from models._habitat import prism_crystal, place

WOOD_D, PLAZA, PATH = PALETTE["ranch_wood_dark"], PALETTE["ranch_plaza"], PALETTE["ranch_path"]
LILAC = PALETTE["ranch_lilac"]
AQUA = rgb(150, 224, 232)
ROCK_LO, ROCK_HI = mix(WOOD_D, PLAZA, 0.6), mix(PLAZA, PATH, 0.7)
R = random.Random(5)
parts = []

KNOLL = [(0, 0), (2.3, 0), (2.5, 0.3), (2.2, 0.9), (1.7, 1.35), (1.0, 1.55), (0, 1.6)]
k = lathe("Knoll", KNOLL, segs=14, color_fn=lambda i, kk, z: shade(mix(ROCK_LO, ROCK_HI, min(1, z / 1.5)), R.uniform(0.92, 1.05)))
for v in k.data.vertices:
    if 0.2 < v.co.z < 1.5 and v.co.xy.length > 1.0:
        s = 1 + R.uniform(-0.08, 0.04)
        v.co.x *= s
        v.co.y *= s
        v.co.z += R.uniform(-0.1, 0.1)
parts.append(k)
# (radius, length, tilt, toward, x, y, colour pair)
SPIRES = [
    (0.78, 5.3, 6, 200, 0.1, 0.0, (LILAC, mix(LILAC, rgb(255, 255, 255), 0.35))),
    (0.58, 3.7, 20, 20, 1.3, 0.2, (AQUA, mix(AQUA, rgb(255, 255, 255), 0.4))),
    (0.5, 3.0, 24, 150, -1.0, 0.9, (mix(LILAC, AQUA, 0.4), mix(AQUA, rgb(255, 255, 255), 0.4))),
    (0.45, 2.4, 30, 300, 0.4, -1.3, (LILAC, mix(LILAC, rgb(255, 255, 255), 0.3))),
    (0.34, 1.5, 38, 100, 1.0, 1.2, (LILAC, mix(LILAC, rgb(255, 255, 255), 0.3))),
    (0.3, 1.3, 40, 330, 1.9, -0.6, (AQUA, mix(AQUA, rgb(255, 255, 255), 0.4))),
    (0.38, 1.7, 34, 250, -1.5, -0.5, (AQUA, mix(AQUA, rgb(255, 255, 255), 0.4))),
]
for i, (r, ln, tilt, toward, x, y, (lo, hi)) in enumerate(SPIRES):
    c = prism_crystal(f"Spire{i}", r, ln, sides=6, tip=0.34, lo=lo, hi=hi)
    parts.append(place(c, (x, y, 1.25), tilt, toward, spin_deg=i * 17))
# pebbles at the foot
for i, a in enumerate((40, 85, 130, 230, 275, 320)):
    x, y = 2.2 * math.cos(math.radians(a)), 2.2 * math.sin(math.radians(a))
    b = blob(f"Pebble{i}", 0.42 + R.uniform(0, 0.12), (x, y, 0.28), None, seed=i, subdiv=1, squash=(1.2, 1, 0.7), jitter=0.12)
    gradient(b, ROCK_LO, ROCK_HI)
    parts.append(b)
finish("plot_skin_crystal", parts)
