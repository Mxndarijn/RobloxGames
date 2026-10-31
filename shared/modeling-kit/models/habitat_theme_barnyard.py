# habitat_theme_barnyard: farmyard theme layer (Moo, Lop, Whiskers, Moo-shroom). Back and sides of the rim only,
# no ring (the tier frame mesh supplies it), front arc clear for the signature prop. From habitat_barn_crate_overlay
# (barn red + white trim, hay bales with twine) with bits of hay_nest (straws, wisps) and rodeo_barrel (wood posts):
# a little red barn door with a white X brace and gable roof at the back, hay bale stacks either side of it, a
# wheelbarrow of hay and a small hen on the right, a feed sack and a pitchfork leaning on the bales on the left, a low
# post-and-rail fence curving round the front sides. (No milk pail, carrots or mushroom: those are Moo's, Lop's and
# Moo-shroom's signature props.)
import math
import random
from mathutils import Matrix
from lib import *
from models._habitat_theme_rim import *
from models._phoenix_ranch import BUTTER, WOOD, WOOD_D, CREAM, bbox

BARN = rgb(220, 54, 46)
BARN_D = shade(BARN, 0.82)
WHITE = rgb(250, 246, 238)
HAY = BUTTER
TWINE = shade(WOOD_D, 0.9)
FENCE = mix(WOOD, CREAM, 0.12)
METAL = rgb(206, 214, 222)
R = random.Random(3)
parts = []


def tdir(deg):
    """Unit tangent (counter-clockwise) at angle deg."""
    a = math.radians(deg + 90)
    return math.cos(a), math.sin(a)


# --- barn door at the back ------------------------------------------------------------------------------------
DX, DY = pol(3.3, 90)
D_W, D_H = 1.9, 1.8
parts.append(bbox("Door", (D_W, 0.3, D_H), (DX, DY, D_H / 2), BARN_D, BARN, bev=0.03))
diag = math.degrees(math.atan2(D_H - 0.3, D_W - 0.3))
L = math.hypot(D_W - 0.3, D_H - 0.3)
for f, fy in (("F", DY - 0.19), ("B", DY + 0.19)):
    for s in (-1, 1):
        parts.append(box(f"DoorSide{f}{s}", (0.17, 0.08, D_H), (DX + s * (D_W / 2 - 0.085), fy, D_H / 2), WHITE))
        parts.append(box(f"DoorX{f}{s}", (L, 0.06, 0.15), (DX, fy, D_H / 2), WHITE, rot=(0, s * diag, 0)))
    parts.append(box(f"DoorTop{f}", (D_W, 0.08, 0.17), (DX, fy, D_H - 0.085), WHITE))
    parts.append(box(f"DoorBot{f}", (D_W, 0.08, 0.17), (DX, fy, 0.085), WHITE))
# gable: red wall (a box turned 45 deg under the roof) + white roof slabs + a hay loft hatch + weathervane ball
parts.append(bbox("Gable", (0.92, 0.26, 0.92), (DX, DY, D_H), BARN_D, BARN, bev=0, rot=(0, 45, 0)))
for s in (-1, 1):
    parts.append(bbox(f"Roof{s}", (1.25, 0.5, 0.16), (DX + s * 0.45, DY, D_H + 0.38), shade(WHITE, 0.86), WHITE, bev=0,
                      rot=(0, s * 38, 0)))
parts.append(box("Hatch", (0.34, 0.34, 0.34), (DX, DY, D_H + 0.14), shade(HAY, 1.04)))
parts.append(cylinder("VanePole", 0.04, 0.26, (DX, DY, D_H + 0.66), CREAM, segs=4))
parts.append(blob("VaneBall", 0.11, (DX, DY, D_H + 0.87), BUTTER, subdiv=1, jitter=0))


# --- hay bale stacks either side of the door: two bales + one on top, twine bands, straws ---------------------
def bale(name, cx, cy, z, deg, sz=(1.0, 0.68, 0.6), tone=1.0):
    out = [bbox(name, sz, (cx, cy, z + sz[2] / 2), shade(HAY, 0.9 * tone), shade(HAY, 1.06 * tone), bev=0.05,
                rot=(0, 0, deg + 90))]
    tx, ty = tdir(deg)
    for t in (-0.25, 0.25):
        out.append(box(name + f"Tw{t}", (0.07, sz[1] + 0.04, sz[2] + 0.03), (cx + tx * t, cy + ty * t, z + sz[2] / 2), TWINE,
                       rot=(0, 0, deg + 90)))
    return out


for i, deg in enumerate((134, 46)):
    cx, cy = pol(3.22, deg)
    tx, ty = tdir(deg)
    sgn = 1 if deg > 90 else -1
    for k, (t, tone) in enumerate(((-0.53, 0.96), (0.53, 1.02))):
        parts += bale(f"Bale{i}{k}", cx + tx * t, cy + ty * t, 0, deg + R.uniform(-5, 5), tone=tone)
    parts += bale(f"BaleT{i}", cx - tx * 0.22 * sgn, cy - ty * 0.22 * sgn, 0.6, deg + 7 * sgn, tone=1.05)
    for k in range(3):
        sx, sy = cx + tx * (0.05 - 0.25 * k) * sgn, cy + ty * (0.05 - 0.25 * k) * sgn
        parts.append(tube(f"Straw{i}{k}", [(sx, sy, 1.12), (sx + tx * 0.1 * (k - 1), sy + ty * 0.1 * (k - 1), 1.5 + 0.1 * k)],
                          [0.05, 0.02], shade(HAY, 1.12), segs=3))

# --- wheelbarrow full of hay on the right (wheel toward the front) ---------------------------------------------
WD = 8
cx, cy = pol(3.22, WD)
tx, ty = tdir(WD)  # +t = toward the back (counter-clockwise)
TRAY = rgb(96, 178, 104)
parts.append(bbox("Tray", (1.15, 0.7, 0.36), (cx + tx * 0.05, cy + ty * 0.05, 0.6), shade(TRAY, 0.86), TRAY, bev=0.05, rot=(0, 0, WD + 90)))
parts.append(bbox("TrayLip", (1.25, 0.8, 0.07), (cx + tx * 0.05, cy + ty * 0.05, 0.8), shade(TRAY, 0.9), shade(TRAY, 1.08), bev=0, rot=(0, 0, WD + 90)))
parts.append(blob("BarrowHay", 0.5, (cx + tx * 0.05, cy + ty * 0.05, 0.86), HAY, subdiv=1, squash=(1.2, 0.75, 0.42), jitter=0.08, seed=4))
wx, wy = cx - tx * 0.62, cy - ty * 0.62  # wheel at the front end
parts.append(cylinder("Wheel", 0.26, 0.14, (wx, wy, 0.26), rgb(90, 84, 84), segs=10, rot=(0, 90, WD)))
parts.append(cylinder("Hub", 0.1, 0.18, (wx, wy, 0.26), BUTTER, segs=6, rot=(0, 90, WD)))
for s in (-1, 1):
    ox, oy = math.cos(math.radians(WD)) * 0.27 * s, math.sin(math.radians(WD)) * 0.27 * s
    parts.append(tube(f"Handle{s}", [(wx + ox * 0.5, wy + oy * 0.5, 0.3), (cx + tx * 0.95 + ox, cy + ty * 0.95 + oy, 0.72)], [0.045, 0.045], WOOD, segs=4))
    parts.append(box(f"BarrowLeg{s}", (0.08, 0.08, 0.42), (cx + tx * 0.45 + ox, cy + ty * 0.45 + oy, 0.21), WOOD_D))

# --- feed sack on the left: tied burlap sack with a red stripe ---------------------------------------------------
SACK = rgb(222, 196, 150)
cx, cy = pol(3.22, 174)
sack = blob("Sack", 0.42, (cx, cy, 0.48), None, subdiv=2, squash=(1.0, 0.85, 1.15), jitter=0.03, seed=7)
gradient(sack, shade(SACK, 0.86), SACK)
parts.append(sack)
parts.append(cylinder("SackTie", 0.17, 0.08, (cx, cy, 0.95), TWINE, segs=6))
parts.append(blob("SackTop", 0.2, (cx, cy, 1.07), SACK, subdiv=1, squash=(1.2, 1.2, 0.7), jitter=0.06, seed=8))
ix, iy = math.cos(math.radians(174)), math.sin(math.radians(174))
parts.append(box("SackStripe", (0.08, 0.5, 0.16), (cx - ix * 0.35, cy - iy * 0.35, 0.55), BARN, rot=(0, 0, 174)))
for k, deg in enumerate((190, 186)):  # spilled grain
    parts.append(blob(f"Grain{k}", 0.16, (*pol(3.15 + 0.2 * k, deg), 0.3), shade(BUTTER, 1.04), subdiv=1, squash=(1.4, 1, 0.5), jitter=0.05, seed=k))

# --- pitchfork leaning on the left bale stack ---------------------------------------------------------------------
fx, fy = pol(3.0, 156)
tx, ty = tdir(156)
top = (fx - tx * 0.3, fy - ty * 0.3, 1.38)
parts.append(tube("ForkHandle", [(fx, fy, 0.0), top], [0.045, 0.045], WOOD, segs=4))
parts.append(box("ForkBar", (0.36, 0.06, 0.06), top, METAL, rot=(0, 0, 156 + 90)))
for k in (-1, 0, 1):
    bx, by = top[0] + math.cos(math.radians(156 + 90)) * 0.15 * k, top[1] + math.sin(math.radians(156 + 90)) * 0.15 * k
    parts.append(cone(f"Tine{k}", 0.035, 0.42, (bx, by, top[2]), METAL, segs=4))

# --- a small chicken on the right, between the barrow and the bales ----------------------------------------------
cx, cy = pol(3.18, 30)
fx_, fy_ = math.cos(math.radians(30 + 180)), math.sin(math.radians(30 + 180))  # faces the slime
hen = blob("Hen", 0.3, (cx, cy, 0.42), WHITE, subdiv=2, squash=(1.0, 1.15, 0.9), jitter=0, rot=(0, 0, 30 + 90))
gradient(hen, shade(WHITE, 0.86), WHITE)
parts.append(hen)
hx, hy = cx + fx_ * 0.2, cy + fy_ * 0.2
parts.append(blob("HenHead", 0.17, (hx, hy, 0.72), WHITE, subdiv=1, jitter=0))
parts.append(blob("Comb", 0.09, (hx, hy, 0.89), BARN, subdiv=1, squash=(0.6, 1.2, 1), jitter=0, rot=(0, 0, 30)))
bk = cone("Beak", 0.06, 0.14, (0, 0, 0), BUTTER, segs=4)
bk.data.transform(Matrix.Translation((hx + fx_ * 0.15, hy + fy_ * 0.15, 0.72)) @ Matrix.Rotation(math.radians(30 + 180 - 90), 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "Y"))
parts.append(bk)
parts.append(blob("HenTail", 0.14, (cx - fx_ * 0.28, cy - fy_ * 0.28, 0.6), shade(WHITE, 0.94), subdiv=1, squash=(0.6, 1, 1.3), jitter=0))
for s in (-1, 1):
    lx, ly = cx + math.cos(math.radians(30 + 90)) * 0.1 * s, cy + math.sin(math.radians(30 + 90)) * 0.1 * s
    parts.append(cylinder(f"HenLeg{s}", 0.03, 0.2, (lx, ly, 0.0), BUTTER, segs=3))

# --- low post-and-rail fence round the front sides ------------------------------------------------------------
FR = 3.5
for side, degs in (("R", (-30, -9)), ("L", (210, 189))):
    for k, deg in enumerate(degs):
        x, y = pol(FR, deg)
        h = 1.0 if k == 0 else 1.15
        parts.append(bbox(f"Post{side}{k}", (0.28, 0.28, h), (x, y, h / 2), shade(FENCE, 0.85), FENCE, bev=0.03, rot=(0, 0, deg)))
        parts.append(cone(f"PostCap{side}{k}", 0.22, 0.16, (x, y, h), WHITE, segs=4, rot=(0, 0, deg + 45)))
    a0, a1 = degs[0] - 2, degs[1] + (8 if side == "R" else -8)
    for j, z in enumerate((0.42, 0.75)):
        pts = [(*pol(FR, a0 + (a1 - a0) * t / 6), z) for t in range(7)]
        parts.append(tube(f"Rail{side}{j}", pts, [0.09] * 7, FENCE, segs=4))

# --- loose hay wisps on the band (they sit on the frame top) ----------------------------------------------------
for i, deg in enumerate((112, 68, 28, 200, -18)):
    x, y = pol(3.0 + 0.4 * (i % 2), deg)
    parts.append(blob(f"Wisp{i}", 0.26, (x, y, 0.3), shade(HAY, R.uniform(0.95, 1.08)), subdiv=1,
                      squash=(1.5, 0.9, 0.5), jitter=0.06, seed=i, rot=(0, 0, deg + 90)))
theme_finish("habitat_theme_barnyard", parts)
