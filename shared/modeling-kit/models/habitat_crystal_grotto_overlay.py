# habitat_crystal_grotto_overlay: crystal dressing for the crate pad: a sandstone rubble frame round the mat,
# big lilac / aqua crystal clusters on the four corners (leaning outward, never over the slime), small aqua
# shard pairs between boulders on the edge middles, rubble chips along the band.
import math, random
from lib import *
from models._habitat import *
from models._habitat_overlay import *

PLAZA, PATH = P["ranch_plaza"], P["ranch_path"]
LILAC = mix(P["ranch_lilac"], rgb(170, 110, 240), 0.35)  # r02: a more vivid lilac, r01 read grey-lilac
AQUA = rgb(150, 224, 232)
ROCK_LO, ROCK_HI = mix(WOOD_D, PLAZA, 0.6), mix(PLAZA, PATH, 0.7)  # warm sandstone (as the full habitat)
R = random.Random(7)
parts = [frame("Rubble", ROCK_HI, ROCK_LO, seed=7, wobble=0.16)]


def rock(name, r, pos, seed, squash=(1.2, 1.0, 0.75), rot=0):
    b = blob(name, r, pos, None, seed=seed, subdiv=1, squash=squash, jitter=0.15, rot=(0, 0, rot))
    gradient(b, ROCK_LO, ROCK_HI)
    return b


def shard(name, col, base, ang, d, t, ln, rad, tilt, off, spin):
    """Crystal at local (d along the outward direction ang, t along the tangent) from base, leaning outward."""
    a = math.radians(ang)
    x = base[0] + d * math.cos(a) - t * math.sin(a)
    y = base[1] + d * math.sin(a) + t * math.cos(a)
    lo, hi = shade(col, 0.96), mix(col, CREAM, 0.36)  # r04: lighter, roblox look went dark teal/purple in shade
    c = prism_crystal(name, rad, ln, lo=lo, hi=hi)
    return place(c, (x, y, 0.42), tilt, ang + off, spin_deg=spin)


# corner clusters: identical geometry rotated per corner (4-fold symmetric -> bbox centred); colours alternate
CLUSTER = [  # (d, t, len, radius, tilt, off, spin, accent)
    (0.0, 0.0, 2.2, 0.56, 12, 0, 10, False),
    (-0.25, -0.5, 1.6, 0.42, 22, -40, 35, False),
    (-0.25, 0.5, 1.45, 0.4, 24, 40, 5, False),
    (-0.45, -0.05, 1.05, 0.32, 30, -12, 50, True),
    (0.2, 0.25, 0.85, 0.28, 44, 25, 20, True),
]
n = 0
for ci, (cx, cy, ang) in enumerate(CORNERS):
    base = (cx * 0.92, cy * 0.92)
    main, accent = (LILAC, AQUA) if ci % 2 == 0 else (AQUA, LILAC)
    parts.append(rock(f"CornerRock{ci}", 0.62, (base[0], base[1], 0.4), seed=ci, squash=(1.25, 1.25, 0.55), rot=ang))
    for d, t, ln, rad, tilt, off, spin, acc in CLUSTER:
        parts.append(shard(f"Crystal{n}", accent if acc else main, base, ang, d, t, ln, rad, tilt, off, spin))
        n += 1

# edge middles: two boulders with a small aqua / lilac shard pair between them
for ei, (x, y, ang) in enumerate(band_spots(4, phase=0.5)):
    a = math.radians(ang)
    tx, ty = -math.sin(a), math.cos(a)
    for s in (-1, 1):
        parts.append(rock(f"Boulder{ei}{s}", 0.48, (x + tx * 0.8 * s, y + ty * 0.8 * s, 0.42), seed=10 + ei * 2 + s, rot=ang))
    col = AQUA if ei % 2 == 0 else LILAC
    parts.append(shard(f"Crystal{n}", col, (x, y), ang, 0.1, -0.15, 1.15, 0.34, 16, -20, 15))
    parts.append(shard(f"Crystal{n + 1}", col, (x, y), ang, 0.0, 0.25, 0.8, 0.27, 32, 30, 40))
    n += 2

# rubble chips along the band between the props
for i, (x, y, ang) in enumerate(band_spots(8, phase=0.5)):
    parts.append(rock(f"Chip{i}", 0.26, (x, y, 0.22), seed=30 + i, squash=(1.3, 1.0, 0.7), rot=ang))

overlay_finish("habitat_crystal_grotto_overlay", parts)
