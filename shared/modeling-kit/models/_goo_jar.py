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

from models._goo_jar_themes import THEMES

# The theme every piece is built in (models/_goo_jar_themes.py; default the tower as built).
THEME_ID = os.environ.get("JAR_THEME", "classic")
THEME = THEMES[THEME_ID]
WOOD, WOOD_D, CREAM = THEME["wood"], THEME["wood_d"], THEME["cream"]
GOO, GOO_HI, METAL = THEME["goo"], THEME["goo_hi"], THEME["metal"]
PINK, LILAC, BUTTER = THEME["pink"], THEME["lilac"], THEME["butter"]
PATH = THEME["path"]
GLASS = THEME["glass"]
CORK = THEME["cork"]
SAND = THEME["sand"]
STRIPE = THEME.get("stripe")  # a second rib colour: the ribs come out striped
LEAVES = THEME.get("leaves")  # leaf colour: the ribs become leafy vines
ICICLES = THEME.get("icicles", False)  # icicles hang from the lids
GREEN = LEAVES or PALETTE["ranch_field_light"]  # stems and bushes on the props
BUDS = THEME.get("buds")  # colours of little buds (flowers, sparkles) dotted up the ribs
RED = rgb(240, 70, 60)  # the lock button: a gameplay signal, the same in every theme
TRIM = mix(LILAC, CREAM, 0.15)
EYE_W, EYE_D = rgb(246, 250, 250), rgb(56, 42, 38)

FLOOR_H = D["floorHeight"]
FLOORS = len(D["floors"])
SHAPE = D["jarShape"]
WALL_H = SHAPE["wall"]  # a covered jar: straight glass above the floor, then the rounded shoulder in to the next jar
SHOULDER_H = SHAPE["shoulder"]
NECK_Z = 0.2 + WALL_H + SHOULDER_H  # a covered jar's neck: the next jar stands in its lid here
TOP_WALL, TOP_DOME = SHAPE["topWall"], SHAPE["topDome"]  # the top jar: straight glass, then a round dome
TOP_NECK = SHAPE["topNeck"]  # the top jar's neck, as a share of its radius
LIP = SHAPE["lip"]  # the glass lip round the top jar's neck, the cork sits on it
CORK_H, LID_H = SHAPE["cork"], SHAPE["lid"]
DOOR_H = D["door"]["height"]
SEGS = 64

def radius(f):
    return D["floors"][f - 1]["radius"]


def neck(f, top):
    """Neck radius of jar f: the next jar's radius (it stands on this lid) or, for the top jar, a narrow neck."""
    return radius(f) * TOP_NECK if top or f >= FLOORS else radius(f + 1) - 0.6


def wall_top(f, top):
    """Height of jar f's straight glass: jar 1's clears its door, so its shoulder or dome starts above the door."""
    w = 0.2 + (TOP_WALL if top else WALL_H)
    return max(w, DOOR_H + 0.3) if f == 1 else w


def neck_z(f, top):
    """Height of jar f's neck: the top of its shoulder (covered) or of its dome (top). The top jar's lip sits above."""
    return wall_top(f, top) + (TOP_DOME if top else max(1.2, NECK_Z - wall_top(f, top)))


def glass_profile(f, top):
    """Jar f's glass outline (r, z) from its rounded foot under the floor to the neck (and the top jar's lip): a quarter
    ellipse from the straight wall in to the neck, so the jar rounds over instead of stopping."""
    r, nk = radius(f), neck(f, top)
    wt, nz = wall_top(f, top), neck_z(f, top)
    pts = [(r - 1.8, -1.2), (r, 0.2), (r, wt)]
    steps = 8 if top else 5
    for k in range(1, steps + 1):
        t = k / steps * math.pi / 2
        pts.append((nk + (r - nk) * math.cos(t), wt + (nz - wt) * math.sin(t)))
    if top:
        pts.append((nk, nz + LIP))
    return pts

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


def loop(name, r, thick, center, normal_axis, col, segs=28, arc=(0.0, 360.0), twist_free=False):
    """A tube bent into a circle (or an arc) of radius r round `center`, in the plane normal to axis 'x', 'y' or 'z'.
    twist_free: no pinched seam where a full circle closes (see lib tube)."""
    pts = []
    a0, a1 = arc
    n = segs if arc == (0.0, 360.0) else max(3, int(segs * (a1 - a0) / 360))
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        u, v = r * math.cos(a), r * math.sin(a)
        cx, cy, cz = center
        pts.append({"x": (cx, cy + u, cz + v), "y": (cx + u, cy, cz + v), "z": (cx + u, cy + v, cz)}[normal_axis])
    return tube(name, pts, [thick] * len(pts), col, segs=8, twist_free=twist_free)


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
    if ICICLES:
        ri = random.Random(seed + 500)
        ice = mix(GOO_HI, CREAM, 0.5)
        for k in range(drops * 3):
            a, h = ri.uniform(0, math.tau), ri.uniform(1.5, 4.0)
            x, y = (r + thick * 0.2) * math.cos(a), (r + thick * 0.2) * math.sin(a)
            out.append(painted(cylinder(f"{name}Icicle{k}", 0.03, h, (x, y, z_rim - thick * 0.2 - h), ice, segs=6, r_top=0.45),
                               GOO_HI, ice))
    return out


def resample(pts, step):
    """The polyline `pts` re-cut into points about `step` apart (keeping its ends)."""
    out = [Vector(pts[0])]
    for a, b in zip(pts, pts[1:]):
        a, b = Vector(a), Vector(b)
        n = max(1, round((b - a).length / step))
        out += [a.lerp(b, i / n) for i in range(1, n + 1)]
    return [tuple(p) for p in out]


def rib(name, pts):
    """One rib up the jar: a brass bar, striped in two colours (STRIPE) or a leafy vine (LEAVES) in some themes, with
    buds (BUDS: flowers, sparkles) dotted up it."""
    out = bar(name, pts)
    if BUDS:
        dense = resample(pts, 1.0)
        for i in range(2, len(dense) - 1, 3):
            p = Vector(dense[i])
            c = p + Vector((p.x, p.y, 0)).normalized() * 0.3
            out.append(blob(f"{name}Bud{i}", 0.34, tuple(c), BUDS[(i // 3) % len(BUDS)], subdiv=1, jitter=0, seed=i))
    return out


def bar(name, pts):
    if STRIPE:
        dense = resample(pts, 1.2)
        return [tube(f"{name}_{i}", dense[i:i + 2], [0.35, 0.35], METAL if i % 2 == 0 else STRIPE, segs=6)
                for i in range(len(dense) - 1)]
    if LEAVES:
        dense = resample(pts, 1.0)
        out = [painted(tube(name, dense, [0.3] * len(dense), METAL, segs=6, seed=len(name), jitter=0.06), shade(METAL, 0.85), METAL)]
        for i in range(1, len(dense) - 1, 2):
            p, q = Vector(dense[i]), Vector(dense[i + 1])
            out_dir = Vector((p.x, p.y, 0)).normalized()
            along = (q - p).normalized()
            side = along.cross(out_dir).normalized() * (0.45 if i % 4 == 1 else -0.45)
            c = p + out_dir * 0.25 + side
            deg = math.degrees(math.atan2(out_dir.y, out_dir.x))
            out.append(blob(f"{name}Leaf{i}", 0.55, tuple(c), LEAVES, subdiv=1, squash=(0.35, 1.0, 0.6), jitter=0, rot=(0, 0, deg)))
        return out
    return [tube(name, pts, [0.35] * len(pts), METAL, segs=6)]


# --- Pieces --------------------------------------------------------------------------------------------------------
def jar_glass(f, top):
    """Jar f's glass shell (Glass in the game, MeshMaterial): the rounded foot, the straight wall (jar 1 with the door
    cut out below the door's top), the shoulder or dome rounding in to the neck, a rounded glass bead on the rim, and
    two soft shine streaks down the front-left (white, so they show faintly through the transparency)."""
    prof = glass_profile(f, top)
    r, nk = radius(f), neck(f, top)
    parts = []
    if f == 1:
        ha = door_half_angle()
        low = [p for p in prof if p[1] <= DOOR_H]
        high = [(r, DOOR_H)] + [p for p in prof if p[1] > DOOR_H]
        parts += [lathe("GlassLow", low + [(r, DOOR_H)], GLASS, a0=-90 + ha, a1=270 - ha), lathe("GlassHigh", high, GLASS)]
    else:
        parts.append(lathe("Glass", prof, GLASS))
    rim_z = prof[-1][1]
    parts.append(loop("Rim", nk + 0.05, 0.32, (0, 0, rim_z), "z", mix(GLASS, CREAM, 0.4), segs=SEGS))
    shine = [(pr + 0.07, pz) for pr, pz in prof if pz >= 0.6 and pz <= prof[-1][1] - 0.3]
    for k, (a0, a1) in enumerate(((-128.0, -125.0), (-120.0, -118.6))):
        parts.append(lathe(f"Shine{k}", shine, rgb(255, 255, 255), a0=a0, a1=a1, segs=360, double=False))
    return parts

def jar_trim(f, top, crown=False):
    """Jar f's opaque trim: brass ribs up the wall and over the shoulder or dome to the neck, the threaded neck, the cork
    (a ring the next jar stands in, the top jar's tall stopper, or the crowned last jar's flat lid), goo oozing over the
    lid with teardrop drips and goo smears on the glass."""
    r, nk = radius(f), neck(f, top)
    prof = [p for p in glass_profile(f, top) if p[1] >= 0.2]
    nz = neck_z(f, top)
    out = []
    ha = door_half_angle() if f == 1 else 0
    for k, (x, y) in enumerate(ring_xy(8, 1.0, math.pi / 8)):
        a = math.degrees(math.atan2(y, x))
        if f == 1 and abs(((a + 90 + 180) % 360) - 180) < ha + 2:
            continue  # no rib over the door
        pts = [(x * (pr + 0.18), y * (pr + 0.18), pz) for pr, pz in prof]
        if not top and f < FLOORS:
            # a covered jar: carry the rib on from its neck straight up to the next jar's floor, at that jar's rib
            # radius, so the brass bars run unbroken up the tower
            ru = radius(f + 1) + 0.18
            pts += [(x * ru, y * ru, pts[-1][2] + 0.3), (x * ru, y * ru, FLOOR_H + 0.25)]
        out += rib(f"Rib{k}", pts)
    lip_top = nz + (LIP if top else 0.0)
    for k in range(2):
        # brass rings round the neck: hollow, or under a covered jar they would read as a solid floor through the
        # next jar's stair hole
        out.append(loop(f"Thread{k}", nk + 0.35, 0.4, (0, 0, lip_top - 0.55 + k * 0.55), "z", METAL, segs=SEGS))
    if top and f > 1:
        # the top jar's stair ends here: the goo post goes on a little above the deck with a round cap and a brass
        # collar, so the stair has a finish instead of a post cut off at the floor
        post = D["stair"]["post"]
        out.append(painted(cylinder("Newel", post, 2.4, (0, 0, 0), GOO, segs=16), shade(GOO, 0.85), mix(GOO, GOO_HI, 0.4)))
        out.append(cylinder("NewelCollar", post + 0.15, 0.3, (0, 0, 2.1), METAL, segs=16))
        out.append(blob("NewelCap", post + 0.2, (0, 0, 2.6), GOO_HI, subdiv=2, squash=(1, 1, 0.8), jitter=0))
    if top and not crown:  # the top jar while growing: a tall cork stopper, wider at the top
        out.append(painted(cylinder("Cork", nk + 0.1, CORK_H, (0, 0, lip_top), CORK, segs=SEGS, r_top=nk + 0.9), shade(CORK, 0.8), CORK))
        out.append(cylinder("CorkRing", nk + 1.0, 0.5, (0, 0, lip_top + CORK_H - 0.8), shade(CORK, 0.88), segs=SEGS))
        lid_top = lip_top + CORK_H
    elif top:  # the crowned last jar: a flat cork lid the mascot sits on
        out.append(painted(cylinder("Lid", nk + 0.4, LID_H, (0, 0, lip_top), CORK, segs=SEGS), shade(CORK, 0.85), CORK))
        lid_top = lip_top + LID_H
    else:  # a cork ring the next jar stands in (its deck covers the middle, the stair comes up through it)
        inner = radius(f + 1) - 1.2
        out.append(painted(lathe("Lid", [(nk + 0.3, nz), (nk + 0.3, nz + LID_H), (inner, nz + LID_H)], CORK, double=False),
                           shade(CORK, 0.85), CORK))
        lid_top = nz + LID_H
    out += ooze("Ooze", nk + 0.6, lid_top - (0.4 if not top else 0.2), 1.0 + 0.15 * f, 7 + f, seed=40 + f)
    rr = random.Random(70 + f)
    for k in range(2):
        deg = rr.choice([rr.uniform(-40, 50), rr.uniform(130, 220)])
        a = math.radians(deg)
        out.append(blob(f"Smear{k}", rr.uniform(1.0, 1.6), ((r + 0.3) * math.cos(a), (r + 0.3) * math.sin(a), rr.uniform(2.5, 6.5)),
                        mix(GOO, GOO_HI, 0.5), subdiv=2, squash=(1.3, 0.3, 1.1), jitter=0.05, rot=(0, 0, deg + 90)))
    return out

def jar_deck(f):
    """Jar f's floor above the ground: a goo pool in a wooden ring and a few bubbles, the stair hole in the middle with
    no rim: the goo rolls over its edge and lines the hole's wall, so the floor's thickness doesn't show from the stair.
    Top of the goo at z = 0 (the floor's walking surface)."""
    r, hole = radius(f), D["stair"]["hole"]
    out = [painted(lathe("Wood", [(hole + 0.2, -1.0), (r - 1.0, -1.0), (r - 1.0, -0.05)], CORK, double=False), shade(CORK, 0.95), CORK)]
    out.append(painted(lathe("Pool", [(r - 0.4, 0.0), (hole + 0.3, 0.0), (hole, -0.25), (hole, -1.05)], GOO, double=False),
                       shade(GOO, 0.8), GOO))
    rr = random.Random(90 + f)
    for k in range(7):
        a, d = rr.uniform(0, math.tau), rr.uniform(hole + 2, r - 3)
        out.append(blob(f"Bubble{k}", rr.uniform(0.35, 0.8), (d * math.cos(a), d * math.sin(a), 0.15), GOO_HI, subdiv=1, squash=(1, 1, 0.8), jitter=0))
    return out


def jar_foot():
    """The whole round plot floor (z = 0 is its top, the floor players walk on; the game's PlotFloor collider is under
    it): a sandy ring out to the plot's edge with a cork rim and its 1-stud edge down to the ground, a low round
    wooden foot, the goo moat round it on a sandy bed, jar 1's goo pool with bubbles. The top is decor a few tenths of
    a stud thick, so feet hardly sink in."""
    r1, m = radius(1), D["moat"]
    edge = D["plotFloorRadius"]
    out = [painted(lathe("Sand", [(edge, -1.0), (edge, 0.0), (edge - 0.4, 0.06), (m["outer"] - 0.2, 0.06)], SAND, double=False),
                   shade(SAND, 0.82), SAND),
           painted(lathe("Rim", [(edge + 0.05, -0.15), (edge + 0.05, 0.12), (edge - 0.5, 0.12)], WOOD_D, double=False), shade(WOOD_D, 0.85), WOOD_D)]
    out.append(painted(cylinder("Foot", m["inner"], 0.3, (0, 0, 0), WOOD, segs=SEGS), shade(WOOD, 0.85), WOOD))
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
    """The stair from a floor up to the next, as a smooth spiral ramp (WorldLayout.RAMP): the goo centre post, a cork
    ramp climbing FLOOR_H in one turn from half a step before floor 1's first tread angle, ending where the next floor's
    ramp starts (stacked, they make one unbroken spiral), a goo line along the inner edge and a brass hand rail on balusters along the outer edge (open where the game's rail
    is open, at the bottom and before the top). The game turns the mesh for higher floors."""
    import bmesh
    from lib.shapes import obj_from_bm
    st, rp = D["stair"], D["ramp"]
    start = D["floors"][0]["treads"][0] - st["angle"]
    span = st["angle"] * round(FLOOR_H)
    post, outer = st["post"], st["outer"]
    out = [painted(cylinder("Post", post, FLOOR_H, (0, 0, 0), GOO, segs=16), shade(GOO, 0.85), mix(GOO, GOO_HI, 0.4))]

    def at(r, deg, z):
        a = math.radians(deg)
        return (r * math.cos(a), r * math.sin(a), z)

    def surface(deg):
        return min(FLOOR_H, max(0.0, (deg - start) / span * FLOOR_H))

    n = 72
    angles = [start + span * i / n for i in range(n + 1)]  # the next floor's ramp goes on from the top
    bm = bmesh.new()
    rows = []
    for deg in angles:
        z = surface(deg)
        rows.append([bm.verts.new(at(post, deg, z)), bm.verts.new(at(outer, deg, z)),
                     bm.verts.new(at(outer, deg, z - 0.6)), bm.verts.new(at(post, deg, z - 0.6))])
    for k in range(len(rows) - 1):
        a, b = rows[k], rows[k + 1]
        bm.faces.new((a[0], a[1], b[1], b[0]))  # top
        bm.faces.new((a[1], a[2], b[2], b[1]))  # outer side
        bm.faces.new((a[2], a[3], b[3], b[2]))  # underside
    bm.faces.new(tuple(reversed(rows[0])))
    bm.faces.new(tuple(rows[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    out.append(painted(obj_from_bm("Ramp", bm, CORK), shade(CORK, 0.82), CORK))
    # goo line along the inner edge
    inner = [at(post + 0.2, deg, surface(deg) + 0.08) for deg in angles[::3]]
    out.append(painted(tube("GooEdge", inner, [0.2] * len(inner), GOO, segs=6), shade(GOO, 0.9), GOO_HI))
    # the brass rail where the game's rail wall stands
    r0, r1 = start + rp["railStart"], start + span - rp["railEnd"]
    steps = max(2, int((r1 - r0) / 7.5))
    rail_angles = [r0 + (r1 - r0) * i / steps for i in range(steps + 1)]
    rail = [at(outer - 0.15, deg, surface(deg) + rp["railHeight"] - 0.2) for deg in rail_angles]
    out.append(tube("Rail", rail, [0.14] * len(rail), METAL, segs=8))
    for k, deg in enumerate(rail_angles[::2]):
        out.append(cylinder(f"Baluster{k}", 0.08, rp["railHeight"] - 0.2, at(outer - 0.15, deg, surface(deg)), METAL, segs=6))
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


def door_surround(r_in, r_out, front_y, cz, segs=48):
    """The wooden surround that seals the round door frame to jar 1's curved glass: a ring plate from r_in to r_out
    round the door's centre (flat-bottomed at the floor), its front flat at front_y, its back on the glass cylinder
    (a little inside it), so no gap shows between the frame and the glass. It also covers the corners of the glass's
    square door cut."""
    R = radius(1)
    bm = bmesh.new()

    def back_y(x):
        return -math.sqrt(max(0.0, (R - 0.25) ** 2 - x * x))

    rings = []
    for k in range(segs):
        a = k / segs * math.tau
        pts = []
        for r in (r_in, r_out):
            x, z = r * math.cos(a), max(0.0, cz + r * math.sin(a))
            pts.append((x, z))
        rings.append([bm.verts.new((x, y, z)) for (x, z) in pts for y in (front_y, back_y(x))])
    for k in range(segs):
        a, b = rings[k], rings[(k + 1) % segs]
        # vertex order per ring: inner front, inner back, outer front, outer back
        bm.faces.new((a[0], a[2], b[2], b[0]))  # front (faces -Y, toward the bridge)
        bm.faces.new((a[1], b[1], b[3], a[3]))  # back (toward the glass)
        bm.faces.new((a[2], a[3], b[3], b[2]))  # outer rim
        bm.faces.new((a[0], b[0], b[1], a[1]))  # inner rim (the doorway)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = mix(WOOD, WOOD_D, 0.45)
    return painted(obj_from_bm("Surround", bm, col), shade(col, 0.8), col)


def jar_door():
    """Jar 1's door frame: a wooden frame ring round the doorway with a goo line along its top, the sill, the brass
    hinge knuckles (on a pin) the round door hangs on, on the left, and the surround that seals it to the glass."""
    cx, cy, cz = door_center()
    rad = D["door"]["width"] / 2 + 0.9
    out = [loop("Frame", rad, 0.9, (cx, cy, cz), "y", WOOD_D, segs=32, twist_free=True)]
    # out to the square door cut's far corners (half width x door height round the centre), past the lock ring
    corner = math.hypot(D["door"]["width"] / 2 + 0.3, max(cz, DOOR_H - cz))
    out.append(door_surround(rad, max(corner, D["door"]["width"] / 2 + 2.45) + 0.2, cy - 0.1, cz))
    out.append(painted(loop("Goo", rad, 0.75, (cx, cy - 0.65, cz), "y", GOO, segs=32, arc=(25, 155)), shade(GOO, 0.9), GOO_HI))
    out.append(painted(box("Sill", (D["door"]["width"] + 2, 2.4, 0.6), (cx, cy, 0.3), WOOD), shade(WOOD, 0.9), WOOD))
    # the hinge knuckles on the frame's left, above and below each of the door's own knuckles, on a pin
    hx, hy = D["doorSwing"]["hinge"][0], cy + 0.3 + D["doorSwing"]["hinge"][1]
    for k, dz in enumerate((-2.8, 2.8)):
        z = cz + dz
        for j, off in enumerate((-0.85, 0.85)):
            out.append(cylinder(f"Knuckle{k}{j}", 0.36, 0.75, (hx, hy, z + off - 0.375), METAL, segs=12))
        out.append(cylinder(f"Pin{k}", 0.14, 2.6, (hx, hy, z - 1.3), shade(METAL, 0.7), segs=8))
        edge = -math.sqrt(max(0.0, (D["door"]["width"] / 2 + 0.9) ** 2 - dz * dz))
        out.append(box(f"Leaf{k}", (abs(hx - edge) + 0.3, 0.2, 2.4), ((hx + edge) / 2, hy - 0.45, z), METAL))
    return out


def jar_door_ring():
    """The lock ring round the door frame (the game tints it: brass while open, glowing red while locked)."""
    cx, cy, cz = door_center()
    return [loop("Ring", D["door"]["width"] / 2 + 2.0, 0.45, (cx, cy - 0.4, cz), "y", rgb(235, 235, 235), segs=36)]


def jar_stopper():
    """Jar 1's round door (the game shows it shut in the doorway while locked, swung out of the jar on its hinges
    while open): a round plank door, inner face at y = 0, outer face at -Y (toward the bridge), with a cork rim, goo
    dripping over its top, two brass hinge straps reaching to the hinge pin on its left (-X) and a brass ring pull on
    the right. Bottom at z = 0."""
    r, t = 4.6, 1.0
    hx, hy = D["doorSwing"]["hinge"][0], D["doorSwing"]["hinge"][1]
    out = [painted(cylinder("Door", r, t, (0, 0, r), WOOD, segs=32, rot=(90, 0, 0)), shade(WOOD, 0.82), WOOD)]
    for k, x in enumerate((-2.3, 0.0, 2.3)):
        h = 2 * math.sqrt(r * r - x * x) - 0.7
        out.append(box(f"Groove{k}", (0.16, 0.08, h), (x, -t - 0.02, r), WOOD_D))
    out.append(painted(loop("Rim", r - 0.12, 0.3, (0, -t + 0.05, r), "y", CORK, segs=32), shade(CORK, 0.85), CORK))
    out.append(painted(loop("Goo", r - 0.05, 0.33, (0, -t - 0.12, r), "y", GOO, segs=32, arc=(32, 148)), shade(GOO, 0.9), GOO_HI))
    for k, x in enumerate((-1.4, 1.9)):
        out += teardrop(f"Drip{k}", x, -t - 0.3, r + math.sqrt(r * r - x * x) - 0.35, 0.9 + 0.3 * k, 0.26)
    for k, dz in enumerate((-2.8, 2.8)):
        z = r + dz
        out.append(box(f"Strap{k}", (abs(hx) - 0.9, 0.16, 0.6), ((hx - 0.9) / 2 - 0.0, -t - 0.08, z), METAL))
        out.append(cylinder(f"Knuckle{k}", 0.36, 0.9, (hx, hy, z - 0.45), METAL, segs=12))
    out.append(loop("Pull", 0.55, 0.12, (2.9, -t - 0.25, r), "y", METAL, segs=16))
    out.append(blob("PullBoss", 0.28, (2.9, -t - 0.1, r + 0.55), METAL, subdiv=1, jitter=0))
    return out


def lock_button():
    """The lock button, in the jar tower's style: a cork stand like the slime stands (brass bands, a goo ring), a brass
    bezel holding a big glossy red goo button with a shine and a drip down its side, and a brass padlock plate on the
    front (-Y, toward the door)."""
    out = [painted(cylinder("Foot", 2.5, 0.4, (0, 0, 0), shade(CORK, 0.85), segs=24), shade(CORK, 0.75), shade(CORK, 0.85)),
           painted(cylinder("Body", 2.05, 2.3, (0, 0, 0.4), CORK, segs=24, r_top=1.8), shade(CORK, 0.8), CORK),
           cylinder("Band", 2.12, 0.3, (0, 0, 0.8), METAL, segs=24),
           painted(cylinder("GooRing", 1.98, 0.22, (0, 0, 1.6), GOO, segs=24), shade(GOO, 0.9), GOO_HI),
           cylinder("Bezel", 2.15, 0.5, (0, 0, 2.7), METAL, segs=24, r_top=1.95),
           painted(blob("Button", 1.7, (0, 0, 3.15), RED, subdiv=3, squash=(1, 1, 0.48), jitter=0.01),
                   shade(RED, 0.75), mix(RED, rgb(255, 210, 200), 0.35)),
           blob("Shine", 0.45, (-0.55, -0.6, 3.75), rgb(255, 225, 220), subdiv=2, squash=(1, 0.6, 0.35), jitter=0)]
    # a red drip over the bezel's rim, and the padlock plate (body and shackle) on the front of the stand
    out += [painted(o, shade(RED, 0.8), RED) for o in teardrop("Drip", 1.4, -1.7, 3.1, 0.9, 0.32)]
    out.append(box("LockPlate", (1.2, 0.3, 1.0), (0, -1.95, 1.05), METAL))
    out.append(loop("Shackle", 0.38, 0.14, (0, -1.98, 1.6), "y", METAL, segs=16, arc=(0, 180)))
    out.append(box("KeyHole", (0.18, 0.1, 0.4), (0, -2.12, 1.0), shade(METAL, 0.45)))
    return out


def catmull(points, per=8):
    """A smooth centripetal-ish Catmull-Rom through `points` (x, y, z), `per` samples a span."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = (Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[i + 1]), Vector(pts[i + 2]))
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)))
    out.append(tuple(pts[-2]))
    return out


TUBE_OUT = 3.2  # the tube's centre stands this far out from each jar's glass


def tube_path(version):
    """The drop tube's centreline (game numbers) for a tower of `version` jars, all on the back at DROP_ANGLE: out of a
    hatch low on the top jar, a short elbow out, then straight down past each jar a little off the glass, easing out
    over each wider jar below, down past jar 1, and out over the moat to a flared mouth above the splash pool."""
    back = math.radians(D["dropAngle"])
    cb, sb = math.cos(back), math.sin(back)

    def at(r, z):
        return (r * cb, r * sb, z)

    top_z = (version - 1) * FLOOR_H
    ctrl = [at(radius(version) - 0.4, top_z + 3.0), at(radius(version) + TUBE_OUT * 0.6, top_z + 3.4),
            at(radius(version) + TUBE_OUT, top_z + 1.0)]
    for f in range(version - 1, 0, -1):
        z = f * FLOOR_H  # the floor of jar f + 1 / top of jar f
        ctrl.append(at(radius(f + 1) + TUBE_OUT, z + 0.5))
        ctrl.append(at(radius(f) + TUBE_OUT, z - 3.5))
    land = D["dropLanding"]
    lr = math.hypot(land[0], land[2])
    ctrl += [at(radius(1) + TUBE_OUT, 4.5), at((radius(1) + TUBE_OUT + lr) / 2, 3.0), at(lr, 2.6)]
    return catmull(ctrl, per=10)


def drop_tube_glass(version):
    """The tube's glass (Glass in the game, lightly goo-tinted so the pipe reads as full of goo): a round 16-sided tube
    along the path, flaring to a mouth at the bottom."""
    pts = tube_path(version)
    radii = [1.9] * (len(pts) - 6) + [1.95, 2.05, 2.2, 2.45, 2.75, 3.1]
    return [tube("Glass", pts, radii, mix(GOO_HI, GLASS, 0.5), segs=16, twist_free=True)]


def drop_tube_goo(version):
    """The pipe full of goo: a bright goo core filling the glass the whole way down, its surface a little lumpy, goo
    bubbles bulging out of it, a brass collar at each floor, cork-ringed goo-filled branches into every upper jar's
    hatch, and the splash pool with droplets under the mouth."""
    pts = tube_path(version)
    back = math.radians(D["dropAngle"])
    cb, sb = math.cos(back), math.sin(back)
    fill = mix(GOO, GOO_HI, 0.3)
    radii = [1.72] * (len(pts) - 6) + [1.76, 1.82, 1.9, 2.0, 2.0, 1.6]
    out = [painted(tube("Goo", pts, radii, fill, segs=14, seed=5, jitter=0.04, twist_free=True), shade(fill, 0.95), mix(GOO, GOO_HI, 0.55))]
    rr = random.Random(30 + version)
    for k in range(2, len(pts) - 6, 3):
        c = Vector(pts[k])
        d = (Vector(pts[k + 1]) - Vector(pts[k - 1])).normalized()
        side = d.cross(Vector((0, 0, 1)))
        side = side.normalized() if side.length > 1e-3 else Vector((1, 0, 0))
        up = side.cross(d).normalized()
        a = rr.uniform(0, math.tau)
        out_dir = side * math.cos(a) + up * math.sin(a)
        out.append(blob(f"Bubble{k}", rr.uniform(0.35, 0.6), tuple(c + out_dir * 1.55), GOO_HI, subdiv=1, jitter=0))
    # one thin brass collar where the tube passes each floor, and a cork-ringed branch into every upper jar's hatch
    def collar_at(z):
        k = min(range(len(pts) - 6), key=lambda i: abs(pts[i][2] - z))
        d = (Vector(pts[min(k + 1, len(pts) - 1)]) - Vector(pts[max(k - 1, 0)])).normalized()
        c = Vector(pts[k])
        return tube(f"Collar{int(z)}", [tuple(c - d * 0.25), tuple(c + d * 0.25)], [2.1, 2.1], METAL, segs=16)

    for f in range(1, version):
        out.append(collar_at(f * FLOOR_H + 0.5))
    # the tube is only entered from the top jar (the game keeps the lower jars' hatches shut): one cork flange there
    r = radius(version)
    hz = (version - 1) * FLOOR_H + 3.0
    out.append(tube("Flange", [((r - 0.1) * cb, (r - 0.1) * sb, hz), ((r + 0.7) * cb, (r + 0.7) * sb, hz)], [1.7, 1.7], CORK, segs=16))
    ex, ey, ez = pts[-1]
    # the splash where it lands in the moat (kept small: it sits on the moat ring, inside the round plot floor)
    out.append(painted(blob("Splash", 2.6, (ex, ey, 0.35), GOO, subdiv=3, squash=(1.3, 1.3, 0.22), jitter=0.05, lumps=0.1), shade(GOO, 0.9), GOO_HI))
    for k, (x, y) in enumerate(ring_xy(7, 3.1, 0.3)):
        out.append(blob(f"Splat{k}", 0.7 + 0.2 * (k % 2), (ex + x, ey + y, 0.5), GOO_HI, subdiv=1, jitter=0.1))
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


# --- Theme extras (concept: one more mesh per theme, placed on the plot floor / on the mascot) ---------------------
PROP_ANGLES = (-45, -10, 25, 112, 150, 190, 228)  # round the foot, clear of the door (-90) and the drop tube (dropAngle)


def theme_props():
    """The theme's props on the ring between jar 1's glass and the moat (plot-local, floor 1 at z = 0): lollipops and
    gumdrops (candy), ice crystals and snow mounds (frost), toadstools and ferns (forest). Classic has none."""
    ring = (radius(1) + D["moat"]["inner"]) / 2 + 0.3
    out = []
    rr = random.Random(7)
    for k, deg in enumerate(PROP_ANGLES):
        a = math.radians(deg)
        x, y = ring * math.cos(a), ring * math.sin(a)
        n = f"Prop{k}"
        if THEME_ID == "candy":
            col = (PINK, BUTTER, LILAC, METAL)[k % 4]
            h = rr.uniform(7.0, 9.0)
            out.append(cylinder(n + "Stick", 0.3, h, (x, y, 0.2), CREAM, segs=8))
            for j, (r, c) in enumerate(((2.4, col), (1.6, STRIPE), (0.8, col))):
                out.append(blob(f"{n}Pop{j}", r, (x, y, h + 1.6), c, subdiv=2, squash=(1, 0.28 + 0.04 * j, 1), jitter=0, rot=(0, 0, deg + 90)))
            for j in range(3):
                b = a + rr.uniform(-0.12, 0.12)
                d = ring + rr.uniform(-1.2, 1.2)
                gc = (PINK, BUTTER, METAL, LILAC)[(k + j) % 4]
                out.append(painted(blob(f"{n}Gum{j}", rr.uniform(0.8, 1.1), (d * math.cos(b), d * math.sin(b), 0.5), gc, subdiv=2,
                                        squash=(1, 1, 0.85), jitter=0), shade(gc, 0.85), mix(gc, CREAM, 0.3)))
        elif THEME_ID == "crystal":
            ice = mix(GLASS, GOO, 0.35)
            for j in range(4):
                h = rr.uniform(4.0, 8.0)
                tilt = rr.uniform(-22, 22)
                out.append(painted(cylinder(f"{n}Shard{j}", rr.uniform(0.7, 1.1), h, (x + rr.uniform(-0.8, 0.8), y + rr.uniform(-0.8, 0.8), 0.1),
                                            ice, segs=6, r_top=0.08, rot=(tilt, rr.uniform(-15, 15), rr.uniform(0, 60))),
                                   shade(ice, 0.9), mix(ice, CREAM, 0.5)))
            out.append(painted(blob(f"{n}Snow", 2.2, (x, y, 0.1), CREAM, subdiv=2, squash=(1.3, 1.0, 0.35), jitter=0.06, seed=k),
                               mix(CREAM, GLASS, 0.6), CREAM))
        elif THEME_ID == "garden":
            if k % 2 == 0:  # a sunflower
                h = rr.uniform(8.0, 10.0)
                out.append(painted(tube(f"{n}Stem", [(x, y, 0.1), (x + 0.3, y, h * 0.5), (x, y, h)], [0.36, 0.3, 0.26], GREEN, segs=6),
                                   shade(GREEN, 0.8), GREEN))
                for j in range(10):
                    pa = j * math.tau / 10
                    tx, ty = -math.sin(a), math.cos(a)  # the flower faces out of the plot
                    px, py, pz = x + tx * 2.0 * math.cos(pa), y + ty * 2.0 * math.cos(pa), h + 2.0 * math.sin(pa)
                    out.append(blob(f"{n}Petal{j}", 0.75, (px, py, pz), BUTTER, subdiv=1, jitter=0))
                out.append(blob(f"{n}Head", 1.4, (x, y, h), WOOD_D, subdiv=2, squash=(1, 0.5, 1), jitter=0.03, rot=(0, 0, deg + 90)))
            else:  # a potted fruit bush
                pot = THEME.get("pot", CORK)
                out.append(painted(cylinder(f"{n}Pot", 1.3, 1.8, (x, y, 0.1), pot, segs=12, r_top=1.7), shade(pot, 0.8), pot))
                out.append(painted(blob(f"{n}Bush", 2.0, (x, y, 3.6), GREEN, subdiv=2, squash=(1, 1, 1.05), jitter=0.08, seed=k),
                                   shade(GREEN, 0.75), GREEN))
                for j in range(6):
                    fa = j * math.tau / 6 + k
                    out.append(blob(f"{n}Fruit{j}", 0.42, (x + 1.8 * math.cos(fa), y + 1.8 * math.sin(fa), 3.4 + 0.6 * math.sin(fa * 2)),
                                    GOO if j % 2 else PINK, subdiv=1, jitter=0))
        elif THEME_ID == "starlight":
            h = rr.uniform(5.5, 8.0)
            out.append(cylinder(f"{n}Pole", 0.2, h, (x, y, 0.1), WOOD_D, segs=6))
            tx, ty = -math.sin(a), math.cos(a)
            out.append(blob(f"{n}Core", 0.85, (x, y, h + 0.3), BUTTER, subdiv=2, squash=(1, 1, 1), jitter=0))
            for j in range(5):  # a five-point star facing out of the plot
                pa = math.pi / 2 + j * math.tau / 5
                ex, ey, ez = x + tx * 2.3 * math.cos(pa), y + ty * 2.3 * math.cos(pa), h + 0.3 + 2.3 * math.sin(pa)
                out.append(tube(f"{n}Point{j}", [(x, y, h + 0.3), (ex, ey, ez)], [0.8, 0.08], BUTTER, segs=5))
            out.append(painted(blob(f"{n}Orb", 0.9, (x + 1.4 * math.cos(a + 1.7), y + 1.4 * math.sin(a + 1.7), 0.8), GOO_HI, subdiv=2, jitter=0),
                               GOO, GOO_HI))
        elif THEME_ID == "mushroom":
            for j, (dx, s) in enumerate(((0.0, 1.35), (1.8, 0.85))):
                cx, cy = x + dx * math.cos(a + 1.6), y + dx * math.sin(a + 1.6)
                cap = (BUTTER, PINK, LILAC)[(k + j) % 3]
                h = 2.6 * s
                out.append(painted(cylinder(f"{n}Stem{j}", 0.5 * s, h, (cx, cy, 0.1), CREAM, segs=10, r_top=0.4 * s), shade(CREAM, 0.85), CREAM))
                out.append(painted(blob(f"{n}Cap{j}", 1.6 * s, (cx, cy, h), cap, subdiv=2, squash=(1, 1, 0.5), jitter=0), shade(cap, 0.8), cap))
                for d in range(4):
                    da = d * math.tau / 4 + 0.4
                    out.append(blob(f"{n}Dot{j}{d}", 0.25 * s, (cx + 0.9 * s * math.cos(da), cy + 0.9 * s * math.sin(da), h + 0.55 * s), CREAM,
                                    subdiv=1, squash=(1, 1, 0.5), jitter=0))
            for j in range(3):
                b = a + 0.25 + j * 0.08
                out.append(blob(f"{n}Fern{j}", 1.3, ((ring + 0.6) * math.cos(b), (ring + 0.6) * math.sin(b), 0.5), LEAVES, subdiv=1,
                                squash=(0.4, 1.0, 0.7), jitter=0.05, rot=(rr.uniform(-30, 30), 0, math.degrees(b))))
    return out


def mascot_hat():
    """The theme's hat on the mascot (radius 1 like the mascot; the game scales it with the mascot): a cherry on cream
    (candy), a knitted hat with a pompom (frost), a toadstool cap (forest). Classic has none."""
    if THEME_ID == "candy":
        return [blob("Cream", 0.5, (0, 0, 1.42), CREAM, subdiv=2, squash=(1, 1, 0.55), jitter=0.04),
                blob("Cherry", 0.24, (0, 0, 1.78), mix(PINK, RED, 0.5), subdiv=2, jitter=0),
                tube("CherryStem", [(0, 0, 1.95), (0.08, 0, 2.15), (0.22, 0, 2.3)], [0.04, 0.04, 0.03], WOOD_D, segs=5)]
    if THEME_ID == "crystal":
        return [painted(blob("Hat", 0.66, (0, 0, 1.3), METAL, subdiv=2, squash=(1, 1, 0.62), jitter=0), shade(METAL, 0.85), METAL),
                cylinder("Band", 0.68, 0.16, (0, 0, 1.18), CREAM, segs=20),
                blob("Pompom", 0.2, (0, 0, 1.74), CREAM, subdiv=2, jitter=0.08)]
    if THEME_ID == "garden":
        return [painted(cylinder("Brim", 0.95, 0.08, (0, 0, 1.3), BUTTER, segs=24), shade(BUTTER, 0.85), BUTTER),
                painted(blob("Crown", 0.5, (0, 0, 1.4), BUTTER, subdiv=2, squash=(1, 1, 0.7), jitter=0), shade(BUTTER, 0.85), BUTTER),
                cylinder("Ribbon", 0.5, 0.1, (0, 0, 1.36), PINK, segs=16),
                blob("Flower", 0.14, (0.42, -0.25, 1.5), PINK, subdiv=1, jitter=0)]
    if THEME_ID == "starlight":
        return [painted(cylinder("Brim", 0.8, 0.08, (0, 0, 1.3), CORK, segs=20), shade(CORK, 0.85), CORK),
                painted(tube("Hat", [(0, 0, 1.3), (0.05, 0, 1.8), (0.25, 0, 2.25), (0.45, 0, 2.4)], [0.55, 0.35, 0.16, 0.05], CORK, segs=12),
                        shade(CORK, 0.85), mix(CORK, LILAC, 0.4)),
                blob("Star", 0.13, (0.15, -0.42, 1.65), BUTTER, subdiv=1, jitter=0)]
    if THEME_ID == "mushroom":
        out = [painted(blob("Cap", 0.85, (0, 0, 1.38), PINK, subdiv=2, squash=(1, 1, 0.45), jitter=0), shade(PINK, 0.8), PINK)]
        for d in range(5):
            da = d * math.tau / 5
            out.append(blob(f"Dot{d}", 0.12, (0.5 * math.cos(da), 0.5 * math.sin(da), 1.62), CREAM, subdiv=1, squash=(1, 1, 0.5), jitter=0))
        return out
    return []


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
