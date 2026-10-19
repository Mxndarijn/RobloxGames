# Habitat overlay helpers (not an asset). An overlay dresses the base pad (phoenix_pad_crate) for one slime's
# habitat instead of replacing it (HABITATS.md "Overlays"). z=0 = the crate deck (DECK above the stand bottom);
# a thin themed frame round the crate mat (outer OUTER square, keeps the FileMesh bbox centred on the pad) and
# props on the rim band only: nothing rises above the frame inside the mat square, so the slime stays clear.
# HABITAT_PREVIEW=1 draws the crate under the overlay for sheets; always run that with --no-export.
import math, os
import bmesh
from mathutils import Vector
from lib import *
from lib.shapes import obj_from_bm
from models._pad_crate import DECK, crate_parts

OUTER = 7.5  # frame outer side: covers the crate Top board edge (7.4)
INNER = 5.2  # frame inner side: just round the 5.0 mat
FRAME_H = 0.14
HALF = OUTER / 2
BAND = (INNER / 2 + HALF) / 2  # rim band centre line (studs from the centre)
PREVIEW = os.environ.get("HABITAT_PREVIEW") == "1"


def frame(name, top, side=None, seed=0, wobble=0.0, segs=6):
    """Flat square ring on the deck (z 0..FRAME_H). wobble = random height of the top verts (organic edge)."""
    import random
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

    n = 4 * segs
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
    inside = [v for v in vs if abs(v.x) < lim and abs(v.y) < lim and v.z > FRAME_H + 0.3]
    print(f"OVERLAY {max(xs) - min(xs):.3f} x {max(zs) - min(zs):.3f} x {max(ys) - min(ys):.3f} "
          f"centre=({(max(xs) + min(xs)) / 2:.3f},{(max(ys) + min(ys)) / 2:.3f}) drop={-min(zs):.3f} "
          f"over_mat={len(inside)}")


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


def overlay_finish(name, parts, drop=0.0):
    """finish() for an overlay: one mesh, origin bottom-centre. drop = how far it may hang below the deck (drips
    over the crate edge; the game's Habitats drop must match); anything lower is flattened. With
    HABITAT_PREVIEW=1 the crate is drawn below the deck so the sheet shows the overlay on the pad; never export
    that."""
    on_deck(parts, -drop)
    if PREVIEW:
        return finish(name, parts + crate_parts(dz=-DECK))
    check(parts, drop)
    return finish(name, parts)
