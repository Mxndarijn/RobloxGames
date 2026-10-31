# habitat_theme_arcane: mystic theme layer (Amethyst, Goo Oracle, Goomancer, Chrono). Back and sides of the rim only,
# no ring (the tier frame mesh supplies it), front arc clear for the signature prop. From
# habitat_crystal_grotto_overlay (hex prism crystals leaning outward from sandstone rocks, the vivid lilac + aqua
# pair): a tall lilac crystal cluster at the back, aqua and lilac clusters on the back corners, standing rune stones
# with glowing aqua runes either side, smaller shard pairs on the sides and wax candle groups with flames toward the
# front ends.
import math, random
from mathutils import Matrix
from lib import *
from models._habitat import prism_crystal, place, WOOD_D, P, CREAM
from models._habitat_theme_rim import *

PLAZA, PATH = P["ranch_plaza"], P["ranch_path"]
LILAC = mix(P["ranch_lilac"], rgb(170, 110, 240), 0.35)
AQUA = rgb(150, 224, 232)
RUNE = rgb(110, 240, 230)
ROCK_LO, ROCK_HI = mix(WOOD_D, PLAZA, 0.6), mix(PLAZA, PATH, 0.7)
STONE_LO, STONE_HI = rgb(138, 128, 160), rgb(186, 178, 206)  # lilac-grey rune stone
WAX, WAX_D = rgb(250, 238, 214), rgb(226, 206, 176)
FLAME, FLAME_HI = rgb(255, 150, 40), rgb(255, 226, 110)
R = random.Random(7)
parts = []


def tdir(deg):
    a = math.radians(deg + 90)
    return math.cos(a), math.sin(a)


def rock(name, r, pos, seed, squash=(1.2, 1.0, 0.75), rot=0):
    b = blob(name, r, pos, None, seed=seed, subdiv=1, squash=squash, jitter=0.15, rot=(0, 0, rot))
    gradient(b, ROCK_LO, ROCK_HI)
    return b


def shard(name, col, x, y, ln, rad, tilt, toward, spin=0, z=0.25):
    lo, hi = shade(col, 0.96), mix(col, CREAM, 0.36)
    c = prism_crystal(name, rad, ln, lo=lo, hi=hi)
    return place(c, (x, y, z), tilt, toward, spin_deg=spin)


def cluster(prefix, deg, r, spec, main, accent, rock_r=0.5):
    """Crystals round a base rock at (r, deg); spec = (t along the ring, d outward, len, radius, tilt, lean_off, acc)."""
    x, y = pol(r, deg)
    tx, ty = tdir(deg)
    ox, oy = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    out = [rock(prefix + "Rock", rock_r, (x, y, 0.25), seed=len(prefix) + int(deg), squash=(1.4, 1.1, 0.6), rot=deg + 90)]
    for k, (t, d, ln, rad, tilt, off, acc) in enumerate(spec):
        out.append(shard(f"{prefix}{k}", accent if acc else main, x + tx * t + ox * d, y + ty * t + oy * d, ln, rad, tilt, deg + off,
                         spin=R.uniform(0, 60)))
    return out


# --- back: the tall lilac cluster, aqua / lilac clusters on the back corners ------------------------------------
BIG = [(0.0, 0.0, 2.45, 0.5, 5, 0, False), (-0.5, 0.0, 1.6, 0.38, 20, 40, False), (0.5, 0.0, 1.45, 0.36, 22, -40, False),
       (-0.2, -0.2, 0.95, 0.27, 28, 70, True), (0.3, -0.18, 0.8, 0.24, 34, -60, True)]
parts += cluster("Big", 90, 3.16, BIG, LILAC, AQUA, rock_r=0.6)
MID = [(0.0, 0.0, 1.5, 0.4, 10, 0, False), (-0.38, 0.0, 1.0, 0.3, 24, 45, False), (0.36, 0.05, 0.85, 0.27, 28, -45, True)]
parts += cluster("MidL", 136, 3.25, MID, AQUA, LILAC)
parts += cluster("MidR", 44, 3.25, MID, LILAC, AQUA)

# --- rune stones either side of the big cluster, glowing runes on the face toward the slime ----------------------


def rune_stone(name, deg, h, w=0.62, r=3.3, glyph=0):
    x, y = pol(r, deg)
    tx, ty = tdir(deg)
    ox, oy = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    st = box(name, (w, 0.3, h), (x, y, h / 2), None, rot=(R.uniform(-4, 4), 0, deg + 90))
    bevel(st, 0.08)
    gradient(st, STONE_LO, STONE_HI)
    out = [st]
    out.append(cone(name + "Top", w * 0.62, 0.22, (x, y, h - 0.02), STONE_HI, segs=4, rot=(0, 0, deg + 45)))
    fx, fy = x - ox * 0.17, y - oy * 0.17  # on the inner face
    strokes = [[(0, 0.32, 0.08, 0.36, 0), (0.0, 0.0, 0.3, 0.07, 0), (0, -0.25, 0.22, 0.07, 35)],
               [(-0.1, 0.1, 0.07, 0.42, 20), (0.1, 0.1, 0.07, 0.42, -20), (0, -0.2, 0.3, 0.07, 0)],
               [(0, 0.05, 0.07, 0.6, 0), (0, 0.2, 0.3, 0.07, 45), (0, 0.2, 0.3, 0.07, -45)]][glyph]
    for k, (u, v, sw, sh, rot) in enumerate(strokes):
        out.append(box(f"{name}Rune{k}", (sw, 0.04, sh), (fx + tx * u, fy + ty * u, h * 0.55 + v), RUNE, rot=(0, rot, deg + 90)))
    return out


parts += rune_stone("RuneL", 113, 1.55, glyph=0)
parts += rune_stone("RuneR", 67, 1.4, glyph=1)
parts += rune_stone("RuneSL", 196, 0.95, w=0.55, glyph=2)
parts += rune_stone("RuneSR", -16, 0.9, w=0.55, glyph=2)

# --- small shard pairs on the sides ------------------------------------------------------------------------------
SM = [(0.0, 0.0, 1.0, 0.3, 14, 0, False), (0.34, 0.0, 0.65, 0.23, 30, -40, True)]
parts += cluster("SmL", 165, 3.25, SM, LILAC, AQUA, rock_r=0.38)
parts += cluster("SmR", 15, 3.25, SM, AQUA, LILAC, rock_r=0.38)


# --- wax candles with flames (groups of 2-3) ---------------------------------------------------------------------
def candle(name, x, y, h, r=0.12):
    out = [cylinder(name, r, h, (x, y, 0), WAX, segs=6)]
    gradient(out[0], WAX_D, WAX)
    out.append(blob(name + "Drip", r * 1.15, (x, y, h - 0.02), WAX, subdiv=1, squash=(1, 1, 0.45), jitter=0.05, seed=len(name)))
    out.append(cylinder(name + "Wick", 0.02, 0.08, (x, y, h), rgb(70, 60, 60), segs=3))
    fl = blob(name + "Flame", 0.09, (x, y, h + 0.17), None, subdiv=1, squash=(1, 1, 1.9), jitter=0)
    gradient(fl, FLAME, FLAME_HI)
    out.append(fl)
    return out


for gi, (deg, hs) in enumerate(((150, (0.85, 0.6, 0.45)), (30, (0.75, 0.55)), (208, (0.5, 0.35)), (-28, (0.45, 0.32, 0.25)))):
    cx, cy = pol(3.2, deg)
    tx, ty = tdir(deg)
    for k, h in enumerate(hs):
        t = (k - (len(hs) - 1) / 2) * 0.28
        d = 0.12 * (k % 2)
        ox, oy = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        parts += candle(f"Cdl{gi}{k}", cx + tx * t + ox * d, cy + ty * t + oy * d, h, r=0.12 if k == 0 else 0.1)

# --- rubble chips on the band (sit on the frame top) -------------------------------------------------------------
for i, deg in enumerate((100, 78, 124, 56, 180, 0)):
    x, y = pol(3.0 + 0.45 * (i % 2), deg)
    parts.append(rock(f"Chip{i}", 0.2, (x, y, 0.32), seed=30 + i, squash=(1.3, 1.0, 0.7), rot=deg))
theme_finish("habitat_theme_arcane", parts)
