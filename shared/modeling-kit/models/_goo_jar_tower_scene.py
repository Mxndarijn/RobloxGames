# Design preview (not an asset): the goo jar tower base at version JAR_V (1..4), open or locked (JAR_LOCKED=1).
# Every floor is a glass jar: a goo pool floor with 8 lily-pad pads round a central spiral stair, a see-through
# glass wall (rbx_transparency, like a Roblox Glass part), a tapered shoulder and a threaded brass neck; the next jar
# stands on the lid. The only way in is the round door in jar 1; the way out is the goo slide from the top jar.
# The lock is a giant cork stopper: parked beside the door while open, plugging it while locked (red ring lit).
# True scale in studs, entrance at -Y, plot 80 x 80. The plot colour in this preview is lilac.
import math
import os
import random

import bpy

from lib import *
from models._phoenix_ranch import bbox

P = PALETTE
V = int(os.environ.get("JAR_V", "4"))
LOCKED = os.environ.get("JAR_LOCKED", "0") == "1"
FLOOR_H = 16.0
RADII = [31.0, 26.0, 21.5, 17.5]
WOOD, WOOD_D, CREAM = P["ranch_wood"], P["ranch_wood_dark"], P["ranch_cream"]
GOO, GOO_HI, METAL = P["ranch_goo"], P["ranch_goo_hi"], P["ranch_metal"]
PINK, LILAC, BUTTER, ROOF = P["ranch_pink"], P["ranch_lilac"], P["ranch_butter"], P["ranch_roof"]
FIELD, FIELD_L, PATH = P["ranch_field"], P["ranch_field_light"], P["ranch_path"]
GLASS = rgb(200, 240, 244)
TOP_NECK = 0.55  # the top jar's neck, as a share of its radius
CORK = rgb(214, 170, 116)
TRIM = mix(LILAC, CREAM, 0.15)
SLIME_COLS = [PINK, LILAC, BUTTER, GOO, rgb(120, 190, 250), rgb(250, 160, 90)]
R = random.Random(5)
solid, glass = [], []


def top(f):
    return 1.0 + (f - 1) * FLOOR_H


def add(o, lo=None, hi=None, into=None):
    if lo is not None:
        gradient(o, lo, hi)
    (solid if into is None else into).append(o)
    return o


def ring_xy(n, radius, phase=0.0):
    return [(radius * math.cos(phase + k * math.tau / n), radius * math.sin(phase + k * math.tau / n)) for k in range(n)]


def teardrop(name, x, y, z_top, length, thick):
    """A drip that stretches out of the goo above it: a tapering neck into a round drop (no loose bulbs)."""
    neck = [(x, y, z_top + thick * 0.3), (x, y, z_top - length * 0.45), (x, y, z_top - length)]
    add(tube(name, neck, [thick * 0.8, thick * 0.38, thick * 0.42], GOO, segs=8), shade(GOO, 0.9), GOO)
    add(blob(name + "Tip", thick * 0.58, (x, y, z_top - length - thick * 0.25), GOO, subdiv=2, squash=(1, 1, 1.15), jitter=0))


def stand(name, x, y, z):
    """The slime stand: a cork pedestal with a brass band, a dish rimmed in the plot colour and a goo bed the slime sits
    in. Seat at z + 2.4 like the game's pads (PAD_SEAT_Y)."""
    add(cylinder(name + "Foot", 3.9, 0.5, (x, y, z), shade(CORK, 0.85), segs=18), shade(CORK, 0.75), shade(CORK, 0.85))
    add(cylinder(name + "Body", 3.3, 1.5, (x, y, z + 0.5), CORK, segs=18, r_top=3.0), shade(CORK, 0.8), CORK)
    add(cylinder(name + "Band", 3.25, 0.4, (x, y, z + 0.9), METAL, segs=18))
    add(cylinder(name + "Dish", 3.0, 0.4, (x, y, z + 2.0), TRIM, segs=18, r_top=3.7), shade(TRIM, 0.9), TRIM)
    add(cylinder(name + "Bed", 3.0, 0.12, (x, y, z + 2.32), GOO_HI, segs=18))


def slime(x, y, z, k, r=1.7):
    col = SLIME_COLS[k % len(SLIME_COLS)]
    add(blob(f"Slime{x}{y}{z}", r, (x, y, z + r * 0.78), col, subdiv=2, squash=(1, 1, 0.78), jitter=0.02), shade(col, 0.82), col)


# Foot: a round cork-and-wood plinth, a goo moat round it, a plank bridge over the moat to the door.
r1 = RADII[0]
add(cylinder("Foot", r1 + 3.5, 1.0, (0, 0, 0), WOOD, segs=48), shade(WOOD, 0.85), WOOD)
moat = shade(GOO_HI, 1.0) if LOCKED else GOO
add(cylinder("MoatBed", r1 + 7.5, 0.4, (0, 0, 0), shade(PATH, 0.95), segs=48))
add(cylinder("Moat", r1 + 7.0, 0.7, (0, 0, 0.05), moat, segs=48))
add(bbox("Bridge", (9, 9, 0.8), (0, -(r1 + 6.0), 1.2), shade(WOOD, 0.88), WOOD, bev=0.15))
for s in (-1, 1):
    add(bbox(f"BridgeRail{s}", (0.6, 9, 0.6), (s * 4.3, -(r1 + 6.0), 2.6), shade(WOOD_D, 0.9), WOOD_D, bev=0.08))

for f in range(1, V + 1):
    r = RADII[f - 1]
    z = top(f)
    neck = (RADII[f] - 0.6) if f < V else r * TOP_NECK
    # floor: goo pool on a wooden base, the glass rounding in under it
    add(cylinder(f"Ring{f}", r - 1.2, 1.0, (0, 0, z - 1.0), WOOD_D, segs=48), shade(WOOD_D, 0.9), WOOD_D)
    add(cylinder(f"Pool{f}", r - 0.4, 0.5, (0, 0, z - 0.45), GOO, segs=48), shade(GOO, 0.85), GOO)
    add(cylinder(f"GlassBase{f}", r - 1.8, 1.4, (0, 0, z - 1.2), GLASS, segs=48, r_top=r, cap=False), into=glass)
    # glass: straight wall, then a round two-step shoulder in to the neck (see-through)
    wall_h = 9.0
    sh = r - (r - neck) * 0.38
    add(cylinder(f"Glass{f}", r, wall_h, (0, 0, z + 0.2), GLASS, segs=48, cap=False), into=glass)
    add(cylinder(f"Shoulder{f}", r, 2.0, (0, 0, z + 0.2 + wall_h), GLASS, segs=48, r_top=sh, cap=False), into=glass)
    add(cylinder(f"ShoulderTop{f}", sh, 1.6, (0, 0, z + 2.2 + wall_h), GLASS, segs=48, r_top=neck, cap=False), into=glass)
    # brass ribs on the wall, threaded neck bands, the cork lid the next jar sits in
    for k, (x, y) in enumerate(ring_xy(8, r + 0.15, math.pi / 8)):
        add(cylinder(f"Rib{f}{k}", 0.35, wall_h, (x, y, z + 0.2), METAL, segs=6))
        ux, uy = x / (r + 0.15), y / (r + 0.15)
        wt = z + 0.2 + wall_h
        add(tube(f"RibTop{f}{k}", [(ux * (r + 0.15), uy * (r + 0.15), wt), (ux * (sh + 0.15), uy * (sh + 0.15), wt + 2.0),
                                   (ux * (neck + 0.2), uy * (neck + 0.2), wt + 3.6)], [0.35, 0.35, 0.35], METAL, segs=6))
    neck_z = z + 3.8 + wall_h
    for k in range(2):
        add(cylinder(f"Thread{f}{k}", neck + 0.6, 0.45, (0, 0, neck_z + 0.2 + k * 0.7), METAL, segs=40))
    lid_z = neck_z + 1.6
    if f < V or V >= 4:
        add(cylinder(f"Lid{f}", neck + 0.3, 1.6, (0, 0, neck_z), CORK, segs=40), shade(CORK, 0.85), CORK)
    else:  # the top jar while growing: a tall cork stopper, wider at the top
        add(cylinder(f"Lid{f}", neck + 0.2, 3.2, (0, 0, neck_z), CORK, segs=40, r_top=neck + 1.0), shade(CORK, 0.8), CORK)
        add(cylinder(f"LidRing{f}", neck + 1.1, 0.5, (0, 0, neck_z + 2.4), shade(CORK, 0.88), segs=40))
    # jam-jar label in the plot colour; jar 1's label is the owner's name board, front-left so the door stays clear
    ang = math.radians(-126 if f == 1 else -90)
    nx, ny = math.cos(ang), math.sin(ang)
    tx, ty = -ny, nx
    lw = r * (0.6 if f == 1 else 0.5)
    lz = z + (5.4 if f == 1 else 4.5)
    lh = 3.6 if f == 1 else 2.8
    turn = (0, 0, math.degrees(ang) + 90)
    add(bbox(f"Label{f}", (lw, 0.5, lh), (nx * (r + 0.35), ny * (r + 0.35), lz), shade(CREAM, 0.95), CREAM, bev=0.15, rot=turn))
    add(bbox(f"LabelBand{f}", (lw + 0.3, 0.6, 0.9), (nx * (r + 0.4), ny * (r + 0.4), lz + lh / 2 + 0.2), shade(TRIM, 0.9), TRIM,
             bev=0.1, rot=turn))
    if f == 1:
        for k, x in enumerate((-4.5, -2.5, -0.5, 1.5, 3.5)):
            add(bbox(f"Letter{k}", (1.2, 0.3, 1.8), (nx * (r + 0.65) + tx * x, ny * (r + 0.65) + ty * x, lz - 0.2), shade(WOOD_D, 0.9),
                     WOOD_D, bev=0.05, rot=turn))
    else:
        for k in range(f):
            x = (k - (f - 1) / 2) * 1.6
            add(blob(f"FloorDot{f}{k}", 0.55, (nx * (r + 0.7) + tx * x, ny * (r + 0.7) + ty * x, lz - 0.3), GOO, subdiv=1,
                     squash=(1, 1, 1), jitter=0))
    # lily-pad pads round the stair, slimes on most of them
    for k, (x, y) in enumerate(ring_xy(8, r * 0.6, math.pi / 8)):
        stand(f"Stand{f}{k}", x, y, z)
        if R.random() < 0.85:
            slime(x, y, z + 2.3, f * 8 + k)
    # central spiral stair up through the lid hatch
    add(cylinder(f"StairPost{f}", 1.8, FLOOR_H, (0, 0, z), WOOD_D, segs=16), shade(WOOD_D, 0.9), WOOD_D)
    if f < V:
        for k in range(9):
            a = k / 9 * math.tau * 0.95 + f
            add(bbox(f"Tread{f}{k}", (5.0, 2.2, 0.5), (3.5 * math.cos(a), 3.5 * math.sin(a), z + 1.4 + k * 1.45), shade(WOOD, 0.9), WOOD,
                     bev=0.08, rot=(0, 0, math.degrees(a))))

EYE_W, EYE_D = rgb(246, 250, 250), rgb(56, 42, 38)


def face(x, y, z, size, facing=-90.0):
    """Two big eyes, pupils and pink cheeks on the -Y (front) side of a slime of radius `size` centred at x, y, z."""
    a = math.radians(facing)
    nx, ny = math.cos(a), math.sin(a)
    tx, ty = -ny, nx
    for s in (-1, 1):
        ex, ey = x + nx * size * 0.86 + tx * s * size * 0.34, y + ny * size * 0.86 + ty * s * size * 0.34
        add(blob(f"Eye{s}{z}", size * 0.2, (ex, ey, z + size * 0.15), EYE_W, subdiv=2, squash=(1, 0.6, 1.15), jitter=0))
        add(blob(f"Pupil{s}{z}", size * 0.11, (ex + nx * size * 0.1, ey + ny * size * 0.1, z + size * 0.12), EYE_D, subdiv=2,
                 squash=(1, 0.6, 1.2), jitter=0))
        add(blob(f"Cheek{s}{z}", size * 0.12, (x + nx * size * 0.8 + tx * s * size * 0.58, y + ny * size * 0.8 + ty * s * size * 0.58,
                                                  z - size * 0.12), PINK, subdiv=1, squash=(1, 0.4, 0.7), jitter=0))


def spill(name, radius, z_rim, thick, drops, seed):
    """A roll of goo oozing round a rim at height z_rim, with drops of uneven length hanging from it."""
    ring = [(radius * math.cos(k / 40 * math.tau), radius * math.sin(k / 40 * math.tau), z_rim) for k in range(41)]
    add(tube(name, ring, [thick] * len(ring), GOO, segs=8, seed=seed, jitter=0.12), shade(GOO, 0.9), GOO_HI)
    rr = random.Random(seed)
    for k in range(drops):
        a = rr.uniform(0, math.tau)
        long = rr.uniform(1.0, 2.6)
        teardrop(f"{name}Drop{k}", (radius + thick * 0.35) * math.cos(a), (radius + thick * 0.35) * math.sin(a), z_rim - thick * 0.3,
                 long, thick)


# Goo oozes out from under every jar's lid (the next jar squeezes it), with drops down the shoulder.
for f in range(1, V + 1):
    neck = (RADII[f] - 0.6) if f < V else RADII[f - 1] * TOP_NECK
    lid_top = top(f) + 3.8 + 9.0 + (1.6 if (f < V or V >= 4) else 3.2)
    spill(f"Ooze{f}", neck + 0.6, lid_top - (0.4 if f < V else 0.2), 1.0 + 0.15 * f, 7 + f, seed=40 + f)

# Slime on the glass and in the pools: goo smears stuck on the outside of every jar (never over the door or labels),
# bubbles rising in the pools.
for f in range(1, V + 1):
    r = RADII[f - 1]
    rr = random.Random(70 + f)
    for k in range(2):
        deg = rr.choice([rr.uniform(-40, 50), rr.uniform(130, 220)])
        a = math.radians(deg)
        add(blob(f"Smear{f}{k}", rr.uniform(1.0, 1.6), ((r + 0.3) * math.cos(a), (r + 0.3) * math.sin(a), top(f) + rr.uniform(2.5, 7.5)),
                 mix(GOO, GOO_HI, 0.5), subdiv=2, squash=(1.3, 0.3, 1.1), jitter=0.05, rot=(0, 0, deg + 90)))
    for k in range(7):
        a, d = rr.uniform(0, math.tau), rr.uniform(6, r - 3)
        add(blob(f"Bubble{f}{k}", rr.uniform(0.35, 0.8), (d * math.cos(a), d * math.sin(a), top(f) + 0.2), GOO_HI, subdiv=1,
                 squash=(1, 1, 0.8), jitter=0))

# The mascot: a big slime sits on the top lid and grows with the version; at version 4 it wears a little crown.
neck_top = RADII[V - 1] * TOP_NECK
crown_z = top(V) + 3.8 + 9.0 + (1.6 if V >= 4 else 3.2)
size = 3.4 + 1.3 * V
body = blob("Mascot", size, (0, 0, crown_z + size * 0.72), GOO, subdiv=3, squash=(1, 1, 0.78), jitter=0.015, lumps=0.05)
add(body, shade(GOO, 0.82), mix(GOO, GOO_HI, 0.45))
add(blob("MascotShine", size * 0.22, (-size * 0.35, -size * 0.45, crown_z + size * 1.15), GOO_HI, subdiv=2, squash=(1, 0.5, 0.7), jitter=0))
face(0, 0, crown_z + size * 0.72, size)
add(cylinder("MascotPuddle", size * 1.05, 0.5, (0, 0, crown_z - 0.1), GOO, segs=24, jitter=0.08, seed=9))
if V >= 4:
    cz = crown_z + size * 1.45
    add(cylinder("Crown", size * 0.36, size * 0.18, (0, 0, cz), BUTTER, segs=12))
    for k, (x, y) in enumerate(ring_xy(5, size * 0.33)):
        add(cone(f"CrownPt{k}", size * 0.1, size * 0.3, (x, y, cz + size * 0.16), BUTTER, segs=5))
        add(blob(f"CrownGem{k}", size * 0.05, (x, y, cz + size * 0.47), PINK, subdiv=1, jitter=0))

# Way out: a glass drop tube full of goo runs straight down the BACK of the tower (the front with the door and labels
# stays clear). It hugs each jar's wall and curves in over the shoulders, has a cork hatch on every jar above the
# ground floor, and bends out at the bottom into a splash pool behind the moat.
def tube_radius(z):
    f = max(1, min(V, int((z - 1.0) // FLOOR_H) + 1))
    h = z - top(f)
    here = RADII[f - 1] + 3.0
    if f < V and h > 9.2:
        t = min(1.0, (h - 9.2) / 6.8)
        t = t * t * (3 - 2 * t)
        return here + (RADII[f] + 3.0 - here) * t
    return here


if V >= 2:
    BACK = math.radians(70)
    cb, sb = math.cos(BACK), math.sin(BACK)
    z_hi = top(V) + 7.5
    pts = []
    for i in range(61):
        z = z_hi + (3.0 - z_hi) * i / 60
        rad = tube_radius(z)
        pts.append((rad * cb, rad * sb, z))
    for k, (d, zz) in enumerate(((3.0, 1.9), (6.0, 1.4), (9.0, 1.2))):
        rad = RADII[0] + 3.0 + d
        pts.append((rad * cb, rad * sb, zz))
    add(tube("DropGlass", pts, [2.3] * len(pts), GLASS, segs=12), into=glass)
    add(tube("DropGoo", pts, [1.6] * len(pts), GOO, segs=10), shade(GOO, 0.85), GOO_HI)
    for f in range(2, V + 1):
        r = RADII[f - 1]
        hz = top(f) + 4.0
        add(cylinder(f"Hatch{f}", 2.6, 0.9, ((r + 0.2) * cb, (r + 0.2) * sb, hz - 2.6), CORK, segs=14, rot=(0, 0, 0)))
        add(cylinder(f"Collar{f}", 2.7, 0.8, (tube_radius(hz) * cb, tube_radius(hz) * sb, hz), METAL, segs=14))
    add(cylinder("TopCollar", 2.7, 0.8, (pts[0][0], pts[0][1], pts[0][2] - 0.4), CORK, segs=14))
    ex, ey, _ = pts[-1]
    add(blob("SplashPool", 4.0, (ex * 1.06, ey * 1.06, 0.9), GOO, subdiv=2, squash=(1.3, 1.3, 0.28), jitter=0.06), shade(GOO, 0.9), GOO_HI)
    for k, (x, y) in enumerate(ring_xy(5, 4.6, 0.3)):
        add(blob(f"Splat{k}", 0.8, (ex * 1.06 + x, ey * 1.06 + y, 1.0), GOO_HI, subdiv=1, jitter=0.1))

# The door and the lock. Round wooden frame with a brass ring; the cork stopper plugs it while locked.
dy = -r1 - 0.3
def loop(name, radius, thick, y, col):
    pts = [(radius * math.cos(k / 28 * math.tau), y, 5.6 + radius * math.sin(k / 28 * math.tau)) for k in range(29)]
    return add(tube(name, pts, [thick] * len(pts), col, segs=8))


add(cylinder("DoorHole", 4.6, 0.6, (0, dy - 0.1, 5.6), rgb(72, 52, 40), segs=24, rot=(90, 0, 0)))
loop("DoorFrame", 5.0, 0.9, dy - 0.9, WOOD_D)
arc = [(5.0 * math.cos(math.radians(d)), dy - 1.55, 5.6 + 5.0 * math.sin(math.radians(d))) for d in range(25, 160, 9)]
add(tube("DoorOoze", arc, [0.75] * len(arc), GOO, segs=8, seed=3, jitter=0.12), shade(GOO, 0.9), GOO_HI)
ring_col = rgb(240, 70, 60) if LOCKED else METAL
loop("DoorRing", 6.1, 0.45, dy - 1.3, ring_col)
add(bbox("DoorSill", (11, 2.4, 1.2), (0, dy - 1.0, 0.6), shade(WOOD, 0.9), WOOD, bev=0.15))
if LOCKED:
    plug = (0, dy - 0.6, 5.6)
else:
    plug = (8.5, dy - 3.8, 4.6)
add(cylinder("Stopper", 4.6, 3.4, plug, CORK, segs=24, r_top=4.2, rot=(90, 0, 0)), shade(CORK, 0.85), CORK)
add(cylinder("StopperBand", 4.7, 0.6, (plug[0], plug[1] - 1.2, plug[2]), ring_col, segs=24, rot=(90, 0, 0)))
add(blob("StopperGrip", 1.4, (plug[0], plug[1] - 3.6, plug[2]), METAL, subdiv=2, squash=(1, 0.6, 1), jitter=0))
if not LOCKED:
    add(bbox("StopperArm", (8.5, 0.8, 0.8), (4.25, dy - 2.2, 4.6), shade(METAL, 0.9), METAL, bev=0.1))
# Lock button: a red goo button on a cork pedestal by the bridge.
add(cylinder("LockPed", 2.0, 3.2, (9.0, -(r1 + 9.5), 0), CORK, segs=16), shade(CORK, 0.85), CORK)
add(blob("LockBtn", 1.6, (9.0, -(r1 + 9.5), 3.4), rgb(240, 70, 60), subdiv=2, squash=(1, 1, 0.55), jitter=0))

# Join into the solid mesh and the glass mesh; the glass previews as a transparent part.
mat = vcol_material("jar_vcol")
for name, objs, t in (("goo_jar_tower", solid, None), ("goo_jar_tower_glass", glass, 0.8)):
    o = join(name, objs)
    apply_transforms(o)
    o.data.materials.clear()
    o.data.materials.append(mat)
    if "Col" in o.data.color_attributes:
        o.data.color_attributes.active_color = o.data.color_attributes["Col"]
    if t:
        o["rbx_transparency"] = t
    o.rotation_euler.z = math.radians(float(os.environ.get("JAR_TURN", "-20")))
