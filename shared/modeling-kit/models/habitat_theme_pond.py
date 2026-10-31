# habitat_theme_pond: pond-side theme layer (Bubbles, Froggo, Honey Toad). Back and sides of the rim only, no ring
# (the tier frame mesh supplies it), front arc clear for the signature prop. Reworked from habitat_syrup_pool_overlay
# but with WATER, not syrup, and nothing below the deck (drop = 0: no drips over the rim): blue-green water pools in
# pebble rims on the back and left, lily pads (one with a pink water-lily), cattails and reeds behind them, a little
# wooden dock post with a rope and a short plank on the right, and a few bubbles on the water.
import math, random
import bmesh
from mathutils import Matrix, Vector
from lib import *
from lib.shapes import obj_from_bm
from models._habitat import lathe, CREAM, P, WOOD, WOOD_D
from models._habitat_theme_rim import *

WATER, WATER_HI = rgb(52, 176, 214), rgb(120, 218, 236)
PEB, PEB_HI = rgb(150, 138, 122), rgb(190, 178, 158)  # warm river stones (pale grey read as a white ring)
PAD, PAD_D = rgb(96, 196, 84), rgb(70, 160, 72)
LILY, LILY_C = rgb(250, 150, 190), rgb(255, 214, 90)
REED, REED_D = rgb(120, 196, 90), rgb(84, 150, 74)
CATTAIL = rgb(150, 96, 58)
ROPE = rgb(232, 196, 128)
BUBBLE = rgb(214, 244, 250)
R = random.Random(5)
parts = []


def tdir(deg):
    a = math.radians(deg + 90)
    return math.cos(a), math.sin(a)


def pool(name, deg, half_t, half_r, r=3.22, z=0.47):
    """Shallow water lens on the band (stretched along the ring), a pebble rim round it."""
    x, y = pol(r, deg)
    w = lathe(name, [(0, 0.12), (0.92, 0.12), (1.0, z - 0.04), (0.94, z), (0.6, z + 0.01), (0, z + 0.01)], segs=14,
              color_fn=lambda i, k, zz: WATER_HI if i == 3 else (WATER if i >= 4 else shade(WATER, 0.8)))
    w.data.transform(Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(deg), 4, "Z") @ Matrix.Diagonal((half_r, half_t, 1, 1)))
    out = [w]
    n = 9
    for k in range(n):
        a = k / n * math.tau + 0.3
        lx, ly = half_r * 1.02 * math.cos(a), half_t * 1.02 * math.sin(a)
        c, s_ = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        px, py = x + lx * c - ly * s_, y + lx * s_ + ly * c
        size = 0.15 + 0.06 * ((k * 7) % 3) / 2
        rr = math.hypot(px, py)
        if rr < R_IN + size * 1.25:  # keep the inner stones off the slime's circle
            px, py = px * (R_IN + size * 1.25) / rr, py * (R_IN + size * 1.25) / rr
        elif rr > 3.72 - size:  # and the outer ones on the dish
            px, py = px * (3.72 - size) / rr, py * (3.72 - size) / rr
        pb = blob(f"{name}Peb{k}", size, (px, py, z - 0.08), None, subdiv=1, squash=(1.2, 1.0, 0.75), jitter=0.1, seed=k + len(name))
        gradient(pb, PEB, PEB_HI)
        out.append(pb)
    return out


def lily_pad(name, x, y, z, r, rot):
    """Flat round pad with a notch, a darker vein ring."""
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    segs, notch = 12, 1
    top = [bm.verts.new((r * math.cos(k / segs * math.tau), r * math.sin(k / segs * math.tau), 0.05)) for k in range(notch, segs + 1 - notch + 1)]
    bot = [bm.verts.new((v.co.x, v.co.y, 0)) for v in top]
    ct, cb = bm.verts.new((0, 0, 0.05)), bm.verts.new((0, 0, 0))
    ring = list(zip(top, bot))
    for (t0, b0), (t1, b1) in zip(ring, ring[1:]):
        bm.faces.new((ct, t0, t1))
        bm.faces.new((cb, b1, b0))
        bm.faces.new((t0, b0, b1, t1))
    bm.faces.new((ct, cb, bot[0], top[0]))
    bm.faces.new((ct, top[-1], bot[-1], cb))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        c = PAD if f.normal.z > 0.5 else PAD_D
        for lp in f.loops:
            lp[layer] = c
    o = obj_from_bm(name, bm)
    o.data.transform(Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(rot), 4, "Z"))
    return o


def lily(name, x, y, z):
    out = []
    for k in range(6):
        a = k * math.tau / 6
        p = blob(f"{name}P{k}", 0.17, (0, 0, 0.12), LILY if k % 2 else shade(LILY, 1.06), subdiv=1, squash=(0.55, 0.35, 1.0), jitter=0)
        p.data.transform(Matrix.Translation((x + 0.08 * math.cos(a), y + 0.08 * math.sin(a), z)) @ Matrix.Rotation(a - math.pi / 2, 4, "Z")
                         @ Matrix.Rotation(math.radians(-40), 4, "X"))
        out.append(p)
    out.append(blob(f"{name}C", 0.09, (x, y, z + 0.1), LILY_C, subdiv=1, jitter=0))
    return out


def cattail(name, x, y, h, lean=(0.0, 0.0)):
    tx, ty = x + lean[0], y + lean[1]
    out = [tube(name + "St", [(x, y, 0), (tx, ty, h)], [0.045, 0.035], REED_D, segs=4)]
    out.append(cylinder(name + "Head", 0.09, 0.38, (x + lean[0] * 0.85, y + lean[1] * 0.85, h * 0.85 - 0.1), CATTAIL, segs=6))
    return out


def reed(name, x, y, h, lean):
    return tube(name, [(x, y, 0), (x + lean[0] * 0.5, y + lean[1] * 0.5, h * 0.6), (x + lean[0], y + lean[1], h)],
                [0.08, 0.05, 0.015], REED, segs=3)


# --- back pool with lily pads and a water-lily, cattails and reeds behind ----------------------------------------
parts += pool("PoolB", 90, 1.35, 0.55, r=3.2)
bx, by = pol(3.2, 90)
parts.append(lily_pad("PadB0", bx - 0.55, by - 0.05, 0.49, 0.36, 30))
parts.append(lily_pad("PadB1", bx + 0.55, by + 0.05, 0.49, 0.26, 200))
parts += lily("LilyB", bx - 0.55, by - 0.05, 0.54)
for k, (deg, h, lean) in enumerate(((104, 2.1, 0.12), (93, 2.45, -0.06), (82, 1.85, -0.15), (113, 1.5, 0.2))):
    x, y = pol(3.6, deg)
    tx, ty = tdir(deg)
    parts += cattail(f"Cat{k}", x, y, h, lean=(tx * lean, ty * lean))
for k, (deg, h, lean) in enumerate(((98, 1.7, 0.3), (87, 1.4, -0.35), (75, 1.2, -0.3), (110, 1.25, 0.35), (70, 0.9, -0.2))):
    x, y = pol(3.62, deg)
    tx, ty = tdir(deg)
    parts.append(reed(f"Reed{k}", x, y, h, (tx * lean, ty * lean)))

# --- left pool with a pad, reeds on the front end ---------------------------------------------------------------
parts += pool("PoolL", 160, 0.95, 0.5, r=3.2)
lx, ly = pol(3.2, 160)
parts.append(lily_pad("PadL", lx, ly, 0.42, 0.3, 120))
for k, (deg, h, lean) in enumerate(((186, 1.3, -0.2), (193, 1.0, 0.25), (180, 0.95, -0.3))):
    x, y = pol(3.4, deg)
    tx, ty = tdir(deg)
    parts.append(reed(f"ReedL{k}", x, y, h, (tx * lean, ty * lean)))
parts += cattail("CatL", *pol(3.45, 189), 1.45, lean=(0.05, 0.08))

# --- right: wooden dock post with rope wraps and a short plank, a small pool ------------------------------------
dx, dy = pol(3.3, 22)
post = cylinder("DockPost", 0.22, 1.35, (dx, dy, 0), WOOD, segs=7)
gradient(post, WOOD_D, shade(WOOD, 1.06))
parts.append(post)
parts.append(cylinder("PostTop", 0.2, 0.06, (dx, dy, 1.35), mix(WOOD, CREAM, 0.4), segs=7))
for k, z in enumerate((0.75, 0.88)):
    parts.append(cylinder(f"Wrap{k}", 0.25, 0.09, (dx, dy, z), ROPE, segs=7))
tx, ty = tdir(22)
rope = [(dx - tx * 0.2, dy - ty * 0.2, 0.8), (dx - tx * 0.45, dy - ty * 0.45, 0.5), (dx - tx * 0.6, dy - ty * 0.6, 0.32)]
parts.append(tube("RopeEnd", rope, [0.06, 0.06, 0.05], ROPE, segs=4))
for k, (deg, r) in enumerate(((2, 3.2), (-12, 3.25))):  # two planks of a little dock, lying on the band
    x, y = pol(r, deg)
    pl = box(f"Plank{k}", (0.95, 0.36, 0.12), (x, y, 0.4), WOOD, rot=(0, 0, deg + R.uniform(-8, 8)))
    gradient(pl, shade(WOOD, 0.9), shade(WOOD, 1.05))
    parts.append(pl)
for k, deg in enumerate((-5, 9)):
    x, y = pol(3.65, deg)
    parts.append(cylinder(f"Stilt{k}", 0.08, 0.42, (x, y, 0), WOOD_D, segs=5))
parts += pool("PoolR", 50, 0.6, 0.42, r=3.22)
parts.append(lily_pad("PadR", *pol(3.22, 52), 0.49, 0.24, 300))
# reed tufts between the pools so the bank reads as one shore
for k, (deg, h, lean) in enumerate(((128, 1.25, 0.2), (133, 0.9, -0.2), (64, 1.1, -0.2), (36, 0.8, 0.2))):
    x, y = pol(3.55, deg)
    tx, ty = tdir(deg)
    parts.append(reed(f"ReedM{k}", x, y, h, (tx * lean, ty * lean)))
parts += cattail("CatM", *pol(3.55, 131), 1.6, lean=(-0.05, 0.05))

# --- bubbles on the water (Bubbles' calling card) ----------------------------------------------------------------
for k, (deg, r, size, z) in enumerate(((84, 3.05, 0.14, 0.6), (88, 3.15, 0.09, 0.74), (152, 3.1, 0.11, 0.58), (50, 3.2, 0.1, 0.58))):
    x, y = pol(r, deg)
    parts.append(blob(f"Bubble{k}", size, (x, y, z), BUBBLE, subdiv=1, jitter=0))
theme_finish("habitat_theme_pond", parts)
