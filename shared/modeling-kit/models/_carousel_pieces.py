# Carousel Tent base: one builder per mesh piece (design only, not uploaded). Every builder returns Blender objects at
# their plot position (kit axes = plot-local, see _round_base_layout: x right, y = plot z with the door at -y, z up).
# Tint pieces are painted in value-only greys: the game colours them with MeshPart.Color (verified multiply, LESSONS),
# so one mesh serves every skin. TINT names each piece's colour role; roles(tid) maps roles to colours per skin.
#
# The look (concept models/_base_x_carousel_scene.py): every floor is a carousel deck behind a glass band between 16
# gold poles, with a cream kerb and head band and a scalloped striped valance with bulbs that flares out from the head
# band (it never comes lower than the head band, so it never hangs over a glass band). The top floor wears a striped
# big-top roof with a gold rim of bulbs, gold ribs, a finial with a teal pennant and the mascot on its plate; the
# owner's drop exit is a striped helter-skelter slide from the top floor's hatch (180 deg) round a pole down to the
# drop landing at polar(34, 200). Painted carousel horses on gold poles circle the outside of floor 1 as decor.
#
# Stripes: MeshPart.Color is one colour per mesh, so a red/cream stripe painted into one tinted mesh would come out as
# two shades of one hue in every skin. Every striped thing is split by stripe colour instead: the cream stripes ride
# in the cream frame meshes (role "cream"), the coloured ones in their own meshes (role "stripe"), so each skin gets a
# real two-colour stripe in its own colours. Gold (poles, rims, bulbs, finial) and the horses are fixed colour.
import colorsys
import math

import bmesh

from lib import PALETTE, blob, box, cylinder, mix, obj_from_bm, rgb, tube
from models._base_design_common import FLOOR_H, floor_top, polar
from models._pagoda_pieces import arc_wall, disc_on_wall, g, revolve
import models._carousel_layout as L

P = PALETTE
TINT = {}

R_IN = L.ROOM_R[0]            # every floor's room has the same radius (28): one mesh per piece fits every floor
R_OUT = L.room_out(1)         # 29
KERB_H = 2.6                  # cream kerb from the floor
HEAD_H = 2.8                  # cream head band under the deck above (the valance flares out from it)
GLASS_Z0, GLASS_Z1 = KERB_H, L.WALL_H - HEAD_H     # the glass band, above the floor (2.6 .. 12.6: 10 studs)
FACE_R = R_OUT + 0.15         # the frame's outer face
POLE_N = 16
POLE_A0 = 11.25               # poles between the 22.5-degree wall segments; two flank the door at 270 +- 11.25
POLE_R = 0.42
POLE_RING = 28.65
VAL_N = 32                    # valance stripes round the floor (16 cream, 16 coloured)
VAL_RUN, VAL_DROP = 2.15, 2.2  # the skirt flares from the wall face out by RUN while dropping DROP
SCALLOP = HEAD_H - VAL_DROP   # each stripe's scallop dips to the head band's bottom edge, never lower
VAL_T = 0.25
DOOR_SKIP = 15.0              # floor 1: no poles within this of the door (the jar's door ring, 14.5 wide, sits there)

GOLD = rgb(250, 200, 72)
GOLD_LO = rgb(240, 172, 52)
BULB = rgb(255, 244, 190)
TEAL = rgb(70, 190, 200)
CLASSIC_RED = rgb(226, 72, 80)


def door_arc():
    half = math.degrees(math.asin(L.DOOR_W / 2 / (R_IN + L.WALL_T / 2)))
    return 270.0 - half, 270.0 + half


def arcs(f):
    """The wall's arcs on floor f (floor 1 leaves the door open)."""
    if f == 1:
        a0, a1 = door_arc()
        return [(a1, a0 + 360.0)]
    return [(0.0, 360.0)]


def _grad(o, lo, hi):
    from lib import gradient
    gradient(o, lo, hi)
    return o


def ring(name, r_in, r_out, z0, h, a0, a1, col, lo=None, step=7.5, face_col=None):
    """A closed annular solid over the arc a0..a1 with shared vertices (8 tris a step, cheaper than arc_wall's boxes).
    face_col(k) -> colour of step k (paints the whole step), else a vertical gradient lo -> col."""
    n = max(1, int(math.ceil((a1 - a0) / step - 1e-9)))
    full = abs((a1 - a0) - 360.0) < 1e-6
    bm = bmesh.new()
    cols = []
    m = n if full else n + 1
    for k in range(m):
        a = a0 + (a1 - a0) * k / n
        x, y = polar(1.0, a)
        cols.append([bm.verts.new((x * r, y * r, z)) for r, z in ((r_in, z0), (r_out, z0), (r_out, z0 + h),
                                                                   (r_in, z0 + h))])
    steps = []
    for k in range(n):
        A, B = cols[k], cols[(k + 1) % m]
        steps.append([bm.faces.new((A[i], A[(i + 1) % 4], B[(i + 1) % 4], B[i])) for i in range(4)])
    if not full:
        bm.faces.new(list(reversed(cols[0])))
        bm.faces.new(cols[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if face_col is None:
        from lib import gradient_bm
        gradient_bm(bm, lo or col, col)
    else:
        layer = bm.loops.layers.color.new("Col")
        for fc in bm.faces:
            for lp in fc.loops:
                lp[layer] = face_col(0)
        for k, fs in enumerate(steps):
            for fc in fs:
                for lp in fc.loops:
                    lp[layer] = face_col(k)
    return obj_from_bm(name, bm)


def sheet(name, grid, normal, thick, front, back=None):
    """A closed thick sheet from a grid of surface points grid[i][j] (i across, j along), pushed back by `thick`
    along normal(i, j) (a unit Vector-like 3-tuple). front/back: colour or fn(i, j) -> colour for the front face."""
    bm = bmesh.new()
    ni, nj = len(grid), len(grid[0])
    F = [[bm.verts.new(grid[i][j]) for j in range(nj)] for i in range(ni)]
    B = []
    for i in range(ni):
        row = []
        for j in range(nj):
            n = normal(i, j)
            x, y, z = grid[i][j]
            row.append(bm.verts.new((x - n[0] * thick, y - n[1] * thick, z - n[2] * thick)))
        B.append(row)
    faces_front, faces_back = [], []
    for i in range(ni - 1):
        for j in range(nj - 1):
            faces_front.append(((i, j), bm.faces.new((F[i][j], F[i + 1][j], F[i + 1][j + 1], F[i][j + 1]))))
            faces_back.append(bm.faces.new((B[i][j + 1], B[i + 1][j + 1], B[i + 1][j], B[i][j])))
    edges = [(F[i][0], F[i + 1][0], B[i + 1][0], B[i][0]) for i in range(ni - 1)]
    edges += [(F[i + 1][nj - 1], F[i][nj - 1], B[i][nj - 1], B[i + 1][nj - 1]) for i in range(ni - 1)]
    edges += [(F[0][j + 1], F[0][j], B[0][j], B[0][j + 1]) for j in range(nj - 1)]
    edges += [(F[ni - 1][j], F[ni - 1][j + 1], B[ni - 1][j + 1], B[ni - 1][j]) for j in range(nj - 1)]
    for q in edges:
        bm.faces.new(q)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    back = back or front
    front_ij = {fc: ij for ij, fc in faces_front}
    for fc in bm.faces:
        if fc in front_ij:
            c = front(*front_ij[fc]) if callable(front) else front
        else:
            c = back(0, 0) if callable(back) else back
        for lp in fc.loops:
            lp[layer] = c
    return obj_from_bm(name, bm)


# ---------------------------------------------------------------- the valance
def _val_pt(a, d, zt):
    """A point on the valance skirt at angle a, d studs below its top edge (the skirt is a straight flare)."""
    x, y = polar(FACE_R + VAL_RUN * d / VAL_DROP, a)
    return (x, y, zt - d)


def _val_normal():
    n = (VAL_DROP, VAL_RUN)
    k = math.hypot(*n)
    return n[0] / k, n[1] / k   # outward, up


def valance(zt, parity, top_v, bot_v, cols=4):
    """The valance stripes of one parity (0 cream, 1 coloured) whose top edge sits on the wall face at zt."""
    out = []
    nr, nz = _val_normal()
    for k in range(VAL_N):
        if k % 2 != parity:
            continue
        a0 = k * 360.0 / VAL_N
        step = 360.0 / VAL_N
        grid = []
        for i in range(cols + 1):
            u = i / cols
            a = a0 + step * u
            dbot = VAL_DROP + SCALLOP * math.sin(math.pi * u)
            grid.append([_val_pt(a, dbot * t, zt) for t in (1.0, 0.0)])

        def normal(i, j, a0=a0, step=step):
            a = math.radians(a0 + step * i / cols)
            return (nr * math.cos(a), nr * math.sin(a), nz)

        def paint(i, j):
            return mix(bot_v, top_v, 0.6)

        out.append(sheet(f"Val{zt:.0f}_{k}", grid, normal, VAL_T, paint, g(0.7)))
    return out


def bulbs_on_valance(zt, name="Bulb"):
    out = []
    nr, nz = _val_normal()
    for k in range(0, VAL_N, 2):
        a = (k + 1.5) * 360.0 / VAL_N
        x, y, z = _val_pt(a, 1.75, zt)
        ox, oy = polar(nr * 0.2, a)
        out.append(blob(f"{name}{zt:.0f}_{k}", 0.36, (x + ox, y + oy, z + nz * 0.2), BULB, subdiv=1, jitter=0))
    return out


# ---------------------------------------------------------------- rooms
def room(f):
    """Cream frame of floor f: kerb with inset panels, head band (over the door on floor 1, with a lintel), the cream
    valance stripes and (floors 2-4) the closed owner hatch. Tint: cream. Floors 2-4 share one mesh (built on 2)."""
    name = "carousel_room_1" if f == 1 else "carousel_room"
    TINT[name] = "cream"
    z = floor_top(f)
    zt = z + L.WALL_H
    out = []
    for a0, a1 in arcs(f):
        out.append(ring(f"Kerb{f}", R_IN, FACE_R, z if f > 1 else z - 0.4, KERB_H + (0 if f > 1 else 0.4),
                        a0, a1, g(0.95), g(0.80)))
        # inset panels on the kerb between the poles (a darker value)
        for k in range(POLE_N):
            pa = POLE_A0 + k * 22.5
            b0, b1 = pa + 2.2, pa + 22.5 - 2.2
            if f == 1 and not (a0 <= b0 and b1 <= a1) and not (a0 <= b0 + 360 and b1 + 360 <= a1):
                continue
            out.append(ring(f"Panel{f}_{k}", FACE_R - 0.05, FACE_R + 0.12, z + 0.55, KERB_H - 1.1, b0, b1, g(0.74),
                            step=9.0))
    out.append(ring(f"Head{f}", R_IN, FACE_R, zt - HEAD_H, HEAD_H, 0, 360, g(0.95), g(0.88)))
    if f == 1:
        a0, a1 = door_arc()
        out.append(ring("Lintel", R_IN, FACE_R, z + L.DOOR_H, zt - HEAD_H - z - L.DOOR_H, a0 - 0.5, a1 + 0.5,
                        g(0.92), step=4.5))
    else:
        out.append(disc_on_wall(f"Hatch{f}", FACE_R - 0.2, L.HATCH_A, z + 3.2, 2.1, 1.0, g(0.55)))
        out.append(disc_on_wall(f"HatchRim{f}", FACE_R - 0.3, L.HATCH_A, z + 3.2, 2.6, 0.9, g(0.80)))
    out += valance(zt, 0, g(1.0), g(0.82))
    return out


def stripes(f=2):
    """The coloured valance stripes (every floor the same). Tint: stripe."""
    TINT["carousel_stripes"] = "stripe"
    return valance(floor_top(f) + L.WALL_H, 1, g(1.0), g(0.80))


def room_glass(f):
    """The glass band of floor f between the kerb and the head band (a see-through glass slot). Tint: glass."""
    name = "carousel_glass_1" if f == 1 else "carousel_glass"
    TINT[name] = "glass"
    z = floor_top(f)
    return [ring(f"Glass{f}_{a0:.0f}", R_IN + 0.35, R_IN + 0.65, z + GLASS_Z0, GLASS_Z1 - GLASS_Z0, a0, a1, g(1.0),
                 step=5.625) for a0, a1 in arcs(f)]


def _gold(o):
    return _grad(o, GOLD_LO, GOLD)


def gold(f):
    """Gold trim of floor f (fixed colour): 16 poles with collars, a rope ring along the valance's top edge, a trim
    ring on the kerb, the bulbs on the valance and the centre post of this storey. Floors 2-4 share one mesh."""
    name = "carousel_gold_1" if f == 1 else "carousel_gold"
    TINT[name] = None
    z = floor_top(f)
    zt = z + L.WALL_H
    out = []
    d0, d1 = door_arc()
    for k in range(POLE_N):
        a = POLE_A0 + k * 22.5
        if f == 1 and abs(a - 270.0) < DOOR_SKIP:
            continue
        x, y = polar(POLE_RING, a)
        z0, z1 = z + GLASS_Z0, z + GLASS_Z1
        out.append(_gold(cylinder(f"Pole{f}_{k}", POLE_R, z1 - z0, (x, y, z0), GOLD, segs=6)))
        for zc in (z0, z1 - 0.6):
            out.append(_gold(cylinder(f"Collar{f}_{k}_{zc:.0f}", POLE_R + 0.22, 0.6, (x, y, zc), GOLD, segs=6)))
    for a0, a1 in arcs(f):
        out.append(ring(f"KerbTrim{f}", FACE_R - 0.05, FACE_R + 0.3, z + KERB_H - 0.3, 0.3, a0, a1, GOLD, GOLD_LO))
    out.append(ring(f"ValRope{f}", FACE_R - 0.05, FACE_R + 0.35, zt - 0.35, 0.4, 0, 360, GOLD, GOLD_LO))
    out += bulbs_on_valance(zt)
    # the centre post of this storey (the post collider runs the whole storey)
    out.append(_gold(cylinder(f"Post{f}", L.POST_R, FLOOR_H, (0, 0, z), GOLD, segs=16)))
    for k in range(4):
        out.append(_gold(cylinder(f"PostRing{f}_{k}", L.POST_R + 0.25, 0.5, (0, 0, z + 1.0 + k * 4.0), GOLD,
                                  segs=12)))
    return out


def deck(f=2):
    """The carousel platform of an upper floor: a ring from the ramp shaft (r 8) to the wall's outer face, painted in
    alternating radial boards. Tint: deck. Built on floor 2, shared by floors 2-4."""
    TINT["carousel_deck"] = "deck"
    z = floor_top(f)
    r0, r1 = L.RAMP_OUT, L.deck_r(f)
    out = [ring(f"Deck{f}", r0, r1, z - L.DECK_T, L.DECK_T, 0, 360, g(0.9), step=11.25,
                face_col=lambda k: g(0.9 if k % 2 == 0 else 0.78))]
    out.append(ring(f"DeckEdge{f}", r0 - 0.05, r0 + 0.5, z - L.DECK_T - 0.1, L.DECK_T + 0.13, 0, 360, g(0.62),
                    step=11.25))
    return out


def ramp(f=2):
    """The spiral ramp arriving on floor f (from floor f - 1) plus floor f's landing. Tint: ramp. Built for floor 2."""
    TINT["carousel_ramp"] = "ramp"
    z0 = floor_top(f - 1)
    segs = 33
    bm = bmesh.new()
    rows = []
    for i in range(segs + 1):
        t = i / segs
        a = L.RAMP_A0 + L.RAMP_SWEEP * t
        z = z0 + FLOOR_H * t
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
    out = [_grad(obj_from_bm(f"Ramp{f}", bm, g(0.95)), g(0.78), g(0.95))]
    # tread stripes and an edge band (lighter / darker values)
    for k in range(1, 16):
        t = k / 16
        a = L.RAMP_A0 + L.RAMP_SWEEP * t
        x0, y0 = polar(L.RAMP_IN + 0.3, a)
        x1, y1 = polar(L.RAMP_OUT - 0.3, a)
        z = z0 + FLOOR_H * t + 0.03
        out.append(tube(f"Tread{f}{k}", [(x0, y0, z), (x1, y1, z)], [0.15, 0.15], g(0.72), segs=4))
    la0, la1 = L.ARCH_A - L.LANDING / 2, L.ARCH_A + L.LANDING / 2
    out.append(arc_wall(f"Landing{f}", 0, 0, L.RAMP_IN, L.RAMP_OUT, floor_top(f) - L.DECK_T, L.DECK_T, g(0.9),
                        la0 - 0.5, la1 + 0.5, step=5.0))
    return out


# ---------------------------------------------------------------- the big top
def roof_prof(f):
    return L.SPEC["ROOF"](f, L.room_out(f))


def _roof_pt(f, s, a):
    """Point on the roof at profile parameter s (0 eave .. 1 crown) and angle a; also the (outward, up) normal."""
    prof = roof_prof(f)
    lens = [math.hypot(prof[k + 1][0] - prof[k][0], prof[k + 1][1] - prof[k][1]) for k in range(len(prof) - 1)]
    tot = sum(lens)
    d = s * tot
    for k, ln in enumerate(lens):
        if d <= ln + 1e-9 or k == len(lens) - 1:
            t = min(1.0, d / ln)
            (r0, z0), (r1, z1) = prof[k], prof[k + 1]
            r, z = r0 + (r1 - r0) * t, z0 + (z1 - z0) * t
            run, rise = r0 - r1, z1 - z0
            n = math.hypot(run, rise)
            nr, nz = rise / n, run / n
            break
        d -= ln
    x, y = polar(r, a)
    return (x, y, z), (nr * math.cos(math.radians(a)), nr * math.sin(math.radians(a)), nz)


ROOF_GORES = 16
ROOF_ROWS = (0.0, 0.15, 0.32, 0.55, 0.75, 1.0)


def _knee(f):
    prof = roof_prof(f)
    lens = [math.hypot(prof[k + 1][0] - prof[k][0], prof[k + 1][1] - prof[k][1]) for k in range(len(prof) - 1)]
    return round(lens[0] / sum(lens), 4)


def _roof_rows(f):
    """Profile parameters at the knee too (so the mesh follows the collider facets exactly)."""
    prof = roof_prof(f)
    lens = [math.hypot(prof[k + 1][0] - prof[k][0], prof[k + 1][1] - prof[k][1]) for k in range(len(prof) - 1)]
    knee = lens[0] / sum(lens)
    return sorted(set([round(s, 4) for s in ROOF_ROWS] + [round(knee, 4)]))


def roof_gores(f, parity):
    out = []
    rows = _roof_rows(f)
    step = 360.0 / ROOF_GORES
    cols = 3
    for k in range(ROOF_GORES):
        if k % 2 != parity:
            continue
        a0 = k * step
        grid, norms = [], []
        for i in range(cols + 1):
            a = a0 + step * i / cols
            gr, nr = [], []
            for s in rows:
                p, n = _roof_pt(f, s, a)
                gr.append(p)
                nr.append(n)
            grid.append(gr)
            norms.append(nr)

        def paint(i, j, rows=rows):
            s = rows[j]
            return g(0.86 + 0.14 * min(1.0, s * 1.6))

        out.append(sheet(f"Gore{f}_{k}", grid, lambda i, j, norms=norms: norms[i][j], 0.5, paint, g(0.72)))
    return out


def roof_gold(f=4):
    """The roof's gold (fixed colour): eave rim with bulbs, a rib on every gore seam, the crown cap, the finial with
    its ball, the teal pennant and the mascot's plate. Built for floor 4; the game shifts it to the top floor."""
    TINT["carousel_roof_gold"] = None
    prof = roof_prof(f)
    (re, ze) = prof[0]
    (rc, zc) = prof[-1]
    out = [_gold(arc_wall("Rim", 0, 0, re - 1.0, re + 0.35, ze - 0.35, 0.8, GOLD, 0, 360, step=5.625))]
    for k in range(24):
        x, y = polar(re + 0.35, k * 15 + 7.5)
        out.append(blob(f"RimBulb{k}", 0.4, (x, y, ze + 0.05), BULB, subdiv=1, jitter=0))
    rows = _roof_rows(f)
    for k in range(ROOF_GORES):
        a = k * 360.0 / ROOF_GORES
        pts = []
        for s in (0.0, _knee(f), 1.0):
            p, n = _roof_pt(f, s, a)
            pts.append((p[0] + n[0] * 0.1, p[1] + n[1] * 0.1, p[2] + n[2] * 0.1))
        out.append(_gold(tube(f"Rib{k}", pts, [0.28] * len(pts), GOLD, segs=4)))
    mz = L.SPEC["MASCOT_Z"](f)
    out.append(_gold(cylinder("CrownCap", rc + 0.5, 1.2, (0, 0, zc - 0.6), GOLD, segs=16, r_top=rc - 0.2)))
    out.append(_gold(cylinder("Finial", 0.5, mz - zc - 0.4, (0, 0, zc + 0.4), GOLD, segs=8)))
    out.append(blob("FinialBall", 1.1, (0, 0, zc + 2.0), GOLD, subdiv=2, jitter=0))
    out.append(_gold(cylinder("Plate", 1.2, 0.5, (0, 0, mz - 0.9), GOLD, segs=12, r_top=2.4)))
    out.append(_gold(cylinder("PlateRim", 2.4, 0.4, (0, 0, mz - 0.4), GOLD, segs=16)))
    # pennant: a flat triangle flag flying off the finial toward +x (seen from the front and the side)
    bm = bmesh.new()
    zf = zc + 3.6
    th = 0.25
    tri = [(0.4, 0.0, zf), (0.4, 0.0, zf + 2.2), (4.6, 0.0, zf + 0.9)]
    vs = [bm.verts.new((x, y - th / 2, z)) for x, y, z in tri] + [bm.verts.new((x, y + th / 2, z)) for x, y, z in tri]
    for fc in ((0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)):
        bm.faces.new([vs[i] for i in fc])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    out.append(_grad(obj_from_bm("Pennant", bm, TEAL), mix(TEAL, rgb(30, 90, 100), 0.25), TEAL))
    return out


# ---------------------------------------------------------------- the helter-skelter (owner drop exit look)
SLIDE_C = polar(35.1, 191.0)  # the slide's pole: its trough stays outside every valance (r >= 31.4) and inside r 39
SLIDE_RS = 2.6                # spiral radius (trough centre line)
SLIDE_W = 0.95                # trough half width
SLIDE_SEG = 2.2               # stripe length along the slide
SLIDE_SLOPE = 25.0
U_PROFILE = [(-0.95, 0.9), (-0.95, -0.15), (0.95, -0.15), (0.95, 0.9), (0.75, 0.9), (0.75, 0.1), (-0.75, 0.1),
             (-0.75, 0.9)]


def _tangent_pts(c, rs, p):
    """The two points where tangent lines from p touch the circle (c, rs), as angles (degrees) round c."""
    dx, dy = p[0] - c[0], p[1] - c[1]
    d = math.hypot(dx, dy)
    base = math.degrees(math.atan2(dy, dx))
    h = math.degrees(math.acos(rs / d))
    return [base + h, base - h]


def slide_path(f):
    """3D centre line (trough floor) from floor f's hatch down to the drop landing: a short chute out from the hatch,
    a spiral round the pole, a run-out to the landing."""
    cx, cy = SLIDE_C
    H = polar(R_OUT + 0.3, L.HATCH_A)
    Lx, Ly = L.EXIT["lands"]
    z_h = floor_top(f) + 1.3
    z_l = 1.25
    best = None
    for s in (1, -1):
        def vel(phi):
            r = math.radians(phi)
            return (-s * math.sin(r), s * math.cos(r))
        ent = [phi for phi in _tangent_pts(SLIDE_C, SLIDE_RS, H)
               if ((cx + SLIDE_RS * math.cos(math.radians(phi)) - H[0]) * vel(phi)[0]
                   + (cy + SLIDE_RS * math.sin(math.radians(phi)) - H[1]) * vel(phi)[1]) > 0]
        ext = [phi for phi in _tangent_pts(SLIDE_C, SLIDE_RS, (Lx, Ly))
               if ((Lx - cx - SLIDE_RS * math.cos(math.radians(phi))) * vel(phi)[0]
                   + (Ly - cy - SLIDE_RS * math.sin(math.radians(phi))) * vel(phi)[1]) > 0]
        phs, phe = ent[0], ext[0]
        ps = (cx + SLIDE_RS * math.cos(math.radians(phs)), cy + SLIDE_RS * math.sin(math.radians(phs)))
        # how close the entry chute comes to the building
        near = min(math.hypot(H[0] + (ps[0] - H[0]) * t, H[1] + (ps[1] - H[1]) * t) for t in (0.5, 0.75, 1.0))
        if best is None or near > best[0]:
            best = (near, s, phs, phe, ps)
    _, s, phs, phe, ps = best
    pe = (cx + SLIDE_RS * math.cos(math.radians(phe)), cy + SLIDE_RS * math.sin(math.radians(phe)))
    len_in = math.hypot(ps[0] - H[0], ps[1] - H[1])
    len_out = math.hypot(Lx - pe[0], Ly - pe[1])
    z_s = z_h - 0.12 * len_in
    z_e = z_l + 0.3 * len_out
    d0 = (s * (phe - phs)) % 360.0
    drop = z_s - z_e
    want = drop / math.tan(math.radians(SLIDE_SLOPE)) / SLIDE_RS
    n = max(0, round((want - math.radians(d0)) / math.tau))
    sweep = d0 + 360.0 * n
    pts = [(H[0], H[1], z_h), ((H[0] + ps[0]) / 2, (H[1] + ps[1]) / 2, (z_h + z_s) / 2)]
    steps = max(4, int(sweep / 12))
    for i in range(steps + 1):
        t = i / steps
        phi = math.radians(phs + s * sweep * t)
        pts.append((cx + SLIDE_RS * math.cos(phi), cy + SLIDE_RS * math.sin(phi), z_s + (z_e - z_s) * t))
    pts.append(((pe[0] + Lx) / 2, (pe[1] + Ly) / 2, (z_e + z_l) / 2))
    pts.append((Lx, Ly, z_l))
    return pts, {"sweep": sweep, "pitch": drop / (sweep / 360.0) if sweep else 0, "z_s": z_s}


def _frames(pts):
    from mathutils import Vector
    out = []
    for i in range(len(pts)):
        a = Vector(pts[max(i - 1, 0)])
        b = Vector(pts[min(i + 1, len(pts) - 1)])
        t = (b - a).normalized()
        side = t.cross(Vector((0, 0, 1)))
        side = side.normalized() if side.length > 1e-6 else Vector((1, 0, 0))
        up = side.cross(t).normalized()
        out.append((Vector(pts[i]), side, up))
    return out


def _resample(pts, step):
    """Points along the polyline every `step` studs (plus the corners), with their running length."""
    from mathutils import Vector
    P = [Vector(p) for p in pts]
    out = [(P[0], 0.0)]
    run = 0.0
    for a, b in zip(P, P[1:]):
        ln = (b - a).length
        n = max(1, int(math.ceil(ln / step)))
        for k in range(1, n + 1):
            out.append((a + (b - a) * (k / n), run + ln * k / n))
        run += ln
    return out


def _trough(name, pts, col):
    """A closed U-trough solid along pts (ring of U_PROFILE per point, three quads per end cap)."""
    bm = bmesh.new()
    rings = []
    for p, side, up in _frames(pts):
        rings.append([bm.verts.new(p + side * u + up * v) for u, v in U_PROFILE])
    n = len(U_PROFILE)
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    for ring in (rings[0], rings[-1]):
        for q in ((0, 1, 6, 7), (1, 2, 5, 6), (2, 3, 4, 5)):
            bm.faces.new([ring[i] for i in q])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, col)


def slide(f, parity):
    """The helter-skelter on top floor f: stripes of one parity (0 cream: plus the pole, struts and landing mat;
    1 coloured: plus the pole's top flag). Not a collider; the drop itself is scripted."""
    path, info = slide_path(f)
    dense = _resample(path, 1.1)
    out = []
    seg = []
    k = 0
    for p, run in dense:
        idx = int(run // SLIDE_SEG)
        if seg and idx != k:
            seg.append(tuple(p))
            if k % 2 == parity and len(seg) >= 2:
                out.append(_grad(_trough(f"Slide{f}_{k}", seg, g(1.0)), g(0.82), g(1.0)))
            seg = [tuple(p)]
            k = idx
        else:
            seg.append(tuple(p))
    if seg and k % 2 == parity and len(seg) >= 2:
        out.append(_grad(_trough(f"Slide{f}_{k}", seg, g(1.0)), g(0.82), g(1.0)))
    cx, cy = SLIDE_C
    ztop = info["z_s"] + 2.6
    if parity == 0:
        out.append(_grad(cylinder(f"SlidePole{f}", 0.6, ztop - 0.6, (cx, cy, 0.6), g(0.95), segs=10), g(0.8), g(0.95)))
        out.append(cylinder(f"SlideKnob{f}", 0.9, 0.5, (cx, cy, ztop), g(0.9), segs=10, r_top=0.3))
        # struts from the pole to the trough every half turn
        s_pts = [p for p in path[2:-2]]
        for i in range(0, len(s_pts), 15):
            x, y, z = s_pts[i]
            ux, uy = x - cx, y - cy
            m = math.hypot(ux, uy)
            ix, iy = cx + ux / m * 0.5, cy + uy / m * 0.5
            ox, oy = cx + ux / m * (SLIDE_RS - SLIDE_W + 0.1), cy + uy / m * (SLIDE_RS - SLIDE_W + 0.1)
            out.append(tube(f"Strut{f}_{i}", [(ix, iy, z - 0.1), (ox, oy, z - 0.1)], [0.18, 0.18], g(0.85), segs=4))
        Lx, Ly = L.EXIT["lands"]
        out.append(cylinder(f"Mat{f}", 2.0, 0.25, (Lx, Ly, 0.95), g(0.92), segs=16))
    else:
        bm = bmesh.new()
        tri = [(cx + 0.5, cy, ztop - 0.2), (cx + 0.5, cy, ztop - 1.8), (cx + 3.0, cy, ztop - 1.0)]
        vs = [bm.verts.new((x, y - 0.12, z)) for x, y, z in tri] + [bm.verts.new((x, y + 0.12, z)) for x, y, z in tri]
        for fc in ((0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)):
            bm.faces.new([vs[i] for i in fc])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        out.append(obj_from_bm(f"SlideFlag{f}", bm, g(1.0)))
        Lx, Ly = L.EXIT["lands"]
        out.append(arc_wall(f"MatRing{f}", Lx, Ly, 1.6, 2.1, 1.18, 0.12, g(0.95), 0, 360, step=22.5))
    return out


def roof_cream(f):
    """Top floor f's cream roof gores (+ on floors 2-4 the slide's cream stripes, pole and mat). Tint: cream."""
    TINT[f"carousel_roof_cream_{f}"] = "cream"
    out = roof_gores(f, 0)
    if f > 1:
        out += slide(f, 0)
    return out


def roof_stripe(f):
    """Top floor f's coloured roof gores (+ on floors 2-4 the slide's coloured stripes and flag). Tint: stripe."""
    TINT[f"carousel_roof_stripe_{f}"] = "stripe"
    out = roof_gores(f, 1)
    if f > 1:
        out += slide(f, 1)
    return out


# ---------------------------------------------------------------- carousel horses round floor 1 (decor)
HORSE_R = 32.0                 # between the wall (29) and the moat (34.5), under the valance's outer edge (r 31.9)
# between floor 1's pads (so they don't stand in front of a slime), clear of the door/bridge (270) and the slide (191)
HORSE_ANGLES = (-16.8, 19.6, 56.1, 92.5, 128.9, 165.4, 238.0, 302.0)
HORSE_COLS = [rgb(252, 244, 228), rgb(250, 168, 196), rgb(150, 206, 250), rgb(252, 222, 130), rgb(200, 176, 240),
              rgb(160, 226, 196), rgb(252, 244, 228), rgb(250, 168, 196)]
SADDLE = [rgb(226, 72, 80), rgb(70, 190, 200), rgb(226, 72, 80), rgb(150, 110, 210)]


def horse(k, a):
    col = HORSE_COLS[k % len(HORSE_COLS)]
    lo = mix(col, rgb(120, 100, 110), 0.25)
    x, y = polar(HORSE_R, a)
    # the horse faces along the circle (counter-clockwise), the way a carousel turns
    fx, fy = -math.sin(math.radians(a)), math.cos(math.radians(a))
    ox, oy = math.cos(math.radians(a)), math.sin(math.radians(a))
    bob = 3.6 + (k % 2) * 1.2

    def P(u, v, w):
        """u forward, v outward, w up from the horse's belly line."""
        return (x + fx * u + ox * v, y + fy * u + oy * v, bob + w)

    yaw = math.degrees(math.atan2(fy, fx))
    out = []
    out.append(_grad(blob(f"HBody{k}", 1.0, P(0, 0, 0.9), col, subdiv=2, squash=(2.0, 0.85, 0.95), jitter=0,
                          rot=(0, 0, yaw)), lo, col))
    out.append(_grad(tube(f"HNeck{k}", [P(1.3, 0, 1.1), P(1.9, 0, 2.2), P(2.2, 0, 2.9)], [0.55, 0.5, 0.45], col,
                          segs=6), lo, col))
    out.append(_grad(blob(f"HHead{k}", 0.62, P(2.7, 0, 2.9), col, subdiv=2, squash=(1.6, 0.8, 0.85), jitter=0,
                          rot=(0, 15, yaw)), lo, col))
    mane = shade_c = mix(col, rgb(140, 90, 120), 0.45)
    for j, (u, w) in enumerate(((1.4, 1.75), (1.8, 2.5), (2.15, 3.25))):
        out.append(blob(f"HMane{k}_{j}", 0.34, P(u - 0.25, 0, w + 0.25), mane, subdiv=1, jitter=0))
    # legs: galloping (front legs bent forward, back legs stretched back)
    for side in (-0.4, 0.4):
        out.append(tube(f"HFL{k}{side}", [P(1.1, side, 0.5), P(1.7, side, -0.2), P(1.4, side, -0.9)],
                        [0.24, 0.2, 0.18], col, segs=5))
        out.append(tube(f"HBL{k}{side}", [P(-1.2, side, 0.5), P(-1.9, side, -0.4), P(-2.5, side, -0.9)],
                        [0.26, 0.2, 0.18], col, segs=5))
    out.append(tube(f"HTail{k}", [P(-1.9, 0, 1.2), P(-2.6, 0, 0.9), P(-2.9, 0, 0.1)], [0.25, 0.3, 0.15], mane,
                    segs=5))
    sad = SADDLE[k % len(SADDLE)]
    out.append(box(f"HSaddle{k}", (1.3, 1.95, 0.28), P(0.0, 0, 1.85), sad, rot=(0, 0, yaw)))
    # the pole runs through the horse from the plinth to under the valance
    px, py = x, y
    out.append(_gold(cylinder(f"HPole{k}", 0.24, 12.6 - 1.0, (px, py, 1.0), GOLD, segs=6)))
    out.append(blob(f"HPoleTop{k}", 0.42, (px, py, 12.6), GOLD, subdiv=1, jitter=0))
    out.append(_gold(cylinder(f"HPlinth{k}", 0.9, 0.5, (px, py, 0.9), GOLD, segs=10, r_top=0.6)))
    del shade_c
    return out


def horses():
    """Eight painted carousel horses on gold poles round floor 1 (fixed colour; no colliders)."""
    TINT["carousel_horses"] = None
    out = []
    for k, a in enumerate(HORSE_ANGLES):
        out += horse(k, a)
    return out


# ---------------------------------------------------------------- tints per skin
def strong(col, sat=0.72, min_v=0.80):
    h, s, v = colorsys.rgb_to_hsv(*col[:3])
    return colorsys.hsv_to_rgb(h, max(s, sat), max(v, min_v)) + (1.0,)


# The stripe colour per skin, from the skin's own palette keys (never copied values). "awning:0" = TH["awning"][0].
STRIPE_KEY = {
    "classic": None,            # carousel red (the concept's)
    "garden": "goo", "crystal": "goo", "starlight": "cork", "candy": "goo", "mushroom": "goo",
    "fairground": "awning:0", "haunted": "goo", "beach": "goo", "space": "lilac", "winter": "metal",
}


def roles(tid):
    """The tint colour per role (cream, stripe, glass, deck, ramp) in skin `tid`."""
    from models._base_design_common import theme

    TH = theme(tid)
    key = STRIPE_KEY.get(tid, "goo")
    if key is None:
        stripe = CLASSIC_RED
    elif ":" in key:
        k, i = key.split(":")
        stripe = strong(TH[k][int(i)], 0.55, 0.80)
    else:
        stripe = strong(TH[key], 0.55, 0.80)
    return {
        "cream": TH["cream"],
        "stripe": stripe,
        "glass": TH["glass"],
        "deck": TH["wood"],
        "ramp": strong(TH["butter"], 0.6),
    }


# PIECES: name -> builder (measuring through iterate.py, see _carousel_piece.py); every one ships as is (SHIP).
PIECES = {
    "carousel_room_1": lambda: room(1), "carousel_room": lambda: room(2),
    "carousel_stripes": lambda: stripes(2),
    "carousel_glass_1": lambda: room_glass(1), "carousel_glass": lambda: room_glass(2),
    "carousel_gold_1": lambda: gold(1), "carousel_gold": lambda: gold(2),
    "carousel_deck": lambda: deck(2), "carousel_ramp": lambda: ramp(2),
    "carousel_roof_gold": lambda: roof_gold(4),
    "carousel_horses": horses,
}
for _f in range(1, 5):
    PIECES[f"carousel_roof_cream_{_f}"] = (lambda f: (lambda: roof_cream(f)))(_f)
    PIECES[f"carousel_roof_stripe_{_f}"] = (lambda f: (lambda: roof_stripe(f)))(_f)
SHIP = dict(PIECES)
# which pieces are built on which floor (the game shifts shared ones up by floor_top(f) - floor_top(native))
NATIVE = {"carousel_room": 2, "carousel_stripes": 2, "carousel_glass": 2, "carousel_gold": 2, "carousel_deck": 2,
          "carousel_ramp": 2, "carousel_roof_gold": 4}
GLASS = {"carousel_glass_1", "carousel_glass"}


def tint_of(name):
    """The tint role of a piece (None: fixed colour)."""
    if name not in TINT:
        PIECES[name]()  # builders register their role; run once if needed
    return TINT.get(name)
