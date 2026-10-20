# Goo jar tower kit pieces (not an asset by itself): every builder here makes one game mesh of the Steal a Slime jar
# tower, to the game's own numbers (inputs/goo_jar_dims.json, written by games/steal-a-slime/scripts/export-jar-dims).
# The thin models/goo_jar_*.py scripts each build one piece and finish() it; models/_goo_jar_assembled.py places all
# of them where the game puts them, so the preview and the game share one source. 1 BU = 1 stud, Z up, front -Y
# (game plot-local: blender (x, y, z) = game (x, z, y), the door at -Y). Jar pieces are built round the jar's axis
# with their floor at z = 0.
import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Vector

from lib import *

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(os.path.join(KIT, "inputs", "goo_jar_dims.json")) as fh:
    D = json.load(fh)

P = PALETTE
WOOD, WOOD_D, CREAM = P["ranch_wood"], P["ranch_wood_dark"], P["ranch_cream"]
GOO, GOO_HI, METAL = P["ranch_goo"], P["ranch_goo_hi"], P["ranch_metal"]
PINK, LILAC, BUTTER = P["ranch_pink"], P["ranch_lilac"], P["ranch_butter"]
PATH = P["ranch_path"]
GLASS = rgb(200, 240, 244)
CORK = rgb(214, 170, 116)
RED = rgb(240, 70, 60)
TRIM = mix(LILAC, CREAM, 0.15)
EYE_W, EYE_D = rgb(246, 250, 250), rgb(56, 42, 38)

FLOOR_H = D["floorHeight"]
FLOORS = len(D["floors"])
SHAPE = D["jarShape"]
WALL_H = SHAPE["wall"]  # straight glass above the floor, then the shoulder
SHOULDER = tuple(SHAPE["shoulder"])  # the two shoulder steps' heights
NECK_Z = 0.2 + WALL_H + sum(SHOULDER)  # top of the shoulder, bottom of the neck/lid
TOP_NECK = SHAPE["topNeck"]  # the top jar's neck, as a share of its radius
CORK_H, LID_H = SHAPE["cork"], SHAPE["lid"]
SEGS = 48


def radius(f):
    return D["floors"][f - 1]["radius"]


def neck(f, top):
    """Neck radius of jar f: the next jar's radius (it stands on this lid) or, for the top jar, a narrow neck."""
    return radius(f) * TOP_NECK if top or f >= FLOORS else radius(f + 1) - 0.6


def door_half_angle():
    return math.degrees(math.asin((D["door"]["width"] / 2 + 0.3) / radius(1)))


def ring_xy(n, r, phase=0.0):
    return [(r * math.cos(phase + k * math.tau / n), r * math.sin(phase + k * math.tau / n)) for k in range(n)]


def painted(o, lo=None, hi=None):
    if lo is not None:
        gradient(o, lo, hi)
    return o


# --- Lathe: a profile of (r, z) points turned round the Z axis over an angle range, double-sided. -----------------
def lathe(name, profile, color, a0=0.0, a1=360.0, segs=SEGS, thick=0.15, double=True):
    """Outer surface from `profile`, inner surface `thick` inside it with flipped faces, so glass shows from inside
    too (Roblox culls back faces). Open edges at a partial sweep are fine (decor, the collider is a primitive).
    double=False: one surface only (flat floors). A face looks to the right of the profile's direction: a profile
    going up faces out, one going inwards (towards the axis) faces up."""
    bm = bmesh.new()
    full = abs(a1 - a0) >= 359.999
    n = segs if full else max(2, int(segs * abs(a1 - a0) / 360) + 1)
    rings = []
    for side, off in ((0, 0.0), (1, -thick))[: 2 if double else 1]:
        grid = []
        for i in range(n + (0 if full else 1)):
            a = math.radians(a0 + (a1 - a0) * i / n)
            grid.append([bm.verts.new((max(0.01, r + off) * math.cos(a), max(0.01, r + off) * math.sin(a), z)) for r, z in profile])
        rings.append(grid)
    for side, grid in enumerate(rings):
        cols = len(grid)
        for i in range(cols if full else cols - 1):
            ca, cb = grid[i], grid[(i + 1) % cols]
            for j in range(len(profile) - 1):
                quad = (ca[j], cb[j], cb[j + 1], ca[j + 1])
                bm.faces.new(quad if side == 0 else tuple(reversed(quad)))
    bmesh.ops.recalc_face_normals(bm, faces=[])  # keep our winding: outer faces out, inner faces in
    return obj_from_bm(name, bm, color)


def loop(name, r, thick, center, normal_axis, col, segs=28, arc=(0.0, 360.0)):
    """A tube bent into a circle (or an arc) of radius r round `center`, in the plane normal to axis 'x', 'y' or 'z'."""
    pts = []
    a0, a1 = arc
    n = segs if arc == (0.0, 360.0) else max(3, int(segs * (a1 - a0) / 360))
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        u, v = r * math.cos(a), r * math.sin(a)
        cx, cy, cz = center
        pts.append({"x": (cx, cy + u, cz + v), "y": (cx + u, cy, cz + v), "z": (cx + u, cy + v, cz)}[normal_axis])
    return tube(name, pts, [thick] * len(pts), col, segs=8)


def teardrop(name, x, y, z_top, length, thick):
    """A drip that stretches out of the goo above it: a tapering neck into a round drop (no loose bulbs)."""
    parts = [painted(tube(name, [(x, y, z_top + thick * 0.3), (x, y, z_top - length * 0.45), (x, y, z_top - length)],
                          [thick * 0.8, thick * 0.38, thick * 0.42], GOO, segs=8), shade(GOO, 0.9), GOO)]
    parts.append(blob(name + "Tip", thick * 0.58, (x, y, z_top - length - thick * 0.25), GOO, subdiv=2, squash=(1, 1, 1.15), jitter=0))
    return parts


def ooze(name, r, z_rim, thick, drops, seed):
    """A roll of goo oozing round a rim at height z_rim, with drops of uneven length hanging from it."""
    ring = [(r * math.cos(k / 48 * math.tau), r * math.sin(k / 48 * math.tau), z_rim) for k in range(49)]
    out = [painted(tube(name, ring, [thick] * len(ring), GOO, segs=8, seed=seed, jitter=0.12), shade(GOO, 0.9), GOO_HI)]
    rr = random.Random(seed)
    for k in range(drops):
        a = rr.uniform(0, math.tau)
        out += teardrop(f"{name}Drop{k}", (r + thick * 0.35) * math.cos(a), (r + thick * 0.35) * math.sin(a), z_rim - thick * 0.3,
                        rr.uniform(1.0, 2.6), thick)
    return out


# --- Pieces --------------------------------------------------------------------------------------------------------
def jar_glass(f, top):
    """Jar f's glass shell from just under its floor to its neck: a rounded glass foot, the straight wall (jar 1 with
    the door cut out below the door's top), and the two-step shoulder. Material Glass in the game (MeshMaterial)."""
    r, nk = radius(f), neck(f, top)
    sh = r - (r - nk) * 0.38
    door_top = D["door"]["height"]
    lower = [(r - 1.8, -1.2), (r, 0.2)]
    if f == 1:
        ha = door_half_angle()
        parts = [lathe("GlassFoot", lower, GLASS),
                 lathe("GlassLow", [(r, 0.2), (r, door_top)], GLASS, a0=-90 + ha, a1=270 - ha),
                 lathe("GlassHigh", [(r, door_top), (r, 0.2 + WALL_H), (sh, 0.2 + WALL_H + SHOULDER[0]), (nk, NECK_Z)], GLASS)]
    else:
        parts = [lathe("Glass", lower + [(r, 0.2 + WALL_H), (sh, 0.2 + WALL_H + SHOULDER[0]), (nk, NECK_Z)], GLASS)]
    return parts


def jar_trim(f, top, crown=False):
    """Jar f's opaque trim: brass ribs up the wall and over the shoulder, the threaded neck, the cork lid (a band the
    next jar stands in, or the top jar's tall stopper / flat crown lid), goo oozing from under the lid with teardrop
    drips, goo smears on the glass, and (above floor 1) the jam-jar label in the plot colour with goo floor dots."""
    r, nk = radius(f), neck(f, top)
    sh = r - (r - nk) * 0.38
    wt = 0.2 + WALL_H
    out = []
    ha = door_half_angle() if f == 1 else 0
    for k, (x, y) in enumerate(ring_xy(8, r + 0.15, math.pi / 8)):
        a = math.degrees(math.atan2(y, x))
        if f == 1 and abs(((a + 90 + 180) % 360) - 180) < ha + 2:
            continue  # no rib over the door
        ux, uy = x / (r + 0.15), y / (r + 0.15)
        out.append(cylinder(f"Rib{k}", 0.35, WALL_H, (x, y, 0.2), METAL, segs=6))
        out.append(tube(f"RibTop{k}", [(ux * (r + 0.15), uy * (r + 0.15), wt), (ux * (sh + 0.15), uy * (sh + 0.15), wt + SHOULDER[0]),
                                       (ux * (nk + 0.2), uy * (nk + 0.2), NECK_Z)], [0.35] * 3, METAL, segs=6))
    for k in range(2):
        out.append(cylinder(f"Thread{k}", nk + 0.6, 0.45, (0, 0, NECK_Z + 0.2 + k * 0.7), METAL, segs=SEGS))
    if top and not crown:  # the top jar while growing: a tall cork stopper, wider at the top
        out.append(painted(cylinder("Cork", nk + 0.2, CORK_H, (0, 0, NECK_Z), CORK, segs=SEGS, r_top=nk + 1.0), shade(CORK, 0.8), CORK))
        out.append(cylinder("CorkRing", nk + 1.1, 0.5, (0, 0, NECK_Z + CORK_H - 0.8), shade(CORK, 0.88), segs=SEGS))
        lid_top = NECK_Z + CORK_H
    elif top:  # the crowned top jar: a flat cork lid the mascot sits on
        out.append(painted(cylinder("Lid", nk + 0.3, LID_H, (0, 0, NECK_Z), CORK, segs=SEGS), shade(CORK, 0.85), CORK))
        lid_top = NECK_Z + LID_H
    else:  # a cork ring the next jar stands in (its deck covers the middle, the stair comes up through it)
        inner = radius(f + 1) - 1.2
        out.append(painted(lathe("Lid", [(nk + 0.3, NECK_Z), (nk + 0.3, NECK_Z + LID_H), (inner, NECK_Z + LID_H)], CORK, double=False),
                           shade(CORK, 0.85), CORK))
        lid_top = NECK_Z + LID_H
    out += ooze("Ooze", nk + 0.6, lid_top - (0.4 if not top else 0.2), 1.0 + 0.15 * f, 7 + f, seed=40 + f)
    rr = random.Random(70 + f)
    for k in range(2):
        deg = rr.choice([rr.uniform(-40, 50), rr.uniform(130, 220)])
        a = math.radians(deg)
        out.append(blob(f"Smear{k}", rr.uniform(1.0, 1.6), ((r + 0.3) * math.cos(a), (r + 0.3) * math.sin(a), rr.uniform(2.5, 7.5)),
                        mix(GOO, GOO_HI, 0.5), subdiv=2, squash=(1.3, 0.3, 1.1), jitter=0.05, rot=(0, 0, deg + 90)))
    if f > 1:
        lw, lz, lh = r * 0.5, 4.5, 2.8
        out.append(painted(box("Label", (lw, 0.5, lh), (0, -r - 0.35, lz), CREAM), shade(CREAM, 0.95), CREAM))
        out.append(painted(box("LabelBand", (lw + 0.3, 0.6, 0.9), (0, -r - 0.4, lz + lh / 2 + 0.2), TRIM), shade(TRIM, 0.9), TRIM))
        for k in range(f):
            out.append(blob(f"Dot{k}", 0.55, ((k - (f - 1) / 2) * 1.6, -r - 0.7, lz - 0.3), GOO, subdiv=1, jitter=0))
    return out


def jar_deck(f):
    """Jar f's floor above the ground: a goo pool in a wooden ring, the stair hole in the middle with a cork rim, a few
    bubbles. Top of the goo at z = 0 (the floor's walking surface)."""
    r, hole = radius(f), D["stair"]["hole"]
    out = [painted(lathe("Wood", [(hole, -1.0), (r - 1.0, -1.0), (r - 1.0, -0.05)], WOOD_D, double=False), shade(WOOD_D, 0.9), WOOD_D)]
    out.append(painted(lathe("Pool", [(r - 0.4, 0.0), (hole + 0.4, 0.0)], GOO, double=False), shade(GOO, 0.85), GOO))
    out.append(loop("HoleRim", hole + 0.2, 0.4, (0, 0, 0.05), "z", CORK, segs=32))
    rr = random.Random(90 + f)
    for k in range(7):
        a, d = rr.uniform(0, math.tau), rr.uniform(hole + 2, r - 3)
        out.append(blob(f"Bubble{k}", rr.uniform(0.35, 0.8), (d * math.cos(a), d * math.sin(a), 0.15), GOO_HI, subdiv=1, squash=(1, 1, 0.8), jitter=0))
    return out


def jar_foot():
    """The ground under jar 1, lying on the plot's Base (z = 0 is the Base top, the floor players walk on): a low round
    wooden foot, the goo moat round it on a sandy bed, jar 1's goo pool with bubbles. All of it is decor a few tenths
    of a stud thick, so feet hardly sink in."""
    r1, m = radius(1), D["moat"]
    out = [painted(cylinder("Foot", m["inner"], 0.3, (0, 0, 0), WOOD, segs=SEGS), shade(WOOD, 0.85), WOOD)]
    out.append(painted(lathe("MoatBed", [(m["outer"], 0.0), (m["outer"], 0.06), (m["inner"], 0.06)], shade(PATH, 0.95), double=False)))
    out.append(painted(lathe("MoatRim", [(m["outer"], 0.06), (m["outer"], 0.3), (m["outer"] - 0.4, 0.3)], WOOD_D, double=False)))
    out.append(painted(lathe("Moat", [(m["outer"] - 0.3, 0.18), (m["inner"], 0.18)], GOO, double=False), shade(GOO, 0.9), GOO))
    out.append(painted(cylinder("Pool", r1 - 0.4, 0.06, (0, 0, 0.3), GOO, segs=SEGS), shade(GOO, 0.9), GOO))
    rr = random.Random(91)
    for k in range(8):
        a, d = rr.uniform(0, math.tau), rr.uniform(8, r1 - 3)
        out.append(blob(f"Bubble{k}", rr.uniform(0.35, 0.8), (d * math.cos(a), d * math.sin(a), 0.45), GOO_HI, subdiv=1, squash=(1, 1, 0.8), jitter=0))
    return out


def jar_stair():
    """The spiral stair from a floor up to the next: the goo centre post and one cork tread per stud of height, tread 1
    at the first tread angle of floor 1 (the game turns the mesh for higher floors)."""
    st = D["stair"]
    angles = D["floors"][0]["treads"]
    out = [painted(cylinder("Post", st["post"], FLOOR_H, (0, 0, 0), GOO, segs=16), shade(GOO, 0.85), mix(GOO, GOO_HI, 0.4))]
    mid = (st["post"] + st["outer"]) / 2
    for k, deg in enumerate(angles, start=1):
        a = math.radians(deg)
        out.append(painted(box(f"Tread{k}", (st["outer"] - st["post"] + 0.4, 2.2, 1.0), (mid * math.cos(a), mid * math.sin(a), k - 0.5), CORK,
                               rot=(0, 0, deg)), shade(CORK, 0.85), CORK))
    return out


def cork_stand():
    """The slime stand: a cork pedestal with a brass band, a dish rimmed in the plot colour (its rim the size of the
    habitat deck) and a goo bed the slime sits in at the game's seat height."""
    deck = D["padDeck"]["half"]
    seat = D["padSeatY"]
    return [painted(cylinder("Foot", deck + 0.15, 0.5, (0, 0, 0), shade(CORK, 0.85), segs=20), shade(CORK, 0.75), shade(CORK, 0.85)),
            painted(cylinder("Body", deck - 0.45, seat - 0.9, (0, 0, 0.5), CORK, segs=20, r_top=deck - 0.75), shade(CORK, 0.8), CORK),
            cylinder("Band", deck - 0.5, 0.4, (0, 0, 0.9), METAL, segs=20),
            painted(cylinder("Dish", deck - 0.75, 0.45, (0, 0, seat - 0.45), TRIM, segs=20, r_top=deck), shade(TRIM, 0.9), TRIM),
            cylinder("Bed", deck - 0.8, 0.1, (0, 0, seat - 0.05), GOO_HI, segs=20)]


def door_center():
    return (0.0, D["doorway"]["zOuter"] + 0.6, D["door"]["height"] / 2 + 0.1)


def jar_door():
    """Jar 1's round door: a wooden frame ring round the doorway with a goo line along its top, and the sill."""
    cx, cy, cz = door_center()
    rad = D["door"]["width"] / 2 + 0.9
    out = [loop("Frame", rad, 0.9, (cx, cy, cz), "y", WOOD_D, segs=32)]
    out.append(painted(loop("Goo", rad, 0.75, (cx, cy - 0.65, cz), "y", GOO, segs=32, arc=(25, 155)), shade(GOO, 0.9), GOO_HI))
    out.append(painted(box("Sill", (D["door"]["width"] + 2, 2.4, 0.6), (cx, cy, 0.3), WOOD), shade(WOOD, 0.9), WOOD))
    return out


def jar_door_ring():
    """The lock ring round the door frame (the game tints it: brass while open, glowing red while locked)."""
    cx, cy, cz = door_center()
    return [loop("Ring", D["door"]["width"] / 2 + 2.0, 0.45, (cx, cy - 0.4, cz), "y", rgb(235, 235, 235), segs=36)]


def jar_stopper():
    """The cork stopper that plugs the door while locked (it is parked beside it while open). Faces -Y."""
    return [painted(cylinder("Cork", 4.6, 3.4, (0, 0, 4.6), CORK, segs=28, r_top=4.2, rot=(90, 0, 0)), shade(CORK, 0.85), CORK),
            cylinder("Band", 4.7, 0.6, (0, -1.2, 4.6), METAL, segs=28, rot=(90, 0, 0)),
            blob("Grip", 1.4, (0, -3.6, 4.6), METAL, subdiv=2, squash=(1, 0.6, 1), jitter=0)]


def lock_button():
    """The lock button: a red goo button on a cork post."""
    return [painted(cylinder("Post", 2.0, 3.2, (0, 0, 0), CORK, segs=18), shade(CORK, 0.85), CORK),
            cylinder("Band", 2.1, 0.35, (0, 0, 2.6), METAL, segs=18),
            blob("Button", 1.6, (0, 0, 3.4), RED, subdiv=2, squash=(1, 1, 0.55), jitter=0)]


def tube_path(version):
    """The drop tube's centreline for a tower of `version` jars: from a hatch on the back of the top jar down the back,
    hugging each jar and sliding in over the shoulders, then out over the moat into the splash pool (game numbers)."""
    back = math.radians(D["dropAngle"])
    cb, sb = math.cos(back), math.sin(back)

    def rad_at(z):
        f = max(1, min(version, int(z // FLOOR_H) + 1))
        h = z - (f - 1) * FLOOR_H
        here = radius(f) + 2.6
        if f < version and h > 9.2:
            t = min(1.0, (h - 9.2) / 6.8)
            t = t * t * (3 - 2 * t)
            return here + (radius(f + 1) + 2.6 - here) * t
        return here

    z_hi = (version - 1) * FLOOR_H + 7.5
    pts = []
    for i in range(61):
        z = z_hi + (2.0 - z_hi) * i / 60
        r = rad_at(z)
        pts.append((r * cb, r * sb, z))
    land = D["dropLanding"]
    lr = math.hypot(land[0], land[2])
    for k, (d, zz) in enumerate(((0.35, 1.2), (0.7, 0.7), (1.0, 0.5))):
        r = pts[-1][0] / cb + (lr - pts[-1][0] / cb) * d if cb else lr
        pts.append((r * cb, r * sb, zz))
    return pts


def drop_tube_glass(version):
    pts = tube_path(version)
    return [tube("Glass", pts, [2.3] * len(pts), GLASS, segs=12)]


def drop_tube_goo(version):
    """The goo inside the tube, the brass collars where it meets each upper jar, the cork hatches and the splash pool."""
    pts = tube_path(version)
    back = math.radians(D["dropAngle"])
    cb, sb = math.cos(back), math.sin(back)
    out = [painted(tube("Goo", pts, [1.6] * len(pts), GOO, segs=10), shade(GOO, 0.85), GOO_HI)]
    for f in range(2, version + 1):
        r = radius(f)
        hz = (f - 1) * FLOOR_H + 4.0
        out.append(cylinder(f"Hatch{f}", 2.6, 0.9, ((r + 0.2) * cb, (r + 0.2) * sb, hz - 2.6), CORK, segs=14))
    ex, ey, _ = pts[-1]
    out.append(painted(blob("Splash", 4.0, (ex, ey, 0.4), GOO, subdiv=2, squash=(1.3, 1.3, 0.28), jitter=0.06), shade(GOO, 0.9), GOO_HI))
    for k, (x, y) in enumerate(ring_xy(5, 4.6, 0.3)):
        out.append(blob(f"Splat{k}", 0.8, (ex + x, ey + y, 0.5), GOO_HI, subdiv=1, jitter=0.1))
    return out


def mascot():
    """The slime mascot on the top lid: a big goo slime with eyes, pupils, pink cheeks and a shine, in a goo puddle.
    Built at radius 1 (the game scales it per version); faces -Y."""
    s = 1.0
    out = [painted(blob("Body", s, (0, 0, s * 0.78), GOO, subdiv=3, squash=(1, 1, 0.78), jitter=0.015, lumps=0.05),
                   shade(GOO, 0.82), mix(GOO, GOO_HI, 0.45))]
    out.append(blob("Shine", s * 0.22, (-s * 0.35, -s * 0.45, s * 1.2), GOO_HI, subdiv=2, squash=(1, 0.5, 0.7), jitter=0))
    z = s * 0.78
    for side in (-1, 1):
        ex, ey = side * s * 0.34, -s * 0.86
        out.append(blob(f"Eye{side}", s * 0.2, (ex, ey, z + s * 0.15), EYE_W, subdiv=2, squash=(1, 0.6, 1.15), jitter=0))
        out.append(blob(f"Pupil{side}", s * 0.11, (ex, ey - s * 0.1, z + s * 0.12), EYE_D, subdiv=2, squash=(1, 0.6, 1.2), jitter=0))
        out.append(blob(f"Cheek{side}", s * 0.12, (side * s * 0.58, -s * 0.8, z - s * 0.12), PINK, subdiv=1, squash=(1, 0.4, 0.7), jitter=0))
    out.append(cylinder("Puddle", s * 1.05, 0.06, (0, 0, 0), GOO, segs=24, jitter=0.08, seed=9))
    return out


def crown():
    """The mascot's crown at the last version (radius 1, the game scales it with the mascot)."""
    s = 1.0
    out = [cylinder("Band", s * 0.36, s * 0.18, (0, 0, 0), BUTTER, segs=12)]
    for k, (x, y) in enumerate(ring_xy(5, s * 0.33)):
        out.append(cone(f"Point{k}", s * 0.1, s * 0.3, (x, y, s * 0.16), BUTTER, segs=5))
        out.append(blob(f"Gem{k}", s * 0.05, (x, y, s * 0.47), PINK, subdiv=1, jitter=0))
    return out


def mascot_size(version):
    """Mascot radius for a tower of `version` jars (the design: 3.4 + 1.3 per version)."""
    return D["mascot"]["base"] + D["mascot"]["grow"] * version


def ship(name, parts):
    """finish() a game mesh, mirrored in X first. The builders work in game axes (blender x, y, z = game x, z, y), which
    is a mirror of the kit's FBX axes; mirroring x here makes the uploaded mesh the builder's shape turned half round,
    and WorldLayout's jar look slots turn it back (they add 180 to undo MeshSwap's IMPORT_YAW). Checked in Studio: the
    drop tube's top and splash pool land where the builder put them, the mascot faces the door."""
    for o in parts:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.transform(bm, matrix=o.matrix_world.copy(), verts=bm.verts)
        for v in bm.verts:
            v.co.x = -v.co.x
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bm.to_mesh(o.data)
        bm.free()
        o.matrix_world = o.matrix_world.Identity(4)
    return finish(name, parts)
