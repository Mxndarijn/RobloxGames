# habitat_theme_garden: flower-garden theme layer (Sprout, Bumble, Prickles, Bloom, Sunny, Gaia). Back and sides of
# the rim only, no ring (the tier frame mesh supplies it), front arc clear for the signature prop. From
# habitat_flower_bed_overlay (5-petal daisies, leafy bushes, the pink / lilac / butter / cream bloom palette): a
# white picket fence round the back, a tall sunflower in the middle of it, red and pink tulip clumps either side,
# daisies on the sides, a birdhouse on a post on the right and a garden gnome on the left. (No watering can or
# cactus: those are Sprout's and Prickles' signature props.)
import math, random
from mathutils import Matrix
from lib import *
from models._habitat import lathe, CREAM, BUTTER, PINK, ROOF, WOOD, WOOD_D, P
from models._phoenix_ranch import bbox
from models._habitat_theme_rim import *

LEAF, LEAF_D = P["ranch_field_light"], P["ranch_field_dark"]
LILAC = mix(P["ranch_lilac"], CREAM, 0.25)
WHITE = rgb(250, 248, 240)
TULIP_R, TULIP_P = rgb(240, 70, 80), rgb(250, 130, 176)
SUN, SUN_C = rgb(255, 200, 40), rgb(150, 92, 52)
BHOUSE = rgb(120, 180, 236)
GNOME_B = rgb(84, 124, 218)
SKIN = rgb(250, 206, 170)
R = random.Random(11)
parts = []


def tdir(deg):
    a = math.radians(deg + 90)
    return math.cos(a), math.sin(a)


def bush(name, deg, r=3.2, size=0.42, seed=0):
    x, y = pol(r, deg)
    return blob(name, size, (x, y, size * 0.35), shade(LEAF if seed % 2 else mix(LEAF, LEAF_D, 0.3), R.uniform(0.95, 1.05)),
                subdiv=1, squash=(1.3, 1.0, 0.8), jitter=0.08, seed=seed, rot=(0, 0, deg + 90))


def daisy(i, x, y, h, col, r=0.36, centre=BUTTER):
    """Stem + 5 petal blobs round a centre bead at height h (from habitat_flower_bed_overlay)."""
    out = [cylinder(f"Stem{i}", 0.06, h, (x, y, 0), LEAF_D, segs=4)]
    for k in range(5):
        a = k * math.tau / 5 + i
        out.append(blob(f"Pt{i}_{k}", r * 0.55, (x + math.cos(a) * r * 0.6, y + math.sin(a) * r * 0.6, h), col,
                        subdiv=1, squash=(1.0, 0.7, 0.4), jitter=0, rot=(0, 0, math.degrees(a))))
    out.append(blob(f"Ct{i}", r * 0.38, (x, y, h + 0.06), centre, subdiv=1, squash=(1, 1, 0.7), jitter=0))
    return out


def tulip(name, x, y, h, col, lean=(0, 0)):
    """Stem, one leaf, a cup head with three pointed petal tips."""
    hx, hy = x + lean[0], y + lean[1]
    out = [tube(name + "St", [(x, y, 0), (hx, hy, h)], [0.06, 0.05], LEAF_D, segs=4)]
    out.append(blob(name + "Leaf", 0.26, (x + 0.08, y, 0.38), LEAF, subdiv=1, squash=(0.45, 0.3, 1.5), jitter=0, rot=(0, 20, R.uniform(0, 180))))
    head = blob(name + "Head", 0.22, (hx, hy, h + 0.16), None, subdiv=1, squash=(1, 1, 1.25), jitter=0)
    gradient(head, shade(col, 0.85), col)
    out.append(head)
    for k in range(3):
        a = k * math.tau / 3 + 0.5
        out.append(cone(name + f"Tip{k}", 0.11, 0.2, (hx + 0.12 * math.cos(a), hy + 0.12 * math.sin(a), h + 0.32), shade(col, 1.06), segs=3))
    return out


# --- white picket fence round the back (pickets rigid, rails bend round the ring) -----------------------------
FR = 3.62
A0, A1, N = 18, 162, 14
for k in range(N):
    deg = A0 + (A1 - A0) * k / (N - 1)
    x, y = pol(FR, deg)
    h = 0.95 - 0.25 * abs(deg - 90) / 72 + 0.04 * (k % 2)
    parts.append(box(f"Picket{k}", (0.26, 0.1, h), (x, y, h / 2), WHITE, rot=(0, 0, deg + 90)))
    gradient(parts[-1], shade(WHITE, 0.86), WHITE)
    parts.append(cone(f"PicketTip{k}", 0.185, 0.18, (x, y, h), WHITE, segs=4, rot=(0, 0, deg + 45)))
for j, z in enumerate((0.3, 0.62)):
    pts = [(*pol(FR + 0.08, A0 - 2 + (A1 - A0 + 4) * t / 12), z) for t in range(13)]
    parts.append(tube(f"Rail{j}", pts, [0.06] * 13, shade(WHITE, 0.92), segs=4))

# --- tall sunflower at the back middle, head turned to the front ----------------------------------------------
sx, sy = pol(3.2, 90)
SH = 1.95
parts.append(tube("SunStem", [(sx, sy, 0), (sx + 0.05, sy, SH * 0.5), (sx, sy - 0.05, SH)], [0.09, 0.08, 0.07], LEAF_D, segs=5))
for s in (-1, 1):
    parts.append(blob(f"SunLeaf{s}", 0.32, (sx + s * 0.28, sy, 0.95 + 0.2 * s), LEAF, subdiv=1, squash=(1.4, 0.3, 0.6), jitter=0,
                      rot=(0, -s * 25, 0)))
head = Matrix.Translation((sx, sy - 0.06, SH)) @ Matrix.Rotation(math.radians(80), 4, "X")  # face toward -Y
for k in range(10):
    a = k * math.tau / 10
    p = blob(f"SunPetal{k}", 0.22, (0.47 * math.cos(a), 0.47 * math.sin(a), 0), SUN if k % 2 else shade(SUN, 0.94), subdiv=1,
             squash=(1.5, 0.75, 0.35), jitter=0, rot=(0, 0, math.degrees(a)))
    p.data.transform(head)
    parts.append(p)
c = cylinder("SunCentre", 0.36, 0.14, (0, 0, -0.04), SUN_C, segs=10)
c.data.transform(head)
parts.append(c)
# --- tulip clumps either side of the sunflower ----------------------------------------------------------------
for ci, (deg, cols) in enumerate(((124, (TULIP_R, TULIP_P, TULIP_R)), (56, (TULIP_P, TULIP_R, LILAC)))):
    cx, cy = pol(3.2, deg)
    tx, ty = tdir(deg)
    parts.append(bush(f"TulBush{ci}", deg, r=3.2, size=0.5, seed=10 + ci))
    for k, (t, h) in enumerate(((-0.35, 1.15), (0.0, 1.45), (0.35, 1.05))):
        parts += tulip(f"Tul{ci}{k}", cx + tx * t, cy + ty * t, h, cols[k], lean=(tx * t * 0.25, ty * t * 0.25))

# --- daisies on the sides (big ones mid side, small low ones toward the front) --------------------------------
for i, (deg, h, col, r) in enumerate(((154, 1.35, CREAM, 0.56), (26, 1.25, PINK, 0.56), (204, 0.7, LILAC, 0.42), (-24, 0.75, CREAM, 0.42))):
    x, y = pol(3.27, deg)
    if r > 0.5:
        parts += daisy(100 + i, x, y, h, col, r=r)
    else:  # small front ones: a round bloom head + centre bead (cheaper than 5 petals, still reads)
        parts += [cylinder(f"BSt{i}", 0.06, h, (x, y, 0), LEAF_D, segs=4),
                  blob(f"Bl{i}", 0.36, (x, y, h + 0.04), col, subdiv=2, squash=(1, 1, 0.55), jitter=0.03, seed=i),
                  blob(f"BC{i}", 0.15, (x, y, h + 0.2), BUTTER, subdiv=1, jitter=0)]
    parts.append(bush(f"DaisyBush{i}", deg + (6 if deg > 90 else -6), r=3.25, size=0.38, seed=20 + i))

# --- birdhouse on a post on the right: red roof, round door facing the slime ------------------------------------
bx, by = pol(3.25, 2)
ix, iy = -math.cos(math.radians(2)), -math.sin(math.radians(2))  # toward the slime
parts.append(box("BirdPost", (0.14, 0.14, 0.95), (bx, by, 0.475), WOOD))
parts.append(bbox("BirdHouse", (0.5, 0.5, 0.48), (bx, by, 1.18), shade(BHOUSE, 0.88), BHOUSE, bev=0.03, rot=(0, 0, 2)))
for s in (-1, 1):
    tx, ty = tdir(2)
    parts.append(bbox(f"BirdRoof{s}", (0.56, 0.42, 0.08), (bx + tx * s * 0.16, by + ty * s * 0.16, 1.52), shade(ROOF, 0.9), ROOF, bev=0,
                      rot=(s * -38, 0, 2)))
parts.append(cylinder("BirdHole", 0.1, 0.04, (bx + ix * 0.25, by + iy * 0.25, 1.24), rgb(90, 66, 52), segs=8, rot=(0, 90, 2)))
parts.append(cylinder("BirdPerch", 0.025, 0.14, (bx + ix * 0.3, by + iy * 0.3, 1.07), WOOD, segs=4, rot=(0, 90, 2)))
parts.append(bush("PostBush", -8, r=3.25, size=0.36, seed=31))

# --- garden gnome on the left: red pointy hat, white beard, blue coat, facing the slime --------------------------
gx, gy = pol(3.22, 180)
fx, fy = -math.cos(math.radians(180)), -math.sin(math.radians(180))
coat = cylinder("GnomeCoat", 0.3, 0.5, (gx, gy, 0), GNOME_B, segs=8, r_top=0.2)
gradient(coat, shade(GNOME_B, 0.85), GNOME_B)
parts.append(coat)
parts.append(blob("GnomeFace", 0.18, (gx, gy, 0.62), SKIN, subdiv=1, jitter=0))
parts.append(blob("GnomeBeard", 0.2, (gx + fx * 0.1, gy + fy * 0.1, 0.5), WHITE, subdiv=1, squash=(0.8, 0.8, 1.2), jitter=0.04, seed=2))
parts.append(blob("GnomeNose", 0.06, (gx + fx * 0.18, gy + fy * 0.18, 0.64), shade(SKIN, 0.92), subdiv=1, jitter=0))
parts.append(cone("GnomeHat", 0.21, 0.55, (gx, gy, 0.68), TULIP_R, segs=8))
parts.append(box("GnomeBelt", (0.5, 0.5, 0.07), (gx, gy, 0.22), rgb(90, 66, 52)))
parts.append(bush("GnomeBush", 190, r=3.3, size=0.34, seed=33))
theme_finish("habitat_theme_garden", parts)
