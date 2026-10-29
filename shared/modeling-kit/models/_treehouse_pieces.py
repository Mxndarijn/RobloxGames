# Tree House base (Exclusive): one builder per game mesh piece (design only, not uploaded). Every builder returns
# Blender objects at their plot position (kit = plot-local, see _round_base_layout: x right, y = plot z, z up). Tint
# pieces are painted in value-only greys; the game colours them with MeshPart.Color (multiply), one mesh for every skin.
# TINT names each piece's colour role; roles(tid) gives the colours (_treehouse_meshes.py writes them for the game).
#
# The look (concept models/_base_tree_scene.py): a giant tree. Floors 1-2 are rooms in the fat bark stump (bark kerb,
# glass band between bark posts, bark head band; roots flaring round the foot), floors 3-4 plank cabins widening into
# the crown (plank kerb, glass band between plank posts, a coloured rim band as the head band, bark struts and leaf
# clumps under their overhang). Leaves never hang over a glass band: the collars sit between the head band below and
# the kerb above, the canopy above the top floor's head band. The canopy carries a bird nest with the mascot. Owner
# exit: the hollow-branch slide, a bark tube corkscrewing down from the top floor's hatch (180) to polar(34, 200).
import colorsys
import math
import random

import bmesh

from lib import PALETTE, blob, box, cylinder, mix, obj_from_bm, rgb, shade, tube
from models._base_design_common import floor_top, polar
from models._pagoda_pieces import arc_wall, paint_under, revolve, surf_z
import models._treehouse_layout as L

P = PALETTE
FLOORS = 4
KERB_H = 3.0                  # solid kerb at the foot of every wall
HEAD_H = 2.4                  # solid head band under the deck above (floors 3-4: the coloured rim)
GLASS_Z0, GLASS_Z1 = KERB_H, L.WALL_H - HEAD_H   # the glass band, from the floor
POST_STEP = 30.0
DOOR_HALF = math.degrees(math.asin(L.DOOR_W / 2 / (L.ROOM_R[0] + L.WALL_T / 2)))
DOOR_GAP = (270 - DOOR_HALF, 270 + DOOR_HALF)
SLIDE_WIN = (160.0, 225.0)    # no leaf clumps or roots here: the slide winds down through it
TINT = {}


def g(v):
    """Value-only grey (a tint piece's paint)."""
    return (v, v, v, 1.0)


def arcs(f):
    """The wall's arcs on floor f (floor 1 leaves the doorway open)."""
    if f == 1:
        return [(DOOR_GAP[1], DOOR_GAP[0] + 360)]
    return [(0.0, 360.0)]


def post_angles(f, w):
    r = L.ROOM_R[f - 1]
    half = math.degrees(w / 2 / r)
    out = []
    for a0, a1 in arcs(f):
        if a1 - a0 < 360:
            out += [a0 + half, a1 - half]
        a = math.ceil(a0 / POST_STEP) * POST_STEP + 15
        while a < a1:
            if a1 - a0 >= 360 or (a - a0 > 2 * half + 4 and a1 - a > 2 * half + 4):
                out.append(a)
            a += POST_STEP
    return out


def _hatch(f, col, rim_col):
    """The owner hatch on the outer wall at HATCH_A: a round plank door (closed; the top floor's slide meets it)."""
    z = floor_top(f)
    out = []
    for nm, r, rad, d, c in (("HatchRim", L.room_out(f) + 0.15, 2.8, 0.9, rim_col), ("Hatch", L.room_out(f) + 0.35, 2.2, 0.8, col)):
        x, y = polar(r, L.HATCH_A)
        out.append(cylinder(f"{nm}{f}", rad, d, (x, y, z + 3.5), c, segs=14, rot=(0, 90, L.HATCH_A)))
    return out


# ---------------------------------------------------------------- floors 1-2: the bark stump
def bark_ridges(name, f, z0, h, a_from, a_to, step=7.5, seed=0):
    """Vertical bark ridges on the outer face of a bark band (darker value), staggered heights."""
    rr = random.Random(seed)
    r = L.room_out(f)
    out = []
    a = a_from + step / 2
    k = 0
    while a < a_to - step / 3:
        hh = h * rr.uniform(0.7, 1.0)
        zz = z0 + (h - hh) * rr.random()
        x, y = polar(r + 0.12, a + rr.uniform(-1.5, 1.5))
        out.append(box(f"{name}{k}", (0.5, rr.uniform(0.7, 1.3), hh), (x, y, zz + hh / 2), g(rr.uniform(0.62, 0.72)),
                       rot=(0, 0, a + rr.uniform(-1.5, 1.5))))
        a += step
        k += 1
    return out


def stump_room(f):
    """Bark frame of stump floor f (1-2): kerb, head band, bark posts, ridges; floor 1 the flared foot, the door's
    lintel and the roots; floor 2 the closed hatch. Tint: bark. The glass between the posts is room_glass(f)."""
    TINT[f"treehouse_room_{f}"] = "bark"
    z = floor_top(f)
    r_in, r_out = L.ROOM_R[f - 1], L.room_out(f)
    out = []
    for a0, a1 in arcs(f):
        out.append(arc_wall(f"Kerb{f}", 0, 0, r_in, r_out, z, KERB_H, g(0.92), a0, a1, lo=g(0.78)))
        out += bark_ridges(f"KRidge{f}_", f, z, KERB_H, a0, a1, seed=f)
    out.append(arc_wall(f"Head{f}", 0, 0, r_in, r_out, z + GLASS_Z1, HEAD_H, g(0.92), 0, 360, lo=g(0.84)))
    out += bark_ridges(f"HRidge{f}_", f, z + GLASS_Z1, HEAD_H, 0, 360, seed=10 + f)
    w = 1.6
    for k, a in enumerate(post_angles(f, w)):
        half = math.degrees(w / 2 / r_in)
        out.append(arc_wall(f"Post{f}_{k}", 0, 0, r_in - 0.1, r_out + 0.35, z + KERB_H, GLASS_Z1 - KERB_H, g(0.86),
                            a - half, a + half, step=2 * half + 1, lo=g(0.74)))
    if f == 1:
        # the doorway: a lintel from the door's top to the head band, bark jambs
        out.append(arc_wall("Lintel", 0, 0, r_in, r_out + 0.3, z + L.DOOR_H, GLASS_Z1 - L.DOOR_H, g(0.84),
                            DOOR_GAP[0], DOOR_GAP[1], step=4))
        # the flared foot: a bark skirt round the kerb, open at the door
        fl = revolve("Flare", [(r_out - 0.2, z + KERB_H - 0.2), (r_out + 0.6, z + 1.6), (r_out + 2.6, z - 0.15),
                               (r_out - 0.2, z - 0.15)], g(0.86), segs=40, lo=g(0.66),
                     a_from=DOOR_GAP[1] + 4, a_to=DOOR_GAP[0] + 356, closed=True)
        bm = bmesh.new()
        bm.from_mesh(fl.data)
        bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(fl.data)
        bm.free()
        out.append(fl)
        rr = random.Random(4)
        for k, a in enumerate((-48, -10, 28, 62, 98, 132, 236)):
            a += rr.uniform(-4, 4)
            s = rr.choice((-1, 1))
            p0 = (*polar(r_out - 0.2, a), z + KERB_H - 0.3)
            p1 = (*polar(r_out + 1.9, a + s * 2), z + 1.4)
            p2 = (*polar(r_out + 4.0, a + s * 5), z + 0.2)
            p3 = (*polar(r_out + 5.4, a + s * 9), z - 0.4)
            o = tube(f"Root{k}", [p0, p1, p2, p3], [1.5, 1.15, 0.75, 0.35], g(0.86), segs=7, twist_free=True)
            from lib import gradient
            gradient(o, g(0.62), g(0.9))
            out.append(o)
    else:
        out += _hatch(f, g(0.72), g(0.6))
    return out


# ---------------------------------------------------------------- floors 3-4: plank cabins
def cabin_room(f):
    """Plank frame of cabin floor f (3-4): a two-board kerb, plank posts and the closed hatch. Tint: plank. The head
    band is rim(f), the glass room_glass(f)."""
    TINT[f"treehouse_room_{f}"] = "plank"
    z = floor_top(f)
    r_in, r_out = L.ROOM_R[f - 1], L.room_out(f)
    out = [arc_wall(f"Board{f}a", 0, 0, r_in, r_out + 0.15, z, 1.5, g(0.86), 0, 360, lo=g(0.76)),
           arc_wall(f"Board{f}b", 0, 0, r_in, r_out, z + 1.5, KERB_H - 1.5, g(0.96), 0, 360, lo=g(0.88))]
    w = 1.2
    half = math.degrees(w / 2 / r_in)
    for k, a in enumerate(post_angles(f, w)):
        out.append(arc_wall(f"Post{f}_{k}", 0, 0, r_in - 0.1, r_out + 0.3, z + KERB_H, GLASS_Z1 - KERB_H, g(0.8),
                            a - half, a + half, step=2 * half + 1, lo=g(0.72)))
    # nail heads on the boards, one per post bay
    for k, a in enumerate(post_angles(f, w)):
        for dz in (0.75, 2.25):
            x, y = polar(r_out + 0.2 - (0.15 if dz > 1.5 else 0), a + 7.5)
            out.append(box(f"Nail{f}_{k}_{dz}", (0.2, 0.35, 0.35), (x, y, z + dz), g(0.55), rot=(0, 0, a + 7.5)))
    out += _hatch(f, g(0.7), g(0.58))
    return out


def rim(f):
    """The coloured head band of cabin floor f with a lip on top (it sits under the deck above / the canopy).
    Tint: rim_f."""
    TINT[f"treehouse_rim_{f}"] = f"rim_{f}"
    z = floor_top(f) + GLASS_Z1
    r_in, r_out = L.ROOM_R[f - 1], L.room_out(f)
    out = [arc_wall(f"Rim{f}", 0, 0, r_in - 0.05, r_out + 0.35, z, HEAD_H - 0.4, g(0.94), 0, 360, lo=g(0.82)),
           arc_wall(f"RimLip{f}", 0, 0, r_in - 0.05, r_out + 0.55, z + HEAD_H - 0.4, 0.4, g(1.0), 0, 360, step=7.5)]
    # a row of round studs along the band (painted trim)
    for k in range(24):
        a = k * 15 + 7.5
        x, y = polar(r_out + 0.4, a)
        out.append(cylinder(f"RimStud{f}_{k}", 0.35, 0.3, (x, y, z + 1.0), g(0.78), segs=6, rot=(0, 90, a)))
    return out


# ---------------------------------------------------------------- every floor
def room(f):
    return stump_room(f) if f <= 2 else cabin_room(f)


def room_glass(f):
    """Floor f's glass band between the kerb and the head band (a see-through glass slot in the game). Tint: glass."""
    TINT[f"treehouse_glass_{f}"] = "glass"
    z = floor_top(f)
    r_in, r_out = L.ROOM_R[f - 1], L.room_out(f)
    return [arc_wall(f"Glass{f}_{a0:.0f}", 0, 0, r_in + 0.3, r_out - 0.3, z + GLASS_Z0, GLASS_Z1 - GLASS_Z0, g(1.0),
                     a0, a1, lo=g(1.0)) for a0, a1 in arcs(f)]


def deck(f):
    """Plank deck ring of floor f (2-4) from the ramp shaft to deck_r(f), its edge fascia and the front landing.
    Tint: deck."""
    TINT[f"treehouse_deck_{f}"] = "deck"
    z = floor_top(f)
    R = L.deck_r(f)
    out = [arc_wall(f"Deck{f}", 0, 0, L.RAMP_OUT, R, z - L.DECK_T, L.DECK_T, g(0.9), 0, 360, step=7.5, lo=g(0.8)),
           arc_wall(f"Fascia{f}", 0, 0, R - 0.3, R + 0.3, z - 1.0, 1.0, g(0.7), 0, 360, step=7.5)]
    for k in range(24):
        a = k * 15
        p0, p1 = polar(L.RAMP_OUT + 0.3, a), polar(L.ROOM_R[f - 1] - 0.3, a)
        out.append(tube(f"Seam{f}_{k}", [(*p0, z + 0.01), (*p1, z + 0.01)], [0.12, 0.12], g(0.68), segs=3))
    lg = [l for l in L.LANDINGS if l["floor"] == f][0]
    out.append(box(f"Landing{f}", (lg["sy"], lg["sx"], L.DECK_T), (lg["x"], lg["y"], z - L.DECK_T / 2), g(0.94)))
    out.append(box(f"LandingEdge{f}", (lg["sy"], 0.3, 0.04), (lg["x"], lg["y"] - lg["sx"] / 2 + 0.3, z + 0.01), g(0.7)))
    return out


def post():
    """The centre post the ramp winds round (one storey, built on floor 1; every floor's slot lifts it). A trunk core:
    bark with two rings. Tint: bark."""
    TINT["treehouse_post"] = "bark"
    z = floor_top(1)
    out = [cylinder("Post", L.POST_R, L.FLOOR_H, (0, 0, z), g(0.82), segs=12)]
    for dz in (0.0, 7.5):
        out.append(cylinder(f"PostRing{dz}", L.POST_R + 0.25, 0.6, (0, 0, z + dz), g(0.66), segs=12))
    rr = random.Random(2)
    for k in range(8):
        a = k * 45 + rr.uniform(-8, 8)
        x, y = polar(L.POST_R, a)
        hh = rr.uniform(4, 7)
        out.append(box(f"PostRidge{k}", (0.35, 0.5, hh), (x, y, z + rr.uniform(1.5, 14.5 - hh) + hh / 2), g(0.66),
                       rot=(0, 0, a)))
    return out


def ramp():
    """One turn of the centre spiral ramp (floor 1 to 2; the slots lift it per floor) with plank treads. Tint: ramp."""
    TINT["treehouse_ramp"] = "ramp"
    z0 = floor_top(1)
    segs = 44
    bm = bmesh.new()
    rows = []
    for i in range(segs + 1):
        t = i / segs
        a = L.RAMP_A0 + L.RAMP_SWEEP * t
        z = z0 + L.FLOOR_H * t
        row = []
        for r in (L.RAMP_IN, L.RAMP_OUT):
            x, y = polar(r, a)
            row.append(bm.verts.new((x, y, z)))
            row.append(bm.verts.new((x, y, z - L.RAMP_T)))
        rows.append(row)
    for i in range(segs):
        a, b = rows[i], rows[i + 1]
        bm.faces.new((a[0], a[2], b[2], b[0]))
        bm.faces.new((a[1], b[1], b[3], a[3]))
        bm.faces.new((a[0], b[0], b[1], a[1]))
        bm.faces.new((a[2], a[3], b[3], b[2]))
    bm.faces.new((rows[0][0], rows[0][1], rows[0][3], rows[0][2]))
    bm.faces.new((rows[-1][0], rows[-1][2], rows[-1][3], rows[-1][1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    out = [obj_from_bm("Ramp", bm, g(0.95))]
    for k in range(1, 22):
        t = k / 22
        a = L.RAMP_A0 + L.RAMP_SWEEP * t
        x0, y0 = polar(L.RAMP_IN + 0.3, a)
        x1, y1 = polar(L.RAMP_OUT - 0.2, a)
        z = z0 + L.FLOOR_H * t + 0.03
        out.append(tube(f"Tread{k}", [(x0, y0, z), (x1, y1, z)], [0.14, 0.14], g(0.72), segs=3))
    # a bark edge along the outer rim (low, visual only)
    pts = []
    for i in range(0, segs + 1, 2):
        t = i / segs
        x, y = polar(L.RAMP_OUT - 0.15, L.RAMP_A0 + L.RAMP_SWEEP * t)
        pts.append((x, y, z0 + L.FLOOR_H * t - 0.25))
    out.append(tube("Edge", pts, [0.3] * len(pts), g(0.62), segs=4, twist_free=True))
    return out


# ---------------------------------------------------------------- under the cabins: struts and leaf collars
def struts(f):
    """Bark struts under cabin f's overhang, from its deck edge down onto the head band of the floor below.
    Tint: bark."""
    TINT[f"treehouse_struts_{f}"] = "bark"
    z = floor_top(f)
    R = L.deck_r(f)
    rb = L.room_out(f - 1)
    out = []
    for k in range(12):
        a = k * 30 + 15
        p0 = (*polar(R - 0.1, a), z - 1.0)
        p1 = (*polar(rb + 0.8, a), z - 1.8)
        p2 = (*polar(rb + 0.1, a), z - 2.45)
        out.append(tube(f"Strut{f}_{k}", [p0, p1, p2], [0.55, 0.5, 0.45], g(0.8), segs=6))
        # a bracket block where the strut meets the deck
        x, y = polar(R - 0.4, a)
        out.append(box(f"Bracket{f}_{k}", (1.0, 1.4, 0.5), (x, y, z - 1.15), g(0.66), rot=(0, 0, a)))
    return out


def _puff(name, r, pos, v, seed, squash=(1.15, 1.15, 0.78)):
    o = blob(name, r, pos, g(v), seed=seed, subdiv=2, squash=squash, jitter=0.1)
    from lib import gradient
    gradient(o, g(v * 0.68), g(min(1.0, v * 1.08)))
    return o


def leaf_band(f):
    """(z_lo, z_hi) the leaves under cabin f may fill: from the head band below up to this floor's kerb top."""
    z = floor_top(f)
    return z - L.DECK_T - HEAD_H, z + KERB_H


def leaves(f):
    """Leaf clumps hugging cabin f's deck edge: between the head band of the floor below and the kerb's top, never
    over a glass band; none where the slide winds down. Tint: leaf."""
    TINT[f"treehouse_leaves_{f}"] = "leaf"
    z = floor_top(f)
    z_lo, z_hi = leaf_band(f)
    zc = (z_lo + z_hi) / 2
    hh = (z_hi - z_lo) / 2           # the clump's half height
    R = L.deck_r(f) + 1.2
    rr = random.Random(60 + f)
    out = []
    n = 15
    for k in range(n):
        a = k * 360 / n + f * 13 + rr.uniform(-5, 5)
        if SLIDE_WIN[0] - 6 < a % 360 < SLIDE_WIN[1] + 6:
            continue
        big = rr.uniform(2.9, 3.4)
        sq = hh / big * 0.86
        out.append(_puff(f"Clump{f}_{k}", big, (*polar(R, a), zc), rr.uniform(0.86, 1.0), seed=f * 40 + k,
                         squash=(1.25, 1.25, sq)))
        for j, (da, dr, s) in enumerate(((-7.5, -0.4, 0.62), (7.0, 0.2, 0.55))):
            sm = big * s
            out.append(_puff(f"Clump{f}_{k}_{j}", sm, (*polar(R + dr, a + da), zc - hh + sm * 0.8 + 0.1),
                             rr.uniform(0.78, 0.95), seed=f * 40 + k * 3 + j + 200, squash=(1.2, 1.2, 0.8)))
    return out


# ---------------------------------------------------------------- the top: canopy, nest, slide
NATIVE_TOP = 4


def roof_prof(f=NATIVE_TOP):
    return L.roof(f, L.room_out(f))


def canopy(f=NATIVE_TOP):
    """The leaf roof over the top floor (built for floor 4, the game scales it by roof_k onto lower tops): a leafy
    shell on the roof's collider profile, covered in puffs that start at the head band's top. Tint: leaf."""
    TINT["treehouse_canopy"] = "leaf"
    prof = roof_prof(f)
    zt = prof[0][1]
    (r0, _), (r1, z1), (r1b, z1b), (r2, z2), (r3, z3) = prof
    shell = [(0.0, zt + 0.1), (L.ROOM_R[f - 1] - 0.5, zt + 0.1), (r0 + 0.3, zt + 0.25), (r0 + 0.5, zt + 1.0),
             (r1 + 0.4, z1 + 0.6), (r1b + 0.4, z1b + 0.6), (r2 + 0.3, z2 + 0.6), (r3 + 0.3, z3 + 0.5), (0.0, z3 + 0.2)]
    out = [paint_under(revolve("Canopy", shell, g(0.85), segs=40), 0.85, 0.5)]
    surf = [(r0, zt), (r1, z1), (r1b, z1b), (r2, z2), (r3, z3)]
    rr = random.Random(9)
    # rings of puffs, from the rim to the crown: (radius on the roof, count, puff radius, squash z)
    rings = [(r0 - 1.0, 17, 4.4, 0.55), (r1, 12, 5.4, 0.66), ((r1 + r1b) / 2, 11, 5.6, 0.7), (r1b, 10, 5.6, 0.72),
             ((r1b + r2) / 2, 8, 5.2, 0.72), (r2 + 0.5, 6, 4.6, 0.72)]
    k = 0
    for i, (rc, n, s, sq) in enumerate(rings):
        for j in range(n):
            a = j * 360 / n + i * 17 + rr.uniform(-6, 6)
            r = rc + rr.uniform(-0.8, 0.8)
            ss = s * rr.uniform(0.88, 1.12)
            zc = surf_z(surf, r) + ss * sq * 0.45
            if i == 0:
                zc = max(zc, zt + ss * sq - 0.3)   # its underside stays above the head band's foot
            v = rr.uniform(0.8, 1.0)
            out.append(_puff(f"Puff{k}", ss, (*polar(r, a), zc), v, seed=300 + k, squash=(1.15, 1.15, sq)))
            k += 1
    # the crown: a ring of big puffs round the nest, rising above the roof (visual only), so the tree tops out in a
    # round leafy dome with the nest sitting in its crater
    for j in range(7):
        a = j * 360 / 7 + 10 + rr.uniform(-6, 6)
        r = r3 + 5.8 + rr.uniform(-0.6, 0.6)
        ss = rr.uniform(3.8, 4.4)
        out.append(_puff(f"Crown{j}", ss, (*polar(r, a), z3 - 1.2), rr.uniform(0.86, 1.0), seed=500 + j,
                         squash=(1.0, 1.0, 0.8)))
    for j in range(9):
        a = j * 40 + 25 + rr.uniform(-6, 6)
        r = (r1 + r1b) / 2 + rr.uniform(-1, 1)
        ss = rr.uniform(5.0, 6.0)
        out.append(_puff(f"Mid{j}", ss, (*polar(r, a), surf_z(surf, r) + 2.2), rr.uniform(0.8, 0.96), seed=520 + j,
                         squash=(1.1, 1.1, 0.8)))
    return out


def nest(f=NATIVE_TOP):
    """The bird nest on the canopy's crown where the mascot sits: a twig bowl with a woven rim (built for floor 4,
    scaled with the canopy). Tint: bark."""
    TINT["treehouse_nest"] = "bark"
    prof = roof_prof(f)
    rc, zc = prof[-1]
    out = [cylinder("NestBowl", rc - 0.6, 2.0, (0, 0, zc - 0.6), g(0.78), segs=16, r_top=rc + 0.6)]
    from lib import gradient
    gradient(out[0], g(0.55), g(0.82))
    rr = random.Random(12)
    for k in range(14):
        a = k * 360 / 14
        pts = [(*polar(rc + 0.2, a), zc + 1.0 + rr.uniform(-0.2, 0.2)), (*polar(rc + 0.6, a + 22), zc + 1.5),
               (*polar(rc + 0.2, a + 44), zc + 1.0 + rr.uniform(-0.2, 0.2))]
        out.append(tube(f"Twig{k}", pts, [0.45, 0.55, 0.45], g(rr.uniform(0.72, 0.95)), segs=5))
    for k in range(5):
        a = k * 72 + 30
        p0 = (*polar(rc + 0.4, a), zc + 0.8)
        p1 = (*polar(rc + 2.4, a + 8), zc + 1.9)
        out.append(tube(f"Stick{k}", [p0, p1], [0.3, 0.15], g(0.7), segs=4))
    return out


SLIDE_C = polar(35.1, 196.0)   # the corkscrew's axis (outside the stump, inside the plot)
SLIDE_RHO = 2.1                # the corkscrew's radius
SLIDE_R = 1.7                  # the branch's radius
SLIDE_PITCH = 15.0             # drop per turn


def slide_path(f):
    """The hollow branch's centre line from top floor f's hatch: out of the wall, round into a corkscrew down the
    axis SLIDE_C, its mouth at the drop's landing (EXIT lands, polar(34, 200))."""
    cx, cy = SLIDE_C
    z = floor_top(f)
    hx, hy = polar(L.room_out(f) - 0.2, L.HATCH_A)
    pts = [(hx, hy, z + 3.5), (*polar(L.room_out(f) + 2.0, L.HATCH_A + 2), z + 3.2)]
    lx, ly = L.EXIT["lands"]
    phi0 = math.degrees(math.atan2(pts[-1][1] - cy, pts[-1][0] - cx))
    phi_end = math.degrees(math.atan2(ly - cy, lx - cx))
    z0, z1 = z + 2.0, 2.4
    turns = max(1, round((z0 - z1) / SLIDE_PITCH))
    # wind clockwise seen from above (phi decreasing): away from the wall first, round the outside
    sweep = (phi0 - phi_end) % 360 + 360 * (turns - 1)
    n = int(sweep / 20) + 2
    for i in range(1, n + 1):
        t = i / n
        phi = phi0 - sweep * t
        rho = SLIDE_RHO * min(1.0, 0.25 + t * 6)
        x, y = cx + rho * math.cos(math.radians(phi)), cy + rho * math.sin(math.radians(phi))
        pts.append((x, y, z0 + (z1 - z0) * t))
    pts.append((lx, ly, 1.6))
    return pts


def slide(f):
    """The owner's drop exit look from top floor f's hatch: a hollow bark branch corkscrewing down to the landing,
    bark rings along it and a dark open mouth at both ends. Never collides (the drop is scripted). Tint: bark."""
    TINT[f"treehouse_slide_{f}"] = "bark"
    pts = slide_path(f)
    o = tube(f"Branch{f}", pts, [SLIDE_R + 0.3] + [SLIDE_R] * (len(pts) - 2) + [SLIDE_R + 0.4], g(0.86), segs=12,
             twist_free=True)
    from lib import gradient
    gradient(o, g(0.72), g(0.92))
    out = [o]
    for k in range(3, len(pts) - 2, 3):
        a, b = pts[k], pts[k + 1]
        m = [(a[i] + b[i]) / 2 for i in range(3)]
        d = [b[i] - a[i] for i in range(3)]
        ln = math.sqrt(sum(v * v for v in d)) or 1.0
        out.append(tube(f"Ring{f}_{k}", [[m[i] - d[i] / ln * 0.25 for i in range(3)], [m[i] + d[i] / ln * 0.25 for i in range(3)]],
                        [SLIDE_R + 0.22] * 2, g(0.66), segs=12))
    # the dark open mouth at the landing, facing out along the last segment
    (ax, ay, az), (bx, by, bz) = pts[-2], pts[-1]
    d = (bx - ax, by - ay, bz - az)
    ln = math.sqrt(sum(v * v for v in d))
    tip = (bx + d[0] / ln * 0.05, by + d[1] / ln * 0.05, bz + d[2] / ln * 0.05)
    out.append(tube(f"Mouth{f}", [(bx - d[0] / ln * 0.2, by - d[1] / ln * 0.2, bz - d[2] / ln * 0.2), tip],
                    [SLIDE_R + 0.15, SLIDE_R + 0.15], g(0.3), segs=12))
    # a bark stub branch with a knot halfway (reads as a branch, not a pipe)
    m = pts[len(pts) // 2]
    out.append(tube(f"Stub{f}", [m, (m[0] + 2.2, m[1] - 0.6, m[2] + 1.8)], [0.8, 0.3], g(0.8), segs=5))
    return out


def exit_pool():
    """The goo pool at the drop's landing, with a goo trickle out of the branch's mouth (shown from floor 2 up, the
    same for every top floor). Tint: goo."""
    TINT["treehouse_exit_pool"] = "goo"
    lx, ly = L.EXIT["lands"]
    # the pool sits a little further out along the branch's last run, so the mouth pours into it
    out = [cylinder("PoolRim", 3.9, 0.55, (lx, ly, 0.75), g(0.62), segs=20),
           cylinder("PoolGoo", 3.4, 0.62, (lx, ly, 0.8), g(1.0), segs=20),
           blob("Splash", 1.3, (lx, ly, 1.45), g(1.0), subdiv=2, squash=(1.5, 1.5, 0.5), jitter=0.05)]
    for k in range(5):
        a = k * 72 + 20
        x, y = polar(2.4, a)
        out.append(blob(f"Drop{k}", 0.5, (lx + x, ly + y, 1.5), g(0.95), subdiv=1, squash=(1, 1, 0.7), jitter=0))
    return out


# ---------------------------------------------------------------- colours per skin
def strong(col, sat=0.6, min_v=0.78):
    h, s, v = colorsys.rgb_to_hsv(*col[:3])
    return colorsys.hsv_to_rgb(h, max(s, sat), max(v, min_v)) + (1.0,)


# per skin: bark, plank, rim_3, rim_4, leaf (theme palette keys, "P:<palette key>" or an rgb tuple)
SKIN_KEYS = {
    "classic": ("wood_d", "wood", "P:ranch_roof", (70, 196, 186), (124, 204, 92)),
    "garden": ("wood_d", "wood", "pink", "goo", "cork"),
    "crystal": ("wood_d", "wood", "lilac", "goo", "goo"),
    "starlight": ("wood_d", "wood", "goo", "pink", "metal"),
    "candy": ("wood_d", "wood", "metal", "butter", "pink"),
    "mushroom": ("wood_d", "wood", "goo", "pink", "leaves"),
    "fairground": ("P:ranch_wood_dark", "wood", "metal", "wood_d", (120, 200, 96)),
    "haunted": ("wood_d", "wood", "metal", "pink", "goo"),
    "beach": ("wood_d", "wood", "pink", "goo", (110, 200, 104)),
    "space": ("wood_d", "wood", "metal", "pink", "goo"),
    "winter": ("wood_d", "wood", "metal", "goo", (92, 170, 120)),
}


def roles(tid):
    """The tint colour per role in skin `tid`."""
    from models._base_design_common import theme

    TH = theme(tid)

    def key(k):
        if isinstance(k, tuple):
            return rgb(*k)
        return P[k[2:]] if k.startswith("P:") else TH[k]

    bark_k, plank_k, r3, r4, leaf_k = SKIN_KEYS[tid]
    return {
        "bark": mix(key(bark_k), rgb(150, 112, 86), 0.2),
        "plank": mix(key(plank_k), TH["cream"], 0.3),
        "deck": mix(key(plank_k), TH["cream"], 0.4),
        "rim_3": strong(key(r3), 0.6),
        "rim_4": strong(key(r4), 0.55),
        "leaf": strong(key(leaf_k), 0.5, 0.74) if tid != "classic" else key(leaf_k),
        "ramp": strong(TH["butter"], 0.55),
        "goo": TH["goo"],
        "glass": TH["glass"],
    }


# ---------------------------------------------------------------- the piece list
PIECES = {}
for _f in range(1, FLOORS + 1):
    PIECES[f"treehouse_room_{_f}"] = (lambda f: lambda: room(f))(_f)
    PIECES[f"treehouse_glass_{_f}"] = (lambda f: lambda: room_glass(f))(_f)
for _f in range(2, FLOORS + 1):
    PIECES[f"treehouse_deck_{_f}"] = (lambda f: lambda: deck(f))(_f)
    PIECES[f"treehouse_slide_{_f}"] = (lambda f: lambda: slide(f))(_f)
for _f in (3, 4):
    PIECES[f"treehouse_rim_{_f}"] = (lambda f: lambda: rim(f))(_f)
    PIECES[f"treehouse_struts_{_f}"] = (lambda f: lambda: struts(f))(_f)
    PIECES[f"treehouse_leaves_{_f}"] = (lambda f: lambda: leaves(f))(_f)
PIECES.update({"treehouse_post": post, "treehouse_ramp": ramp, "treehouse_canopy": canopy, "treehouse_nest": nest,
               "treehouse_exit_pool": exit_pool})
SHIP = dict(PIECES)


# ---- the slot plan (models/_treehouse_meshes.py writes it for the game, models/_base_treehouse_design.py previews it):
# a slot puts mesh `mesh` (built where its builder builds it) at offset `up` and uniform `scale`: vertex v -> up + v * k.
MASCOT_SCALE = 3.8           # the jar's goo_jar_mascot, about the MascotBall collider's 8 studs


def top_fit(f, native=NATIVE_TOP):
    """(up, k) that fit a piece built on top floor `native`'s roof onto top floor f's: scaled by roof_k about the
    roof's foot (the head band's top), as the layout's roof profile is."""
    k = L.roof_k(L.room_out(f)) / L.roof_k(L.room_out(native))
    zt, zn = floor_top(f) + L.WALL_H, floor_top(native) + L.WALL_H
    return zt - k * zn, k


def slot_plan():
    """Every slot; build the pieces first (their builders fill TINT, the slots' roles)."""
    slots = []

    def slot(floor, name, mesh, up=0.0, scale=1.0, show=None, glass=False):
        slots.append({"floor": floor, "name": name, "mesh": mesh, "up": up, "scale": scale, "show": show,
                      "role": TINT.get(mesh), "glass": glass})

    for f in range(1, FLOORS + 1):
        covered = None if f == FLOORS else "covered"
        top = None if f == FLOORS else "top"
        lift = floor_top(f) - floor_top(1)
        slot(f, "Room", f"treehouse_room_{f}")
        slot(f, "Glass", f"treehouse_glass_{f}", glass=True)
        slot(f, "PostLook", "treehouse_post", up=lift)
        if f > 1:
            slot(f, "Deck", f"treehouse_deck_{f}")
        if f >= 3:
            slot(f, "Rim", f"treehouse_rim_{f}")
            slot(f, "Struts", f"treehouse_struts_{f}")
            slot(f, "Leaves", f"treehouse_leaves_{f}")
        if f < FLOORS:
            slot(f, "RampLook", "treehouse_ramp", up=lift, show=covered)
        up, k = top_fit(f)
        slot(f, "Canopy", "treehouse_canopy", up=up, scale=k, show=top)
        slot(f, "Nest", "treehouse_nest", up=up, scale=k, show=top)
        slot(f, "MascotLook", "goo_jar_mascot", up=L.MASCOT_Z(f) - 0.3, scale=MASCOT_SCALE, show=top)
        if f > 1:
            slot(f, "Slide", f"treehouse_slide_{f}", show=top)
    slot(2, "ExitPool", "treehouse_exit_pool")
    return slots

