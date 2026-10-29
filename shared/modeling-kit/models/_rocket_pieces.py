# Space Rocket base: one builder per mesh piece (design only, not uploaded). Every builder returns Blender objects at
# their plot position (kit axes = plot-local, see _round_base_layout: x right, y = plot z with the door at -y, z up).
# Tint pieces are painted in value-only greys: the game colours them with MeshPart.Color (verified multiply, LESSONS),
# so one mesh serves every skin. TINT names each piece's colour role; roles(tid) maps roles to colours per skin.
#
# The look (concept models/_base_rocket_scene.py): every floor is a hull stage of a chunky cartoon rocket: a low hull
# band (kerb) with portholes, a wide glass band between thin ribs, a head band with a red joint ring that also hides
# the deck edge above. Four thin red swept fins with booster pods stand on the diagonals outside floor 1. The top
# floor wears the red ogive nose with a white band, the glass cockpit (the mascot as pilot) and an antenna; the owner's
# escape chute runs from the top floor's hatch (180 deg) down to the drop landing at polar(34, 200).
import colorsys
import math

import bmesh

from lib import PALETTE, blob, box, cylinder, mix, obj_from_bm, rgb, tube
from models._base_design_common import FLOOR_H, floor_top, polar
from models._pagoda_pieces import arc_wall, disc_on_wall, g, revolve
import models._rocket_layout as L

P = PALETTE
TINT = {}

KERB_H = 3.0                  # low hull band
HEAD_Z = 12.6                 # head band from here (above the floor) to the deck above (FLOOR_H)
RING_Z = 14.4                 # the red joint ring from here to FLOOR_H + 0.2
RIB_W = 1.0
RIB_ANGLES = tuple(k * 45.0 for k in range(8))  # the fins stand on the 45-degree ribs; pads face the panes between
LINTEL_Z = 11.0               # floor 1: hull above the door from here (the jar's door ring covers below)
NOSE_FLOOR = 4                # the nose, cockpit, trim are built on floor 4 and scaled to the top floor (L.nose_k)


def door_arc():
    half = math.degrees(math.asin(L.DOOR_W / 2 / (L.ROOM_R[0] + L.WALL_T / 2)))
    return 270.0 - half, 270.0 + half


def z_foot(f):
    """Where floor f's hull starts: floor 1 sinks a little into the plot floor, upper ones start on their deck."""
    return 0.6 if f == 1 else floor_top(f)


# ---------------------------------------------------------------- hull stages
def hull(f):
    """Hull stage f: kerb with portholes, ribs, head band (to the deck above), the hatch on floors 2-4, floor 1's
    lintel over the door. Tint: stage_f. The glass is hull_glass(f), the red ring joint_ring(f)."""
    TINT[f"rocket_hull_{f}"] = f"stage_{f}"
    z = floor_top(f)
    r_in, r_out = L.ROOM_R[f - 1], L.room_out(f)
    if f == 1:
        d0, d1 = door_arc()
        arcs = [(d1, d0 + 360.0)]
    else:
        arcs = [(0.0, 360.0)]
    out = []
    for a0, a1 in arcs:
        out.append(arc_wall(f"Kerb{f}", 0, 0, r_in, r_out, z_foot(f), z + KERB_H - z_foot(f), g(0.92), a0, a1,
                            step=7.5, lo=g(0.78)))
        out.append(arc_wall(f"KerbLip{f}", 0, 0, r_out - 0.1, r_out + 0.3, z + KERB_H - 0.5, 0.5, g(0.84), a0, a1,
                            step=7.5))
    out.append(arc_wall(f"Head{f}", 0, 0, r_in, r_out, z + HEAD_Z, FLOOR_H - HEAD_Z, g(0.96), 0.0, 360.0, step=7.5,
                        lo=g(0.86)))
    out.append(arc_wall(f"HeadLip{f}", 0, 0, r_out - 0.1, r_out + 0.3, z + HEAD_Z, 0.5, g(0.84), 0.0, 360.0, step=7.5))
    if f == 1:
        d0, d1 = door_arc()
        out.append(arc_wall("Lintel", 0, 0, r_in, r_out, z + LINTEL_Z, HEAD_Z - LINTEL_Z, g(0.96), d0, d1, step=4))
    half = math.degrees(RIB_W / 2 / r_in)
    ribs = list(RIB_ANGLES)
    if f == 1:
        ribs = [a for a in ribs if abs(a - 270) > 1] + [d0 - half - 0.3, d1 + half + 0.3]
    for k, a in enumerate(ribs):
        out.append(arc_wall(f"Rib{f}_{k}", 0, 0, r_in - 0.1, r_out + 0.25, z + KERB_H, HEAD_Z - KERB_H, g(0.9),
                            a - half, a + half, step=2 * half + 1, lo=g(0.8)))
    # portholes on the kerb between the ribs (skip the door's pane on floor 1 and the hatch on 2-4)
    for k in range(8):
        a = 22.5 + 45 * k
        if f == 1 and abs(a - 270) < 30:
            continue
        out.append(disc_on_wall(f"PortRim{f}_{k}", r_out - 0.1, a, z + KERB_H * 0.5 + 0.1, 1.05, 0.5, g(0.72),
                                segs=12))
        out.append(disc_on_wall(f"Port{f}_{k}", r_out + 0.15, a, z + KERB_H * 0.5 + 0.1, 0.7, 0.4, g(0.42), segs=12))
    if f > 1:
        out.append(disc_on_wall(f"HatchRim{f}", r_out - 0.2, L.HATCH_A, z + 3.5, 2.9, 1.1, g(0.66), segs=18))
        out.append(disc_on_wall(f"Hatch{f}", r_out + 0.2, L.HATCH_A, z + 3.5, 2.3, 0.9, g(0.9), segs=18))
        out.append(disc_on_wall(f"HatchWheel{f}", r_out + 0.7, L.HATCH_A, z + 3.5, 1.0, 0.5, g(0.5), segs=10))
    return out


def hull_glass(f):
    """Floor f's glass band between the kerb and the head band (a see-through glass slot in the game). Tint: glass."""
    TINT[f"rocket_glass_{f}"] = "glass"
    z = floor_top(f)
    r_in, r_out = L.ROOM_R[f - 1], L.room_out(f)
    if f == 1:
        d0, d1 = door_arc()
        arcs = [(d1, d0 + 360.0)]
    else:
        arcs = [(0.0, 360.0)]
    return [arc_wall(f"Glass{f}", 0, 0, r_in + 0.3, r_out - 0.3, z + KERB_H, HEAD_Z - KERB_H, g(1.0), a0, a1,
                     step=7.5, lo=g(1.0)) for a0, a1 in arcs]


def joint_ring(f):
    """The red joint ring round the top of stage f (it also covers the step to the narrower stage above). Tint:
    joint."""
    TINT[f"rocket_ring_{f}"] = "joint"
    z = floor_top(f)
    r_out = L.room_out(f)
    prof = [(r_out - 0.2, z + RING_Z), (r_out + 0.55, z + RING_Z + 0.15), (r_out + 0.75, z + RING_Z + 0.9),
            (r_out + 0.55, z + FLOOR_H + 0.1), (r_out - 0.2, z + FLOOR_H + 0.2)]
    return [revolve(f"Ring{f}", prof, g(1.0), segs=64, closed=True, lo=g(0.78))]


# ---------------------------------------------------------------- decks, post, ramp
def deck(f):
    """Floor f's deck ring (r RAMP_OUT .. deck_r), the landing at the front, the centre post of the storey and
    panel seams. Tint: deck. Floor 1 (it walks on the plot floor) has only the post."""
    TINT[f"rocket_deck_{f}" if f > 1 else "rocket_post"] = "deck"
    z = floor_top(f)
    out = [cylinder(f"Post{f}", L.POST_R, FLOOR_H, (0, 0, z), g(0.8), segs=14)]
    for k in range(4):
        out.append(cylinder(f"PostBand{f}_{k}", L.POST_R + 0.15, 0.4, (0, 0, z + 2.0 + k * 4.0), g(0.62), segs=14))
    if f == 1:
        return out
    R = L.deck_r(f)
    out.append(arc_wall(f"Deck{f}", 0, 0, L.RAMP_OUT, R - 0.05, z - L.DECK_T, L.DECK_T, g(0.9), 0.0, 360.0, step=7.5,
                        lo=g(0.7)))
    out.append(arc_wall(f"Landing{f}", 0, 0, L.RAMP_IN, L.RAMP_OUT, z - L.DECK_T, L.DECK_T, g(0.9),
                        L.ARCH_A - L.LANDING / 2, L.ARCH_A + L.LANDING / 2, step=5, lo=g(0.7)))
    # the shaft edge (a darker band) and radial panel seams
    out.append(arc_wall(f"ShaftEdge{f}", 0, 0, L.RAMP_OUT, L.RAMP_OUT + 0.7, z, 0.04, g(0.6), 0.0, 360.0, step=7.5))
    out.append(arc_wall(f"Seam{f}", 0, 0, (L.RAMP_OUT + R) / 2 - 0.15, (L.RAMP_OUT + R) / 2 + 0.15, z, 0.03, g(0.7),
                        0.0, 360.0, step=7.5))
    for k in range(16):
        a = k * 22.5
        x0, y0 = polar(L.RAMP_OUT + 0.7, a)
        x1, y1 = polar(R - 0.5, a)
        out.append(box(f"Seam{f}_{k}", (math.hypot(x1 - x0, y1 - y0), 0.25, 0.06), ((x0 + x1) / 2, (y0 + y1) / 2, z),
                       g(0.7), rot=(0, 0, a)))
    return out


def _helix_strip(name, r0, r1, a0, a1, z0, z1, t, col, segs):
    """A solid helical strip between radii r0..r1, angle a0..a1, rising z0..z1 (top surface), t thick."""
    bm = bmesh.new()
    rows = []
    for i in range(segs + 1):
        u = i / segs
        a = a0 + (a1 - a0) * u
        zz = z0 + (z1 - z0) * u
        row = []
        for r in (r0, r1):
            x, y = polar(r, a)
            row += [bm.verts.new((x, y, zz)), bm.verts.new((x, y, zz - t))]
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
    return obj_from_bm(name, bm, col)


def ramp(f=1):
    """One turn of the centre spiral ramp, floor f to f + 1 (built on floor 1; the game moves it up per floor):
    the walking strip and a hazard-striped band along the open shaft edge. Tint: ramp."""
    TINT["rocket_ramp"] = "ramp"
    z0 = floor_top(f)
    a0, sweep = L.RAMP_A0, L.RAMP_SWEEP
    edge = L.RAMP_OUT - 0.9
    out = [_helix_strip(f"Ramp{f}", L.RAMP_IN, edge, a0, a0 + sweep, z0, z0 + FLOOR_H, L.RAMP_T, g(0.95), 44)]
    n = 22
    for k in range(n):
        b0 = a0 + sweep * k / n
        b1 = a0 + sweep * (k + 1) / n
        out.append(_helix_strip(f"Haz{f}_{k}", edge, L.RAMP_OUT, b0, b1, z0 + FLOOR_H * k / n,
                                z0 + FLOOR_H * (k + 1) / n, L.RAMP_T, g(1.0) if k % 2 == 0 else g(0.36), 2))
    return out


# ---------------------------------------------------------------- the nose (floor 4's, scaled to the top floor)
def _zt(f=NOSE_FLOOR):
    return floor_top(f) + L.WALL_H


def _smooth(prof, n):
    """n + 1 points along a smooth curve (Catmull-Rom) through the (r, z) control points of the roof profile."""
    pts = [prof[0]] + list(prof) + [prof[-1]]
    out = []
    segs = len(prof) - 1
    for i in range(n + 1):
        t = i / n * segs
        k = min(int(t), segs - 1)
        u = t - k
        p0, p1, p2, p3 = pts[k], pts[k + 1], pts[k + 2], pts[k + 3]
        out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * u + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * u * u
                                + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * u ** 3) for j in range(2)))
    return out


def nose_profile(f=NOSE_FLOOR):
    return _smooth(L.roof(f, L.room_out(f)), 18)


def nose(f=NOSE_FLOOR):
    """The red ogive nose cone as a closed shell (seen from the top floor inside too), with the antenna's tip ball.
    Tint: nose."""
    TINT["rocket_nose"] = "nose"
    zt = _zt(f)
    outer = nose_profile(f)
    rim = outer[0][0]
    inner = [(max(r - 0.8, 0.3), z - 0.3) for r, z in reversed(outer)]
    top_r, top_z = outer[-1]
    prof = [(rim - 1.2, zt - 0.2), (rim + 0.25, zt - 0.2)] + outer + [(top_r - 0.6, top_z)] + inner[1:] + \
           [(rim - 1.2, zt + 0.2)]
    o = revolve("Nose", prof, g(1.0), segs=56, closed=True, lo=g(0.8))
    out = [o]
    out.append(blob("AntennaTip", 0.9, (0, 0, top_z + 7.6 + 4.6), g(1.0), subdiv=2, jitter=0.0))
    return out


def _surface_band(name, prof, z_lo, z_hi, lift, col, segs=56):
    """A band on the nose's outer surface between heights z_lo and z_hi, `lift` proud of it (a closed ring)."""
    def r_at(z):
        for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
            if z0 <= z <= z1:
                return r0 + (r1 - r0) * (z - z0) / max(z1 - z0, 1e-9)
        return prof[-1][0]
    zs = [z_lo + (z_hi - z_lo) * k / 3 for k in range(4)]
    outer = [(r_at(z) + lift, z) for z in zs]
    inner = [(r_at(z) - 0.5, z) for z in reversed(zs)]
    return revolve(name, outer + inner, col, segs=segs, closed=True, lo=col)


def nose_trim(f=NOSE_FLOOR):
    """The white parts of the nose: the band round its waist, the cockpit ring and the antenna mast with its cap.
    Tint: trim."""
    TINT["rocket_nose_trim"] = "trim"
    zt = _zt(f)
    prof = nose_profile(f)
    top_r, top_z = prof[-1]
    k = L.nose_k(f)
    out = [_surface_band("NoseBand", prof, zt + 9.6 * k, zt + 12.6 * k, 0.25, g(1.0))]
    ring = [(top_r - 0.3, top_z - 0.4), (top_r + 0.6, top_z - 0.4), (top_r + 0.8, top_z + 0.3),
            (top_r + 0.6, top_z + 0.8), (top_r - 0.3, top_z + 0.8)]
    out.append(revolve("CockpitRing", ring, g(0.95), segs=40, closed=True, lo=g(0.75)))
    hz = top_z + 7.6                      # the cockpit bubble's top (the MascotBall's)
    out.append(cylinder("AntennaCap", 1.3, 0.6, (0, 0, hz - 0.35), g(0.9), segs=14))
    out.append(cylinder("AntennaMast", 0.3, 4.4, (0, 0, hz + 0.2), g(0.62), segs=6))
    return out


def cockpit(f=NOSE_FLOOR):
    """The glass cockpit bubble on the nose's tip (the mascot sits inside). A glass slot. Tint: glass."""
    TINT["rocket_cockpit"] = "glass"
    top_r, top_z = nose_profile(f)[-1]
    rb, h = top_r + 0.3, 7.6
    prof = [(0.0, top_z + 0.05)]
    for k in range(9):
        t = k / 8 * math.pi / 2
        prof.append((max(rb * math.cos(t), 0.0), top_z + 0.05 + h * math.sin(t)))
    prof[-1] = (0.0, prof[-1][1])
    return [revolve("Cockpit", prof, g(1.0), segs=32, lo=g(1.0))]


# ---------------------------------------------------------------- floor-1 decor: fins and boosters
FIN_A = (45.0, 135.0, 225.0, 315.0)
BOOST_R = 33.6                # booster pod centre radius (pod radius 2.3: r 31.3..35.9, inside the plot's 39)
BOOST_PR = 2.3


def _slab_rows(name, a, rows, t, col):
    """A flat radial slab in the (u radial, z) plane at angle a from rows (u_in, u_out, z), t thick."""
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    bm = bmesh.new()
    vs = []
    for ui, uo, z in rows:
        row = []
        for u in (ui, uo):
            for s in (-t / 2, t / 2):
                row.append(bm.verts.new((u * ca - s * sa, u * sa + s * ca, z)))
        vs.append(row)  # in-, in+, out-, out+
    for r0, r1 in zip(vs, vs[1:]):
        bm.faces.new((r0[0], r0[2], r1[2], r1[0]))
        bm.faces.new((r0[1], r1[1], r1[3], r0[3]))
        bm.faces.new((r0[0], r1[0], r1[1], r0[1]))
        bm.faces.new((r0[2], r0[3], r1[3], r1[2]))
    b, e = vs[0], vs[-1]
    bm.faces.new((b[0], b[1], b[3], b[2]))
    bm.faces.new((e[0], e[2], e[3], e[1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, col)


def fins():
    """Four thin red swept fins on the 45-degree ribs, their roots on the hull (floor 1, stepping in to floor 2's
    hull), the booster pods' red tips. Decor, never collides. Tint: fin."""
    TINT["rocket_fins"] = "fin"
    r1, r2 = L.room_out(1) - 0.5, L.room_out(2) - 0.5
    j = floor_top(2)
    lead = lambda z: BOOST_R - (BOOST_R - (r2 + 0.5)) * (z - 11.0) / (26.0 - 11.0)
    rows = [(r1, BOOST_R, 0.5), (r1, BOOST_R, 11.0), (r1, lead(j - 0.8), j - 0.8), (r2, lead(j + 0.4), j + 0.4),
            (r2, lead(22.0), 22.0), (r2, r2 + 0.5, 26.0)]
    out = []
    for a in FIN_A:
        o = _slab_rows(f"Fin{a:.0f}", a, rows, 1.4, g(0.95))
        from lib import gradient
        gradient(o, g(0.78), g(1.0))
        out.append(o)
        x, y = polar(BOOST_R, a)
        out.append(cylinder(f"BoostTip{a:.0f}", BOOST_PR, 3.6, (x, y, 14.4), g(0.95), segs=16, r_top=0.35))
    return out


def boosters():
    """The four booster pods at the fin tips: white body, darker band, a dark nozzle sinking into the plot floor.
    Decor, never collides. Tint: trim."""
    TINT["rocket_boosters"] = "trim"
    out = []
    for a in FIN_A:
        x, y = polar(BOOST_R, a)
        out.append(cylinder(f"Nozzle{a:.0f}", 1.6, 1.9, (x, y, 0.4), g(0.34), segs=16, r_top=2.1))
        body = cylinder(f"Booster{a:.0f}", BOOST_PR, 12.1, (x, y, 2.3), g(1.0), segs=16)
        from lib import gradient
        gradient(body, g(0.8), g(1.0))
        out.append(body)
        out.append(cylinder(f"BoostBand{a:.0f}", BOOST_PR + 0.15, 1.0, (x, y, 10.2), g(0.62), segs=16))
        out.append(cylinder(f"BoostFoot{a:.0f}", BOOST_PR + 0.2, 0.5, (x, y, 2.1), g(0.7), segs=16))
    return out


# ---------------------------------------------------------------- the owner's escape chute (top floor 2..4)
def chute_path(f):
    hx, hy = polar(L.room_out(f) - 0.4, L.HATCH_A)
    zh = floor_top(f) + 3.5
    rd = 32.4
    land_a = L.EXIT_A
    pts = [(hx, hy, zh), (*polar(L.room_out(f) + 1.6, L.HATCH_A), zh), (*polar(rd - 1.0, L.HATCH_A + 0.5), zh - 0.8),
           (*polar(rd, L.HATCH_A + 1.5), zh - 2.4)]
    z_lo = 4.0
    n = max(2, int((zh - 2.4 - z_lo) / 5))
    for k in range(1, n + 1):
        t = k / n
        pts.append((*polar(rd, L.HATCH_A + 1.5 + (land_a - 2.0 - L.HATCH_A - 1.5) * t), zh - 2.4 - (zh - 2.4 - z_lo) * t))
    pts.append((*polar(rd + 0.6, land_a - 1.0), 2.4))
    pts.append((*polar(rd + 1.8, land_a), 1.6))
    return pts


def chute(f):
    """The escape chute from top floor f's hatch: a white tube out of the hull, down the rocket's side to a flared
    mouth at the landing, with darker bands. Never collides (the drop is a scripted ride to EXIT lands). Tint: trim."""
    TINT[f"rocket_chute_{f}"] = "trim"
    pts = chute_path(f)
    out = [tube(f"Chute{f}", pts, [1.8] * (len(pts) - 1) + [2.3], g(0.96), segs=16, twist_free=True)]
    out.append(tube(f"Collar{f}", [pts[0], pts[1]], [2.3, 2.3], g(0.66), segs=16))
    for k in range(3, len(pts) - 2):
        a, b = pts[k], pts[k + 1]
        m = [(a[i] + b[i]) / 2 for i in range(3)]
        d = [b[i] - a[i] for i in range(3)]
        ln = math.sqrt(sum(v * v for v in d)) or 1.0
        out.append(tube(f"Band{f}_{k}", [[m[i] - d[i] / ln * 0.35 for i in range(3)],
                                        [m[i] + d[i] / ln * 0.35 for i in range(3)]], [2.05, 2.05], g(0.62), segs=16))
    return out


# ---------------------------------------------------------------- tints per skin
def strong(col, sat=0.72, min_v=0.80):
    h, s, v = colorsys.rgb_to_hsv(*col[:3])
    return colorsys.hsv_to_rgb(h, max(s, sat), max(v, min_v)) + (1.0,)


# skin -> (stage 3 accent, the "red" (joint rings, fins, nose), the ramp); keys name the skin's palette, "P:" PALETTE
THEME_KEYS = {
    "garden": ("cork", "pot", "butter"),
    "crystal": ("goo", "metal", "lilac"),
    "starlight": ("wood", "metal", "butter"),
    "candy": ("metal", "goo", "butter"),
    "mushroom": ("leaves", "cork", "butter"),
    "fairground": ("wood_d", "wood", "metal"),
    "haunted": ("metal", "goo", "butter"),
    "beach": ("goo", "pink", "butter"),
    "space": ("wood", "goo", "butter"),
    "winter": ("goo", "metal", "butter"),
}
WHITE = rgb(240, 247, 255)    # cool white (pure white reads cream under the game's warm sun)


def roles(tid):
    """The tint colour per role in skin `tid`."""
    from models._base_design_common import theme
    TH = theme(tid)
    if tid == "classic":
        red = rgb(236, 82, 78)
        r = {"stage_1": WHITE, "stage_2": WHITE, "stage_3": rgb(70, 196, 200), "stage_4": WHITE, "joint": red,
             "fin": red, "nose": red, "trim": WHITE, "deck": rgb(200, 206, 216), "ramp": rgb(250, 206, 70)}
    else:
        acc, red_k, ramp_k = THEME_KEYS[tid]

        def key(k):
            return P[k[2:]] if k.startswith("P:") else TH[k]
        hull_c = mix(TH["cream"], WHITE, 0.4)
        red = strong(key(red_k), 0.62)
        r = {"stage_1": hull_c, "stage_2": hull_c, "stage_3": strong(key(acc), 0.5), "stage_4": hull_c, "joint": red,
             "fin": red, "nose": red, "trim": hull_c, "deck": mix(TH["cream"], TH["path"], 0.45),
             "ramp": strong(key(ramp_k), 0.6)}
    r["glass"] = TH["glass"]
    return r


# ---------------------------------------------------------------- registry
PIECES = {}
for _f in range(1, 5):
    PIECES[f"rocket_hull_{_f}"] = (lambda f: lambda: hull(f))(_f)
    PIECES[f"rocket_glass_{_f}"] = (lambda f: lambda: hull_glass(f))(_f)
    PIECES[f"rocket_ring_{_f}"] = (lambda f: lambda: joint_ring(f))(_f)
    if _f > 1:
        PIECES[f"rocket_deck_{_f}"] = (lambda f: lambda: deck(f))(_f)
        PIECES[f"rocket_chute_{_f}"] = (lambda f: lambda: chute(f))(_f)
PIECES.update({
    "rocket_post": lambda: deck(1), "rocket_ramp": lambda: ramp(1),
    "rocket_nose": lambda: nose(), "rocket_nose_trim": lambda: nose_trim(), "rocket_cockpit": lambda: cockpit(),
    "rocket_fins": fins, "rocket_boosters": boosters,
})
SHIP = dict(PIECES)
GLASS = {"rocket_glass_1", "rocket_glass_2", "rocket_glass_3", "rocket_glass_4", "rocket_cockpit"}
ROLE_OF = {  # the TINT role of every piece (the builders fill TINT as they run; this is the same, without running)
    **{f"rocket_hull_{f}": f"stage_{f}" for f in range(1, 5)}, **{f"rocket_glass_{f}": "glass" for f in range(1, 5)},
    **{f"rocket_ring_{f}": "joint" for f in range(1, 5)}, **{f"rocket_deck_{f}": "deck" for f in range(2, 5)},
    **{f"rocket_chute_{f}": "trim" for f in range(2, 5)},
    "rocket_post": "deck", "rocket_ramp": "ramp", "rocket_nose": "nose", "rocket_nose_trim": "trim",
    "rocket_cockpit": "glass", "rocket_fins": "fin", "rocket_boosters": "trim",
}
