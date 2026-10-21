# Habitat overlay helpers (not an asset). An overlay dresses the base pad (the round goo_cork_stand) for one
# slime's habitat instead of replacing it (HABITATS.md "Overlays"). z=0 = the stand's dish rim (DECK above the stand
# bottom); a thin themed frame ring on the dish round the goo bed (outer radius HALF, keeps the FileMesh bbox
# centred on the pad) and props on the rim band only: nothing rises above the frame inside the mat circle, so the
# slime stays clear.
# Overlays are authored in a square layout (the old crate pad: x, y on a square loop, corners at (+-BAND, +-BAND));
# overlay_finish maps that onto the round dish (round_up): a point at square "radius" max(|x|, |y|) lands on the
# circle of that radius in the same direction. Small props move whole, long ones (ropes, bolsters, trims, the frame)
# bend round the ring.
# HABITAT_PREVIEW=1 draws the stand under the overlay for sheets; always run that with --no-export.
import math, os
import bmesh
from mathutils import Vector
from lib import *
from lib.shapes import obj_from_bm
from models._goo_jar import D, cork_stand

DECK = D["padSeatY"]  # the dish rim the overlay rests on (the game's PAD_DECK.y)
OUTER = 2 * D["padDeck"]["half"]  # frame outer diameter: the dish rim (7.5)
INNER = 2 * D["padDeck"]["matHalf"]  # frame inner diameter: just round the slime (5.2)
FRAME_H = 0.14
HALF = OUTER / 2
BAND = (INNER / 2 + HALF) / 2  # rim band centre line (studs from the centre)
PREVIEW = os.environ.get("HABITAT_PREVIEW") == "1"


def frame(name, top, side=None, seed=0, wobble=0.0, segs=6):
    """Flat ring on the deck (z 0..FRAME_H), authored square (round_up bends it round). wobble = random height of
    the top verts (organic edge)."""
    import random
    segs = max(segs, 10)
    side = side or shade(top, 0.75)
    R = random.Random(seed)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")

    def ring(h, z):
        pts = []
        for s in range(4):  # 4 sides, segs points each, counter-clockwise from the (-h, -h) corner
            for k in range(segs):
                t = -h + 2 * h * k / segs
                x, y = [(t, -h), (h, t), (-t, h), (-h, -t)][s]
                pts.append((x, y))
        return pts

    n = 4 * segs  # (round_up bends the square ring round; frame() keeps at least 10 points a side for that)
    o_lo = [bm.verts.new((x, y, 0)) for x, y in ring(HALF, 0)]
    i_lo = [bm.verts.new((x, y, 0)) for x, y in ring(INNER / 2, 0)]
    o_hi = [bm.verts.new((x, y, FRAME_H + R.uniform(0, wobble))) for x, y in ring(HALF, 0)]
    i_hi = [bm.verts.new((x, y, FRAME_H + R.uniform(0, wobble) * 0.5)) for x, y in ring(INNER / 2, 0)]

    def face(vs, c):
        f = bm.faces.new(vs)
        for lp in f.loops:
            lp[col] = c

    for k in range(n):
        k1 = (k + 1) % n
        face((o_hi[k], o_hi[k1], i_hi[k1], i_hi[k]), top)
        face((o_lo[k], i_lo[k], i_lo[k1], o_lo[k1]), shade(side, 0.8))
        face((o_lo[k], o_lo[k1], o_hi[k1], o_hi[k]), side)
        face((i_lo[k], i_hi[k], i_hi[k1], i_lo[k1]), side)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def band_spots(n, phase=0.0, inset=0.0):
    """n evenly spaced spots on the rim band (square loop), from the front-left corner, counter-clockwise.
    Returns (x, y, outward_deg). inset moves the loop toward the centre (negative = toward the edge)."""
    h = BAND - inset
    out = []
    for i in range(n):
        u = ((i + phase) / n) % 1.0 * 4
        s, t = int(u), u - int(u)
        t = -h + 2 * h * t
        x, y = [(t, -h), (h, t), (-t, h), (-h, -t)][s]
        out.append((x, y, math.degrees(math.atan2(y, x))))
    return out


CORNERS = [(s * BAND, t * BAND, math.degrees(math.atan2(t, s))) for s, t in ((-1, -1), (1, -1), (1, 1), (-1, 1))]


def check(parts, drop=0.0):
    """Print OVERLAY in deck space (before finish() recentres the mesh): bbox, centre offset, DROP (studs below
    the deck) and verts above the frame inside the mat square (should be 0)."""
    import bpy
    bpy.context.view_layer.update()
    vs = [p.matrix_world @ v.co for p in parts for v in p.data.vertices]
    xs, ys, zs = [v.x for v in vs], [v.y for v in vs], [v.z for v in vs]
    lim = INNER / 2 - 0.05
    inside = [v for v in vs if math.hypot(v.x, v.y) < lim and v.z > FRAME_H + 0.3]
    reach = max(math.hypot(v.x, v.y) for v in vs)
    print(f"OVERLAY {max(xs) - min(xs):.3f} x {max(zs) - min(zs):.3f} x {max(ys) - min(ys):.3f} "
          f"centre=({(max(xs) + min(xs)) / 2:.3f},{(max(ys) + min(ys)) / 2:.3f}) drop={-min(zs):.3f} "
          f"over_mat={len(inside)} reach={reach:.3f}")


def on_deck(parts, floor=0.0):
    """Flatten every vertex below `floor` onto it (sunk blob / crystal bases): finish() puts the origin at the
    lowest vertex, so anything under the deck would lift the whole overlay off it in the game."""
    for p in parts:
        mw = p.matrix_world
        inv = mw.inverted()
        for v in p.data.vertices:
            w = mw @ v.co
            if w.z < floor:
                w.z = floor
                v.co = inv @ w
        p.data.update()


def round_point(x, y):
    """The square layout's point (x, y) on the round dish: same direction, radius max(|x|, |y|)."""
    r = math.hypot(x, y)
    if r < 1e-6:
        return x, y
    k = max(abs(x), abs(y)) / r
    return x * k, y * k


RIGID = 1.6  # parts no wider than this move whole (keep their shape); wider ones bend vertex by vertex
GROUP = 0.7  # rigid parts this close to a group's first part move with it (a lollipop's stick and disc, a crystal cluster)
STAND_FOOT = 3.9  # the cork stand's foot radius: props stay over the stand, never past it
BEND_STEP = 1.2  # densify: the longest edge a bent part keeps (a 1.2 chord on the ring sags 0.06)


def densify(p, step=BEND_STEP):
    """Splits the part's long edges (in x / y) until none is longer than step, so a straight bar (a trim, a
    bolster) gets the in-between points it needs to bend round the ring. Kept coarse: each split costs triangles on
    every pad that shows the overlay."""
    mw = p.matrix_world
    bm = bmesh.new()
    bm.from_mesh(p.data)
    for _ in range(6):
        long = [e for e in bm.edges if ((mw @ e.verts[0].co) - (mw @ e.verts[1].co)).xy.length > step]
        if not long:
            break
        bmesh.ops.subdivide_edges(bm, edges=long, cuts=1, use_grid_fill=True)
    bm.to_mesh(p.data)
    bm.free()


def _groups(items):
    """Rigid items that belong together: each joins the first group whose seed (first item) centre is within
    GROUP of its own (no chaining, so a row of props along the band stays separate)."""
    groups = []
    for it in items:
        for g in groups:
            seed = g[0]["c"]
            if math.hypot(it["c"][0] - seed[0], it["c"][1] - seed[1]) <= GROUP:
                g.append(it)
                break
        else:
            groups.append([it])
    return groups


def round_up(parts):
    """Maps the square-authored overlay onto the round dish (see the header). Rigid props move whole, grouped with
    their neighbours; a group that rises above the frame then fits between the slime's circle (radius INNER / 2) and
    the stand's foot (STAND_FOOT): shrunk if it is wider than that ring, and pushed out until it clears the slime."""
    rigid = []
    for p in parts:
        mw = p.matrix_world
        ws = [mw @ v.co for v in p.data.vertices]
        if not ws:
            continue
        xs, ys = [w.x for w in ws], [w.y for w in ws]
        if max(max(xs) - min(xs), max(ys) - min(ys)) <= RIGID:
            rigid.append({"p": p, "ws": ws, "c": ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2)})
            continue
        densify(p)
        inv = mw.inverted()
        for v in p.data.vertices:
            w = mw @ v.co
            v.co = inv @ Vector((*round_point(w.x, w.y), w.z))
        p.data.update()
    for group in _groups(rigid):
        allw = [w for it in group for w in it["ws"]]
        xs, ys = [w.x for w in allw], [w.y for w in allw]
        cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
        nx, ny = round_point(cx, cy)
        r = math.hypot(nx, ny)
        tall = max(w.z for w in allw) > FRAME_H + 0.3
        k = 1.0
        if tall and r > 1e-6:
            # between the slime's circle and the stand's foot: shrink a group too wide for that ring, then centre it
            # in the room it has
            half = max(math.hypot(w.x - cx, w.y - cy) for w in allw)
            room = (STAND_FOOT - INNER / 2) / 2
            k = min(1.0, room / half) if half > 0 else 1.0
            half *= k
            want = min(max(r, INNER / 2 + half), STAND_FOOT - half)
            nx, ny = nx * want / r, ny * want / r
        for it in group:
            p = it["p"]
            inv = p.matrix_world.inverted()
            for v, w in zip(p.data.vertices, it["ws"]):
                v.co = inv @ Vector((nx + (w.x - cx) * k, ny + (w.y - cy) * k, w.z * k))
            p.data.update()


def overlay_finish(name, parts, drop=0.0):
    """finish() for an overlay: one mesh, origin bottom-centre. drop = how far it may hang below the deck (drips
    over the dish rim; the game's Habitats drop must match); anything lower is flattened. With HABITAT_PREVIEW=1
    the cork stand is drawn below the deck so the sheet shows the overlay on the pad; never export that."""
    round_up(parts)
    on_deck(parts, -drop)
    if PREVIEW:
        stand = cork_stand()
        for o in stand:
            o.location.z -= DECK
        return finish(name, parts + stand)
    check(parts, drop)
    return finish(name, parts)
