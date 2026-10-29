# Shared inside for the Exclusive base concept sketches (models/_base_x_*_scene.py). Not assets: design sketches.
# Every one of them keeps the base rules (contract/base-shapes.md §44): 4 floors at top(f), 8 pads per floor, a centre
# spiral ramp (one turn per floor), the only door on floor 1 at -Y, vat and lock button inside floor 1 either side of
# the door, see-through walls so the pads read from outside. Only the shell and the roof change per concept.
import math

import bmesh

from lib import obj_from_bm, shade
from models._base_concept_common import *

POST_R = 3.0
RAMP_OUT = 9.0
PAD_R = 16.5
DOOR_GAP = (-101.0, -79.0)


def core(R, deck_col, post_col, ramp_col, trims, floors=None, square=False):
    """Decks, centre post, spiral ramps and pads for every floor; vat, lock and two avatars on floor 1."""
    n = FLOORS if floors is None else floors
    Rs = list(R) if isinstance(R, (list, tuple)) else [R] * 4
    for i in range(n):
        f = i + 1
        z = top(f)
        R = Rs[i]
        if f == 1:
            if square:
                part("Deck1", (2 * R, 2 * R, 0.3), (0, 0, z - 0.15), deck_col)
            else:
                disc("Deck1", R, 0.3, (0, 0, z - 0.3), deck_col, segs=48)
            pad_ring(1, PAD_R, n=8, a0=-90 + 60, arc=240, trim=trims[i % len(trims)])
        else:
            if square:
                for sx, sy, w, d in ((0, (R + RAMP_OUT) / 2, 2 * R, R - RAMP_OUT), (0, -(R + RAMP_OUT) / 2, 2 * R, R - RAMP_OUT),
                                     ((R + RAMP_OUT) / 2, 0, R - RAMP_OUT, 2 * RAMP_OUT), (-(R + RAMP_OUT) / 2, 0, R - RAMP_OUT, 2 * RAMP_OUT)):
                    part(f"Deck{f}_{sx}_{sy}", (w, d, 0.6), (sx, sy, z - 0.3), deck_col)
            else:
                ring_wall(f"Deck{f}", RAMP_OUT, R, z - 0.6, 0.6, deck_col, segs=48, into=None)
            pad_ring(f, PAD_R, n=8, a0=-90 + 22.5, trim=trims[i % len(trims)])
        if f < n:
            helix_ramp(f"Ramp{f}", POST_R, RAMP_OUT, z, FLOOR_H, 90, 360, ramp_col, segs=32)
    disc("Post", POST_R, top(n) + FLOOR_H - 1.0, (0, 0, 1.0), post_col, segs=16)
    z1 = top(1)
    R = Rs[0]
    vat(*polar(PAD_R + 6.0, -60), z1)
    lock_button(*polar(PAD_R + 6.0, -120), z1)
    avatar(0, -12.5, z1)
    avatar(5, -(R + 6), 1.0, rgb(230, 120, 90))


def wedge_cone(name, r0, r1, z0, h, cols, n=16, a0=-90.0, into="shell", k=0.85):
    """A cone (or cone frustum r0 -> r1) made of n wedges, coloured in turn from cols (stripes)."""
    for i in range(n):
        a1 = a0 + i * 360 / n
        a2 = a0 + (i + 1) * 360 / n
        bm = bmesh.new()
        p = [polar(r0, a1), polar(r0, a2), polar(r1, a2), polar(r1, a1)]
        vs = [bm.verts.new((p[0][0], p[0][1], z0)), bm.verts.new((p[1][0], p[1][1], z0)),
              bm.verts.new((p[2][0], p[2][1], z0 + h)), bm.verts.new((p[3][0], p[3][1], z0 + h))]
        c = bm.verts.new((0, 0, z0))
        bm.faces.new(vs)
        bm.faces.new((vs[1], vs[0], c))
        if r1 > 0.01:
            ct = bm.verts.new((0, 0, z0 + h))
            bm.faces.new((vs[3], vs[2], ct))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        col = cols[i % len(cols)]
        add(obj_from_bm(f"{name}{i}", bm, col), shade(col, k), col, into)


def bands(R, cols, glass_from=3.0, z_floor_gap=0.0, segs=48, door=True, frame=None, frame_n=12, frame_r=0.6):
    """Per floor: a low solid kick wall, a glass band above it, and a solid lintel band; posts round the outside."""
    Rs = list(R) if isinstance(R, (list, tuple)) else [R] * 4
    for i in range(FLOORS):
        f = i + 1
        R = Rs[i]
        z = top(f) if f > 1 else 1.0
        col = cols[i % len(cols)]
        gap = DOOR_GAP if (door and f == 1) else None
        if f == 1 and door:
            ring_wall("Kick1", R - 0.8, R, z, glass_from, col, segs=segs, gap=gap)
            ring_wall("Glass1", R - 0.5, R - 0.3, z + glass_from, FLOOR_H - glass_from - 2.5, GLASS_C, segs=segs, gap=(-101, -79), into="glass")
        else:
            ring_wall(f"Kick{f}", R - 0.8, R, z, glass_from, col, segs=segs)
            ring_wall(f"Glass{f}", R - 0.5, R - 0.3, z + glass_from, FLOOR_H - glass_from - 2.5, GLASS_C, segs=segs, into="glass")
        ring_wall(f"Lintel{f}", R - 0.8, R + 0.2, z + FLOOR_H - 2.5, 2.5, shade(col, 0.92), segs=segs)
        if frame:
            for kk in range(frame_n):
                a = -90 + (kk + 0.5) * 360 / frame_n
                x, y = polar(R + 0.1, a)
                disc(f"Frame{f}_{kk}", frame_r, FLOOR_H, (x, y, z), frame, segs=8, into="shell")


GLASS_C = mix(GOO_HI, rgb(150, 214, 236), 0.55)
