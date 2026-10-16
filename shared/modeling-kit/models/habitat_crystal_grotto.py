# habitat_crystal_grotto: warm sandstone rock bowl (7.8 x 5.0 x 7.8) with a flat stone seat at z=2.4 for the slime,
# lilac / aqua crystal clusters on the rim only (seat column r<2 stays clear up to the top, 5.0).
import math, random
from lib import *
from models._habitat import *

W, H = 7.8, 5.0
PLAZA, PATH = P["ranch_plaza"], P["ranch_path"]
LILAC = P["ranch_lilac"]
AQUA = rgb(150, 224, 232)  # crystal accent (soft, not neon); r03: a touch lighter, r02 went teal-grey
ROCK_LO, ROCK_HI = mix(WOOD_D, PLAZA, 0.6), mix(PLAZA, PATH, 0.7)  # r02: warm sandstone, less orange
R = random.Random(7)
parts = []

# bowl: outer flank -> rim crest (~3.0) -> inner slope -> floor groove at 2.3 round the seat slab
BOWL = [(0, 0), (3.7, 0), (3.9, 0.3), (3.8, 1.0), (3.6, 1.7), (3.4, 2.35), (3.15, 2.85), (2.8, 3.05), (2.45, 2.8), (2.2, 2.35), (0, 2.3)]  # r02: sloped flank, more rows
def bowl_col(i, k, z):
    if i >= 9:
        return mix(WOOD_D, PLAZA, 0.35)  # floor groove (shadowed)
    t = min(1.0, z / 3.0)
    return shade(mix(ROCK_LO, ROCK_HI, t), R.uniform(0.92, 1.04))  # r02: per-face stone facets
bowl = lathe("Bowl", BOWL, segs=18, color_fn=bowl_col)
for v in bowl.data.vertices:  # r02: per-vertex rocky wobble on the flank and rim (not the bottom or floor)
    if 0.2 < v.co.z < 3.1 and v.co.xy.length > 2.4:
        s = 1 + R.uniform(-0.07, 0.03)
        v.co.x *= s
        v.co.y *= s
        v.co.z += R.uniform(-0.12, 0.12)
parts.append(bowl)

# seat: flat stone slab, top exactly at SEAT, slightly lighter, chamfered edge
SLAB = [(0, 2.1), (2.05, 2.1), (2.1, 2.3), (1.98, SEAT), (0, SEAT)]
parts.append(lathe("Seat", SLAB, segs=16, color_fn=lambda i, k, z: mix(PLAZA, PATH, 0.75) if i >= 3 else mix(PLAZA, WOOD_D, 0.2)))

# rim boulders between the crystal clusters
for i, a in enumerate((25, 95, 160, 215, 290, 340)):
    r = 3.25
    b = blob(f"Boulder{i}", 0.68 + R.uniform(0, 0.15), (r * math.cos(math.radians(a)), r * math.sin(math.radians(a)), 2.75),
             None, seed=i, subdiv=1, squash=(1.2, 1.0, 0.8), jitter=0.15, rot=(0, 0, a))
    gradient(b, ROCK_LO, ROCK_HI)
    parts.append(b)

# crystal clusters on the rim: (angle, base r, colour, [(len, radius, tilt, side offset deg)])
CLUSTERS = [  # r02: chunkier, taller crystals (r01 read as small pebbles); r03: +15 % girth, 4th shard on the big ones
    (60, 3.0, LILAC, [(2.35, 0.58, 10, 0), (1.6, 0.44, 28, -20), (1.25, 0.36, 30, 24), (0.8, 0.3, 46, -40)]),
    (130, 3.05, AQUA, [(1.85, 0.5, 16, 0), (1.3, 0.36, 32, 24)]),
    (190, 3.0, LILAC, [(2.1, 0.55, 12, 0), (1.45, 0.4, 30, 20), (1.1, 0.34, 36, -24), (0.75, 0.28, 46, 40)]),
    (250, 3.05, AQUA, [(1.55, 0.46, 20, 0), (1.15, 0.34, 34, -22)]),
    (315, 3.0, LILAC, [(1.85, 0.5, 14, 0), (1.3, 0.36, 30, 22), (0.85, 0.3, 44, -34)]),
    (5, 3.05, AQUA, [(1.65, 0.46, 18, 0), (1.2, 0.34, 34, -24)]),
]
n = 0
for a, r, col, xs in CLUSTERS:
    lo, hi = shade(col, 0.78), mix(col, P["ranch_cream"], 0.25)
    for ln, rad, tilt, off in xs:
        aa = math.radians(a + off * 0.35)
        c = prism_crystal(f"Crystal{n}", rad, ln, lo=lo, hi=hi)
        place(c, (r * math.cos(aa), r * math.sin(aa), 2.75), tilt, a + off, spin_deg=R.uniform(0, 60))
        parts.append(c)
        n += 1

o = finish("habitat_crystal_grotto", parts)
fit(o, W, H, W)
