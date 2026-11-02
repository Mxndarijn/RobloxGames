# Shared helpers for the obby drip options (obby_drip_a/b/c), not an asset.
# Climb's drip (games/steal-a-slime src/shared/ObbySections/Climb.luau `drip`) is three parts today:
#   * the drop: a 2-stud red hazard Ball (HAZARD red 215,20,25 at 0.25 transparency, dark ring outline) waiting under
#     the nozzle, then falling down the ladder; it must keep that colour, outline and a ball-sized touch shape;
#   * the nozzle: a dark "post" box 2.6 x 1.4 x 2.6 (70,60,90) whose bottom face touches the waiting drop's top;
#   * the drain cup: a dark "post" box 2.8 x 2.6 x 2.8 under the step you climb from (mostly hidden in that slab).
# Each option script builds all three. DRIP_PART picks what one run builds:
#   set (default): the preview scene (the nozzle with the drop waiting under it) for the sheet;
#   nozzle | drop | drain: one shippable mesh (pass --name obby_drip_<x>_<part> to iterate.py).
# DRIP_TINT=1 paints the drop value-only (light grey + white gloss) so the game's MeshPart.Color = HAZARD.color and the
# tells' flash toward HAZARD.hot keep working (vertex colour x Color, assumed multiply, see LESSONS [slimes]).
# 1 BU = 1 stud, Z up, front -Y. In the set the drop's centre is at (0, 0, DROP_Z) and the nozzle's bottom at
# DROP_Z + 1 (the game's spacing: nozzle centre = drop centre + DRIP / 2 + 0.7, height 1.4).
import math, os
import bmesh
from mathutils import Vector
from lib import *
from lib.goo import Ball, metaball_mesh, paint_goo
from lib.shapes import obj_from_bm, _place

PART = os.environ.get("DRIP_PART", "set")
TINT = os.environ.get("DRIP_TINT") == "1"

DRIP = 2.0
DROP_Z = 1.15  # drop centre in the preview set (its bottom just over the ground)
NOZZLE_Z = DROP_Z + DRIP / 2  # the nozzle's bottom

# The hazard look (ObbyParts.HAZARD): fixed. Shade only toward a deeper red below and a brighter red / gloss above.
HAZ = rgb(215, 20, 25)
HAZ_LO = rgb(176, 14, 24)
HAZ_HI = rgb(255, 92, 84)
HAZ_GLOSS = rgb(255, 214, 208)
HAZ_EDGE = rgb(90, 0, 10)

# The old post (70,60,90) lifted for the Roblox look (as the cannon's slate): it still reads darker than the course.
SLATE_LO = rgb(112, 104, 156)
SLATE = rgb(146, 138, 192)
SLATE_HI = rgb(186, 180, 228)
BORE = rgb(52, 40, 70)  # inside a mouth: dark on purpose, so the hole reads
BORE_HI = rgb(84, 68, 108)
LIME_LO = rgb(128, 212, 64)  # the Climb ladders' goo lime (150,230,70)
LIME = rgb(150, 230, 70)
LIME_HI = rgb(204, 250, 130)
WHITE = rgb(255, 255, 255)
INK = rgb(40, 30, 52)


def keep_smooth(o, on=True):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    sm = bm.faces.layers.int.get("keep_smooth") or bm.faces.layers.int.new("keep_smooth")
    for f in bm.faces:
        f[sm] = int(on)
    bm.to_mesh(o.data)
    bm.free()
    return o


def rev(name, prof, col_fn, segs=18, pos=(0, 0, 0), rot=(0, 0, 0), smooth=True, wobble=None, phase=0.0, loop=False):
    """Surface of revolution round local +Z. prof: [(r, z)], an end with r == 0 is a pole (closed shell).
    col_fn(i, co, n): colour for profile row segment i (the face between rows i and i + 1) at a corner with
    local position co and vertex normal n. wobble(i, a) -> radius factor. loop=True joins the last row back to
    the first (a closed ring band, no poles)."""
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    sm = bm.faces.layers.int.new("keep_smooth")
    rings = []
    for i, (r, z) in enumerate(prof):
        if r < 1e-6:
            rings.append(bm.verts.new((0, 0, z)))
            continue
        ring = []
        for k in range(segs):
            a = phase + k * math.tau / segs
            f = wobble(i, a) if wobble else 1.0
            ring.append(bm.verts.new((math.cos(a) * r * f, math.sin(a) * r * f, z)))
        rings.append(ring)
    rows = []
    for i in range(len(prof) if loop else len(prof) - 1):
        A, B = rings[i], rings[(i + 1) % len(prof)]
        faces = []
        for k in range(segs):
            k2 = (k + 1) % segs
            if isinstance(A, list) and isinstance(B, list):
                faces.append(bm.faces.new((A[k], A[k2], B[k2], B[k])))
            elif isinstance(A, list):
                faces.append(bm.faces.new((A[k], A[k2], B)))
            elif isinstance(B, list):
                faces.append(bm.faces.new((A, B[k2], B[k])))
        rows.append(faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    for i, faces in enumerate(rows):
        for f in faces:
            f.smooth = smooth
            f[sm] = int(smooth)
            for lp in f.loops:
                lp[layer] = col_fn(i, lp.vert.co, lp.vert.normal if smooth else f.normal)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm, smooth=smooth)


def flat(cols):
    """col_fn for rev(): one colour per profile segment."""
    return lambda i, co, n: cols[min(i, len(cols) - 1)]


def lit(lo, hi, i_cols=None):
    """col_fn: lo on faces turned down, hi on faces turned up (a cartoon top light)."""
    def f(i, co, n):
        t = max(0.0, min(1.0, 0.5 + 0.5 * n.z))
        return mix(lo, hi, t)
    return f


GLOSS_DIR = Vector((-0.42, -0.6, 0.68)).normalized()  # a soft studio key from up front-left


def drop_profile(height=2.2, rows=18, pinch=1.5):
    """A cartoon teardrop round local +Z: a round belly the size of the 2-stud ball (its centre at z = 0, bottom at
    z = -1), drawn up into a soft point at z = height - 1. x = sin t * sin(t/2)^pinch, z = cos t."""
    pts = []
    xs = [math.sin(math.pi * k / rows) * math.sin(math.pi * k / rows / 2) ** pinch for k in range(rows + 1)]
    m = max(xs)
    for k in range(rows + 1):
        t = math.pi * k / rows
        z = math.cos(t) * height / 2 + (height / 2 - 1.0)
        pts.append((xs[k] / m, z))
    pts.reverse()  # bottom pole first
    return pts


def drop(name, center=(0, 0, 0), height=2.2, pinch=1.5, segs=20, rows=18, scale=(1, 1, 1)):
    """The hazard drop: a teardrop over the 2-stud ball, deep red underneath, bright on top, a gloss spot front-left.
    With DRIP_TINT the same values in grey so MeshPart.Color carries the hazard red."""
    prof = drop_profile(height, rows, pinch)
    lo, base, hi, gloss = (HAZ_LO, HAZ, HAZ_HI, HAZ_GLOSS)
    if TINT:
        lo, base, hi, gloss = rgb(206, 206, 206), WHITE, WHITE, WHITE

    def col(i, co, n):
        t = max(0.0, min(1.0, (co.z + 1.0) / 1.6))
        c = mix(lo, base, min(1.0, t * 1.6))
        d = n.dot(GLOSS_DIR)
        if d > 0.55:
            c = mix(c, hi, min(1.0, (d - 0.55) / 0.25))
        if d > 0.86:
            c = mix(c, gloss, min(1.0, (d - 0.86) / 0.08))
        return c

    o = rev(name, prof, col, segs=segs)
    o.scale = scale
    o.location = center
    return o


def bolts(prefix, n, R, z, col, r=0.12, a0=0.0):
    out = []
    for k in range(n):
        a = a0 + k * math.tau / n
        out.append(keep_smooth(blob(f"{prefix}{k}", r, (R * math.cos(a), R * math.sin(a), z), col, subdiv=1,
                                    squash=(1, 1, 0.6), jitter=0), False))
    return out


def lip_goo(name, z, r, drips, seed=1, thick=0.2, col_lo=None, col=None, col_hi=None, n=14, res=0.07, tris=320):
    """A roll of red goo round a mouth's lip at height z (radius r) with short drips hanging off it:
    drips = [(angle_deg, length)]. Metaballs, so the drips grow out of the roll (no stuck-on beads)."""
    col_lo, col, col_hi = col_lo or HAZ_LO, col or HAZ, col_hi or HAZ_HI
    balls = []
    for k in range(n):
        a = k * math.tau / n
        wob = 1 + 0.12 * math.sin(3 * a + seed)
        balls.append(Ball((r * math.cos(a), r * math.sin(a), z), (thick * 1.25 * wob, thick * 1.25 * wob, thick * wob)))
    for ad, ln in drips:
        a = math.radians(ad)
        ox, oy = (r + thick * 0.15) * math.cos(a), (r + thick * 0.15) * math.sin(a)
        steps = 5
        for s in range(steps):
            t = s / (steps - 1)
            w = thick * (0.95 - 0.45 * t)
            balls.append(Ball((ox, oy, z - thick * 0.4 - ln * t), (w, w, w * 1.1)))
        balls.append(Ball((ox, oy, z - thick * 0.5 - ln - thick * 0.35), thick * 0.95))
    o = metaball_mesh(name, balls, resolution=res, tris=tris)

    def gc(co, nn):
        c = mix(col_lo, col, min(1.0, max(0.0, 0.5 + 0.5 * nn.z + 0.2)))
        if nn.dot(GLOSS_DIR) > 0.7:
            c = mix(c, col_hi, 0.6)
        return c

    return paint_goo(o, gc)


def drain_cup(prefix, x=0.0, y=0.0, lo=SLATE_LO, mid=SLATE, hi=SLATE_HI):
    """The drain the drop falls into: a round tub 2.8 wide, 2.6 tall (the old cup's box), a rolled rim, a dark hole
    with a red puddle down inside it, a bolted foot band. Mostly hidden in the slab above it in the game."""
    prof = [
        (0.0, 0.0), (1.2, 0.0), (1.3, 0.12), (1.22, 0.5),          # foot
        (1.18, 2.1), (1.34, 2.36), (1.4, 2.5), (1.3, 2.6),           # wall -> rolled rim
        (1.08, 2.56), (1.02, 2.2), (0.98, 1.3),                      # down inside
        (0.0, 1.28),                                                 # the floor of the hole (the puddle)
    ]
    cols = [lo, lo, mix(lo, mid, 0.5), mid, mix(mid, hi, 0.6), hi, mix(hi, mid, 0.3), BORE_HI, BORE, BORE, HAZ_LO]
    out = [rev(f"{prefix}Tub", prof, flat(cols), segs=20, pos=(x, y, 0), smooth=False)]
    # a lime band round the waist and bolts on it
    band = [(1.2, 0.62), (1.3, 0.68), (1.3, 0.92), (1.2, 0.98), (1.1, 0.8)]
    out.append(rev(f"{prefix}Band", band, flat([LIME_LO, LIME, LIME_HI, LIME_LO, LIME_LO]), segs=20, pos=(x, y, 0),
                   smooth=False, loop=True))
    for b in bolts(f"{prefix}Bolt", 6, 1.3, 0.8, SLATE_HI, r=0.1, a0=0.3):
        b.data.transform(__import__("mathutils").Matrix.Translation((x, y, 0)))
        out.append(b)
    # the red puddle in the hole, domed a little so it reads from above
    pud = [(0.0, 1.42), (0.9, 1.36), (1.0, 1.27), (0.0, 1.2)]
    out.append(rev(f"{prefix}Puddle", pud, flat([HAZ, HAZ_LO, HAZ_LO]), segs=20, pos=(x, y, 0)))
    return out


def finish_smooth(name, parts):
    """finish() that keeps the per-face smooth flag set by rev()/paint_goo/keep_smooth."""
    for p in parts:
        if "keep_smooth" not in p.data.attributes:
            p.data.attributes.new("keep_smooth", "INT", "FACE")
    o = finish(name, parts)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    return o


DROP_KW = {}  # an option's drop shape (height, pinch, ...), set before ship()


def ship(option, nozzle_fn):
    """Build what DRIP_PART asks for and finish it. nozzle_fn(z0) -> parts with the nozzle's bottom at z0."""
    if PART == "drop":
        return finish_smooth(f"obby_drip_{option}_drop", [drop("Drop", (0, 0, 1.0), **DROP_KW)])
    if PART == "drain":
        return finish_smooth(f"obby_drip_{option}_drain", drain_cup("Drain"))
    if PART == "nozzle":
        return finish_smooth(f"obby_drip_{option}_nozzle", nozzle_fn(0.0))
    parts = nozzle_fn(NOZZLE_Z) + [drop("Drop", (0, 0, DROP_Z), **DROP_KW)]
    return finish_smooth(f"obby_drip_{option}", parts)
