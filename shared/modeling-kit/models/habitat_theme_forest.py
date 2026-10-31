# habitat_theme_forest: woodland theme layer (Pebble, Mushie, Truffle, Elder Oak). Back and sides of the rim only,
# no ring (the tier frame mesh supplies it), front arc clear for the signature prop. From
# habitat_mushroom_ring_overlay (red toadstools with cream spot columns, moss tufts, same moss / cap / stem colours):
# a mossy fallen log across the back with a little toadstool on it, two tall red toadstools behind its ends, brown
# truffle mushroom clumps on the sides, an old tree stump on the left, mossy pebbles on the right.
import math, random
from mathutils import Matrix
from lib import *
from models._habitat import lathe, CREAM, P, WOOD, WOOD_D
from models._habitat_theme_rim import *

MOSS, MOSS_D = P["ranch_field_light"], P["ranch_field_dark"]
CAP, CAP_D = rgb(234, 74, 66), rgb(196, 58, 60)
STEM = mix(CREAM, rgb(255, 244, 200), 0.5)
BROWN, BROWN_D = rgb(188, 124, 76), rgb(150, 96, 60)
BARK, BARK_D = rgb(164, 112, 74), rgb(132, 88, 58)
RING = rgb(238, 200, 140)
STONE, STONE_HI = rgb(160, 156, 150), rgb(196, 192, 184)
R = random.Random(9)
parts = []


def tdir(deg):
    a = math.radians(deg + 90)
    return math.cos(a), math.sin(a)


def toadstool(name, x, y, s, sh, cap=CAP, cap_d=CAP_D, spots=True, z0=0.0):
    """Cream stem (height sh) + dome cap of radius 0.62 s with cream spot columns."""
    out = [cylinder(name + "St", 0.2 * s + 0.05, sh + 0.1, (x, y, z0), STEM, segs=6, r_top=0.15 * s + 0.04)]

    def col(ii, k, zz):
        if ii == 0:
            return shade(STEM, 0.92)
        if spots and (k + ii) % 3 == 0 and ii >= 2:
            return CREAM
        return cap_d if ii == 1 else cap
    out.append(lathe(name + "Cap", [(0, 0), (0.62 * s, 0.04), (0.56 * s, 0.3 * s), (0.32 * s, 0.5 * s), (0, 0.55 * s)], segs=8,
                     phase=math.pi / 8, pos=(x, y, z0 + sh - 0.05), color_fn=col))
    return out


def moss(name, deg, r=3.25, size=0.4, z=0.12, seed=0):
    x, y = pol(r, deg)
    return blob(name, size, (x, y, z), shade(MOSS, R.uniform(0.9, 1.05)), subdiv=1, squash=(1.4, 1.0, 0.55), jitter=0.06,
                seed=seed, rot=(0, 0, deg + 90))


# --- fallen log across the back -----------------------------------------------------------------------------------
LX, LY = pol(3.3, 90)
LL, LR = 2.5, 0.4
log = cylinder("Log", LR, LL, (0, 0, -LL / 2), BARK, segs=8)
gradient(log, BARK_D, BARK)
log.data.transform(Matrix.Translation((LX, LY, LR + 0.02)) @ Matrix.Rotation(math.radians(90), 4, "Y")
                   @ Matrix.Rotation(math.radians(360 / 16), 4, "Z"))
parts.append(log)
for s in (-1, 1):  # pale end rings with a darker heart
    parts.append(cylinder(f"LogEnd{s}", LR - 0.06, 0.04, (LX + s * LL / 2, LY, LR + 0.02), RING, segs=8, rot=(0, 90, 0)))
    parts.append(cylinder(f"LogHeart{s}", 0.14, 0.05, (LX + s * (LL / 2 + 0.005), LY, LR + 0.02), BARK_D, segs=6, rot=(0, 90, 0)))
parts.append(cylinder("Branch", 0.12, 0.5, (LX + 0.55, LY + 0.1, LR + 0.25), BARK, segs=5, rot=(0, -35, 20)))
for k, t in enumerate((-0.7, 0.05)):  # moss on top of the log
    parts.append(blob(f"LogMoss{k}", 0.38, (LX + t, LY, 2 * LR - 0.02), MOSS, subdiv=1, squash=(1.5, 0.95, 0.45), jitter=0.06, seed=k))
parts += toadstool("LogShroom", LX - 0.25, LY - 0.05, 0.55, 0.32, z0=2 * LR - 0.05)

# --- tall red toadstools behind the log ends ---------------------------------------------------------------------
for i, (deg, s, sh) in enumerate(((121, 1.0, 1.95), (59, 0.88, 1.45))):
    x, y = pol(3.28, deg)
    parts += toadstool(f"Big{i}", x, y, s, sh)
    parts.append(moss(f"BigMoss{i}", deg, size=0.52, seed=10 + i))

# --- brown truffle mushroom clumps on the sides ------------------------------------------------------------------
for ci, deg in enumerate((152, 28)):
    cx, cy = pol(3.22, deg)
    tx, ty = tdir(deg)
    for k, (t, s, sh) in enumerate(((0.0, 0.7, 0.75), (0.42, 0.5, 0.45), (-0.38, 0.45, 0.35))):
        parts += toadstool(f"Tr{ci}{k}", cx + tx * t, cy + ty * t, s, sh, cap=BROWN, cap_d=BROWN_D, spots=(k == 0))
    parts.append(moss(f"TrMoss{ci}", deg, size=0.46, seed=20 + ci))

# --- old tree stump on the left: rings on top, root flares, a moss cap ------------------------------------------
sx, sy = pol(3.2, 186)
ST = [(0, 0), (0.62, 0), (0.5, 0.18), (0.46, 0.85), (0.44, 0.9), (0, 0.9)]
parts.append(lathe("Stump", ST, segs=8, pos=(sx, sy, 0), phase=math.pi / 8,
                   color_fn=lambda i, k, z: RING if i >= 4 else (shade(BARK, 0.95 + 0.1 * (k % 2)) if i >= 2 else BARK_D)))
for k in range(3):
    parts.append(cylinder(f"Ring{k}", 0.32 - 0.1 * k, 0.02, (sx, sy, 0.9 + 0.005 * (k + 1)), shade(RING, 0.86) if k % 2 == 0 else RING, segs=8))
parts.append(blob("StumpMoss", 0.24, (sx + 0.22, sy + 0.1, 0.92), MOSS, subdiv=1, squash=(1.4, 1, 0.5), jitter=0.05, seed=3))
parts += toadstool("StumpShroom", sx - 0.15, sy + 0.42, 0.42, 0.3)

# --- mossy pebbles on the right ----------------------------------------------------------------------------------
for k, (deg, r, size) in enumerate(((-6, 3.2, 0.42), (-20, 3.3, 0.3), (6, 3.45, 0.26))):
    x, y = pol(r, deg)
    rk = blob(f"Pebble{k}", size, (x, y, size * 0.45), None, subdiv=1, squash=(1.25, 1.0, 0.8), jitter=0.12, seed=40 + k)
    gradient(rk, STONE, STONE_HI)
    parts.append(rk)
parts.append(blob("PebbleMoss", 0.22, (*pol(3.2, -4), 0.72), MOSS, subdiv=1, squash=(1.4, 1, 0.45), jitter=0.05, seed=5))

# --- ferns: a fan of leaning fronds (squashed blobs) --------------------------------------------------------------
FERN = mix(MOSS_D, MOSS, 0.35)
for i, deg in enumerate((139, 41, 197)):
    fx, fy = pol(3.25, deg)
    for k in range(5):
        a = math.radians(deg + 90 + (k - 2) * 38 + (180 if k % 2 else 0) * 0)
        lean = 35 + 10 * (k % 2)
        fr = blob(f"Frond{i}{k}", 0.42, (0, 0, 0.42), shade(FERN, 0.95 + 0.05 * (k % 3)), subdiv=1, squash=(0.32, 0.12, 1.0), jitter=0)
        fr.data.transform(Matrix.Translation((fx, fy, 0.05)) @ Matrix.Rotation(a - math.pi / 2, 4, "Z") @ Matrix.Rotation(math.radians(lean), 4, "X"))
        parts.append(fr)

# --- moss clumps and small toadstools toward the front ends ------------------------------------------------------
for i, deg in enumerate((205, 168, 40, 140, 75)):
    parts.append(moss(f"Tuft{i}", deg, r=3.0 + 0.4 * (i % 2), size=0.34, z=0.2, seed=60 + i))
parts += toadstool("SmallL", *pol(3.3, 208), 0.42, 0.35)
parts += toadstool("SmallR", *pol(3.15, -30), 0.4, 0.3)
theme_finish("habitat_theme_forest", parts)
