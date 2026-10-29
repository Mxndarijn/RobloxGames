# Snow Globe base: one builder per mesh piece (design only, not uploaded). Every builder returns Blender objects at
# their plot position (kit = plot-local, see models/_round_base_layout.py). Tint pieces are painted in value-only
# greys and named in TINT; the game colours them with MeshPart.Color per skin (roles()). Fixed-colour pieces (gold
# trim, snow, the pines, the snowman) have TINT None and look the same in every skin.
#
# The look: floor 1 is the wooden pedestal (wood kerb, a glass band between gold posts, a fat wood head band with a
# gold trim); floors 2-4 are one giant glass globe on it. The colliders are upright cylinders (ROOM_R 28/25/28/25), so
# the globe is per-floor glass that bulges: floor 2 flares out going up, floor 3 is the barrel, floor 4 curves back
# in, and the dome (the roof profile, models/_snowglobe_layout.py) closes it. A floor that is the top one wears its
# "top" variant (floor 2's glass curves back in to meet the small dome; floor 3's barrel takes the big dome as is).
# Inside, snow drifts lie along the glass foot of every upper floor (they also mark the invisible collider wall),
# with tiny snow specks floating near the glass. Owner exit: a glass chute from the top floor's hatch down the globe's
# side to the landing.
import math
import random

import bmesh

from lib import blob, box, cone, cylinder, mix, obj_from_bm, rgb, shade, tube
from models._base_design_common import floor_top, polar
import models._snowglobe_layout as L

TINT = {}
GOLD, GOLD_LO = rgb(246, 186, 54), rgb(228, 148, 38)
SNOW, SNOW_LO = rgb(248, 251, 255), rgb(212, 228, 248)
PINE, PINE_LO = rgb(56, 160, 104), rgb(40, 128, 92)
BARK = rgb(150, 100, 70)
SEGS = 64                                  # round pieces: segments per full circle
GLASS_T = 0.35                             # glass thickness (closed shells: Roblox culls back faces)
DOOR_HALF = math.degrees(math.asin(L.DOOR_W / 2 / (L.ROOM_R[0] + L.WALL_T / 2)))
PED_ARC = (270 + DOOR_HALF, 270 - DOOR_HALF + 360)   # floor 1's wall without the doorway


def g(v):
    """Value-only grey (a tint piece's paint)."""
    return (v, v, v, 1.0)


def _grad(o, lo, hi):
    from lib import gradient
    gradient(o, lo, hi)
    return o


def lathe_loop(name, loop, col, lo=None, segs=SEGS, a_from=None, a_to=None):
    """Solid of revolution from a CLOSED (r, z) loop (the last point joins the first); r = 0 points are poles.
    a_from/a_to: a part-revolve, its two cut ends capped so the piece stays closed."""
    bm = bmesh.new()
    full = a_from is None
    n = segs if full else segs + 1
    rings = []
    for r, z in loop:
        if r <= 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
            continue
        ring = []
        for k in range(n):
            a = (k * math.tau / segs) if full else math.radians(a_from + (a_to - a_from) * k / segs)
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    m = segs
    for i in range(len(rings)):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        if len(a) == 1 and len(b) == 1:
            continue
        for k in range(m):
            j = (k + 1) % n if full else k + 1
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[k]))
            elif len(b) == 1:
                bm.faces.new((a[k], a[j], b[0]))
            else:
                bm.faces.new((a[k], a[j], b[j], b[k]))
    if not full:
        for end in (0, n - 1):
            vs = [rg[0] if len(rg) == 1 else rg[end] for rg in rings]
            uniq = []
            for v in vs:
                if v not in uniq:
                    uniq.append(v)
            if len(uniq) >= 3:
                bm.faces.new(uniq)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, col)
    return _grad(o, lo or shade(col, 0.85), col)


def ring(name, r_in, r_out, z0, h, col, lo=None, segs=SEGS, arc=None):
    """A flat-sided ring (a wall band) r_in..r_out, z0..z0 + h; arc = (a_from, a_to) leaves a gap."""
    loop = [(r_in, z0), (r_out, z0), (r_out, z0 + h), (r_in, z0 + h)]
    if arc:
        n = max(2, int(segs * (arc[1] - arc[0]) / 360))
        return lathe_loop(name, loop, col, lo, segs=n, a_from=arc[0], a_to=arc[1])
    return lathe_loop(name, loop, col, lo, segs=segs)


def torus(name, r, z, rad, col, segs=SEGS, minor=6):
    """A thin round ring (gold joint rings): a circle of radius rad swept round r at height z."""
    loop = [(r + rad * math.cos(t * math.tau / minor), z + rad * math.sin(t * math.tau / minor)) for t in range(minor)]
    return lathe_loop(name, loop, col, shade(col, 0.9), segs=segs)


def shell(name, prof, col, thick=GLASS_T, segs=SEGS):
    """A closed glass shell from an outer (r, z) profile going up: the outer face, then the inner one thick inside."""
    inner = [(max(0.0, r - thick), z) if r > 0 else (0.0, z - thick) for r, z in reversed(prof)]
    return lathe_loop(name, list(prof) + inner, col, col, segs=segs)


# ---------------------------------------------------------------- the globe's glass profiles
def glass2_top_r(z):
    """Floor 2's top variant: a short bulge from the pedestal (26.5) out to ~27.6 and back in to the small dome's rim,
    meeting it at the same slope: r = a - c (z - m)^2."""
    r0, s0 = L.dome_start(L.room_out(2))
    zt = floor_top(2) + L.WALL_H
    D = zt - L.PED_TOP
    c = (r0 - s0 * D - 26.5) / D ** 2
    p = -s0 / (2 * c)
    return r0 + c * p * p - c * (z - (zt - p)) ** 2


def profile(fn, z0, z1, n):
    return [(round(fn(z0 + (z1 - z0) * k / n), 4), z0 + (z1 - z0) * k / n) for k in range(n + 1)]


def glass_profile(f, top):
    """(r, z) outer profile of floor f's globe glass (floors 2-4)."""
    if f == 2 and top:
        return profile(glass2_top_r, L.PED_TOP, floor_top(2) + L.WALL_H, 10)
    if f == 2:
        return profile(L.globe_r, L.PED_TOP, floor_top(3), 10)
    if f == 3:
        return profile(L.globe_r, floor_top(3), floor_top(4) - 0.4, 10)
    return profile(L.globe_r, floor_top(4) - 0.2, floor_top(4) + L.WALL_H, 10)


def glass_at(f, z, top):
    """The glass radius of floor f (its top variant or not) at height z."""
    if f == 2 and top:
        return glass2_top_r(z)
    return L.globe_r(z)


def globe_glass(f, top=False):
    """Floor f's slice of the globe (a see-through glass slot in the game). Tint: glass."""
    name = f"snowglobe_glass_{f}" + ("t" if (top and f == 2) else "")
    TINT[name] = "glass"
    return [shell(f"Glass{f}", glass_profile(f, top), g(1.0))]


def dome(rim_floor):
    """The glass dome on the top floor: the roof profile from the rim up to the crown (r CROWN_R), closed flat under
    the gold crown. Built on floor 4 (small, rim 26) or floor 3 (big, rim 29); the game shifts it onto the top floor.
    Tint: glass."""
    rim = L.room_out(rim_floor)
    name = "snowglobe_dome_s" if rim < 27.5 else "snowglobe_dome_l"
    TINT[name] = "glass"
    zt = floor_top(rim_floor) + L.WALL_H
    prof = [(round(L.dome_r(rim, L.DOME_H * k / 12), 4), zt + L.DOME_H * k / 12) for k in range(13)]
    prof.append((0.0, zt + L.DOME_H))
    return [shell("Dome", prof, g(1.0))]


def crown():
    """The gold crown the mascot sits on (the RoofCrown collider's look), built on floor 4's dome. Fixed colours."""
    TINT["snowglobe_crown"] = None
    zc = floor_top(4) + L.WALL_H + L.DOME_H
    out = [lathe_loop("Crown", [(0.0, zc - 1.0), (L.CROWN_R + 0.5, zc - 1.0), (L.CROWN_R + 0.9, zc - 0.4),
                                (L.CROWN_R + 0.6, zc + 0.15), (0.0, zc + 0.15)], GOLD, GOLD_LO, segs=40)]
    out.append(torus("CrownBead", L.CROWN_R + 0.85, zc - 0.55, 0.3, shade(GOLD, 1.05), segs=40))
    for k in range(8):
        x, y = polar(L.CROWN_R + 0.75, k * 45 + 22.5)
        out.append(blob(f"CrownGem{k}", 0.45, (x, y, zc - 0.3), rgb(150, 210, 255), subdiv=1, jitter=0))
    return out


# ---------------------------------------------------------------- floor 1: the pedestal
KERB_TOP = 4.0
GLASS1 = (4.2, 13.0)          # floor 1's glass band (z)
HEAD0 = 13.0                  # the fat head band from here up to PED_TOP
PED_OUT = 31.0


def pedestal():
    """Floor 1's wood: kerb (gap at the door), the fat head band the globe stands on, a foot ring. Tint: wood."""
    TINT["snowglobe_ped"] = "wood"
    ri = L.ROOM_R[0] - 0.1
    z = floor_top(1)
    out = [ring("Kerb", ri, L.room_out(1) + 0.4, z, KERB_TOP - z, g(0.86), g(0.74), arc=PED_ARC),
           ring("Foot", L.room_out(1) + 0.3, L.room_out(1) + 1.3, z - 0.1, 0.9, g(0.7), g(0.62), arc=PED_ARC),
           lathe_loop("Head", [(ri, HEAD0), (PED_OUT - 0.6, HEAD0), (PED_OUT, HEAD0 + 0.6), (PED_OUT, L.PED_TOP - 1.6),
                               (PED_OUT - 0.7, L.PED_TOP - 0.45), (PED_OUT - 2.2, L.PED_TOP), (25.9, L.PED_TOP), (25.9, floor_top(2) - 0.8),
                               (ri, floor_top(2) - 0.8)], g(0.95), g(0.8)),
           ring("HeadLip", ri + 0.4, PED_OUT + 0.35, HEAD0 - 0.5, 0.5, g(0.78), g(0.72))]
    # carved panels round the head band: shallow darker insets between the gold studs
    for k in range(24):
        a = k * 15 + 7.5
        x, y = polar(PED_OUT + 0.05, a)
        out.append(box(f"Panel{k}", (0.2, 5.6, 1.1), (x, y, HEAD0 + 1.05), g(0.7), rot=(0, 0, a)))
    return out


def pedestal_gold():
    """Gold on the pedestal: posts between the glass panes, the head band's trim, the kerb cap and the globe's seat
    ring. Fixed colours."""
    TINT["snowglobe_ped_gold"] = None
    z = floor_top(1)
    out = [ring("KerbCap", L.ROOM_R[0] - 0.2, L.room_out(1) + 0.55, KERB_TOP - 0.05, 0.3, GOLD, arc=PED_ARC),
           ring("Trim", PED_OUT - 0.1, PED_OUT + 0.35, HEAD0 + 2.0, 0.6, GOLD, GOLD_LO),
           torus("Seat", 26.75, L.PED_TOP + 0.15, 0.4, GOLD),
           torus("HeadEdge", PED_OUT - 0.2, L.PED_TOP - 1.55, 0.32, GOLD)]
    for k in range(12):
        a = 15 + k * 30
        x, y = polar(L.ROOM_R[0] + 0.55, a)
        out.append(box(f"Post{k}", (1.6, 0.9, HEAD0 - KERB_TOP + 0.2), (x, y, (KERB_TOP + HEAD0) / 2), GOLD,
                       rot=(0, 0, a)))
    for k in range(24):
        x, y = polar(PED_OUT + 0.3, k * 15)
        out.append(blob(f"Stud{k}", 0.32, (x, y, HEAD0 + 1.05), GOLD, subdiv=1, jitter=0))
    return out


def pedestal_glass():
    """Floor 1's glass band between the kerb and the head band (gap at the door). Tint: glass."""
    TINT["snowglobe_glass_1"] = "glass"
    return [ring("Glass1", L.ROOM_R[0] + 0.3, L.room_out(1) - 0.2, GLASS1[0], GLASS1[1] - GLASS1[0], g(1.0), g(1.0),
                 arc=PED_ARC)]


# ---------------------------------------------------------------- decks, ramp, post
DECK_NATIVE = 2


def deck():
    """An upper floor's plank deck ring (r 8 to the deck reach), built on floor 2; the game shifts it to floors 3-4.
    Tint: deck."""
    TINT["snowglobe_deck"] = "deck"
    z = floor_top(DECK_NATIVE)
    R = L.deck_r(DECK_NATIVE)
    out = [ring("Deck", L.RAMP_OUT, R, z - L.DECK_T, L.DECK_T, g(0.9), g(0.75))]
    for k in range(32):
        a = k * 360 / 32
        rm = (L.RAMP_OUT + 0.3 + R - 0.4) / 2
        x, y = polar(rm, a)
        out.append(box(f"Seam{k}", (R - L.RAMP_OUT - 0.7, 0.22, 0.06), (x, y, z + 0.02), g(0.68), rot=(0, 0, a)))
    out.append(ring("DeckRing", 16.0, 16.4, z, 0.05, g(0.72), g(0.72)))
    return out


def post(f=1):
    """The centre post of one storey. Tint: ramp."""
    TINT["snowglobe_post"] = "ramp"
    z = floor_top(f)
    return [cylinder("Post", L.POST_R, 16.0, (0, 0, z), g(0.92), segs=16),
            cylinder("PostFoot", L.POST_R + 0.4, 0.6, (0, 0, z), g(0.75), segs=16)]


def core(f=DECK_NATIVE):
    """Floor f's middle: its post, the ramp turn that climbs to it from the floor below (outer lip as a rail) and its
    landing. Built on floor 2; the game shifts it to floors 3-4. Tint: ramp."""
    had_post = "snowglobe_post" in TINT
    out = post(f)
    if not had_post:
        TINT.pop("snowglobe_post", None)
    TINT["snowglobe_core"] = "ramp"
    z0 = floor_top(f - 1)
    n = 44
    bm = bmesh.new()
    rows = []
    for k in range(n + 1):
        t = k / n
        a = math.radians(L.RAMP_A0 + L.RAMP_SWEEP * t)
        zt = z0 + L.FLOOR_H * t
        row = []
        for r, dz in ((L.RAMP_IN, 0.0), (L.RAMP_OUT, 0.0), (L.RAMP_OUT, -L.RAMP_T), (L.RAMP_IN, -L.RAMP_T)):
            row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), zt + dz)))
        rows.append(row)
    for a, b in zip(rows, rows[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    out.append(_grad(obj_from_bm("Ramp", bm, g(0.9)), g(0.76), g(0.94)))
    # the rail along the open edge: a low lip, gold-free so the tint carries it
    pts = []
    for k in range(n + 1):
        t = k / n
        a = L.RAMP_A0 + L.RAMP_SWEEP * t
        x, y = polar(L.RAMP_OUT - 0.25, a)
        pts.append((x, y, z0 + L.FLOOR_H * t + 0.45))
    out.append(tube("Lip", pts, [0.3] * len(pts), g(0.7), segs=6, twist_free=True))
    lx = L.LANDINGS[f - 2]
    a0, a1 = L.ARCH_A - L.LANDING / 2 - 1, L.ARCH_A + L.LANDING / 2 + 1
    out.append(lathe_loop("Landing", [(L.RAMP_IN, floor_top(f) - L.DECK_T), (L.RAMP_OUT, floor_top(f) - L.DECK_T),
                                      (L.RAMP_OUT, floor_top(f)), (L.RAMP_IN, floor_top(f))], g(0.88), g(0.8),
                          segs=8, a_from=a0, a_to=a1))
    del lx
    return out


# ---------------------------------------------------------------- snow inside the globe
def snow(f):
    """Floor f's (2-4) snow: a drift along the glass foot from just inside the collider wall to the glass (it hides the
    deck ledge outside a narrow room and marks the invisible wall), tiny specks floating near the glass, and the
    thin gold ring at the joint with the floor below (floors 3-4). Fixed colours."""
    TINT[f"snowglobe_snow_{f}"] = None
    z = floor_top(f)
    r_in = L.ROOM_R[f - 1] - 0.5
    r_out = glass_at(f, z + 0.3, True) - 0.25
    h = 0.6 + 0.14 * (r_out - r_in)
    out = [lathe_loop(f"Drift{f}", [(r_in, z - 0.05), (r_out, z - 0.05), (r_out, z + h), (r_out - 0.6, z + h * 0.92),
                                    (r_in + (r_out - r_in) * 0.45, z + h * 0.55), (r_in + 0.4, z + 0.3)],
                      SNOW, SNOW_LO, segs=SEGS)]
    rr = random.Random(10 + f)
    for k in range(34):
        a = rr.uniform(0, 360)
        zz = z + rr.uniform(2.5, L.WALL_H - 1.0)
        gr = min(glass_at(f, zz, True), glass_at(f, zz, False))
        r = rr.uniform(gr - 2.6, gr - 0.6)
        x, y = polar(r, a)
        out.append(blob(f"Speck{f}_{k}", rr.uniform(0.2, 0.36), (x, y, zz), SNOW, subdiv=1, jitter=0, seed=k))
    if f > 2:
        out.append(torus(f"Joint{f}", L.globe_r(z - 0.3) + 0.12, z - 0.3, 0.38, GOLD))
    return out


def pine_tree(name, x, y, z, s=1.0):
    out = [cylinder(name + "Trunk", 0.45 * s, 1.6 * s, (x, y, z), BARK, segs=6)]
    for k, (r, h, zz) in enumerate(((2.4, 3.4, 1.2), (1.9, 3.0, 3.2), (1.35, 2.7, 5.0))):
        out.append(_grad(cone(f"{name}Tier{k}", r * s, h * s, (x, y, z + zz * s), PINE, segs=9), PINE_LO, PINE))
        out.append(_grad(cylinder(f"{name}Snow{k}", r * s * 0.62, h * s * 0.42, (x, y, z + (zz + h * 0.58) * s), SNOW,
                                  segs=9, r_top=0.05), SNOW_LO, SNOW))
    out.append(blob(name + "Star", 0.45 * s, (x, y, z + 7.9 * s), GOLD, subdiv=1, jitter=0))
    return out


PINE_SPOTS = ((21.0, 45.0, 1.0), (21.0, 135.0, 0.85))


def pines():
    """Two little snowy pines on the top floor's deck, outside the pad ring between pads (built on floor 4; never
    collide). Fixed colours."""
    TINT["snowglobe_pine"] = None
    z = floor_top(4)
    out = []
    for k, (r, a, s) in enumerate(PINE_SPOTS):
        x, y = polar(r, a)
        out += pine_tree(f"Pine{k}", x, y, z, s)
        out.append(blob(f"PineSnow{k}", 2.2 * s, (x, y, z), SNOW, subdiv=2, squash=(1, 1, 0.22), jitter=0))
    return out


# ---------------------------------------------------------------- the owner's drop exit
CHUTE_R = 1.7


def chute_path(f):
    """The chute's line from floor f's hatch (the top floor) out through the globe and down its -x side, round the
    pedestal's head band, to just above the landing at polar(34, 200)."""
    hx, hy, hz = L.hatch_pos(f)
    zh = floor_top(f) + 3.6
    land = L.EXIT["lands"]
    a_land = math.degrees(math.atan2(land[1], land[0])) % 360
    r_land = math.hypot(*land)

    def clear_r(z):
        if z > L.PED_TOP + 1.5:
            fl = min(f, max(2, int((z - 1) // 16) + 1))
            gl = glass_at(fl, z, fl == f)
            return gl + CHUTE_R + 0.6
        return PED_OUT + 0.4 + CHUTE_R + 0.3

    pts = [(*polar(L.ROOM_R[f - 1] - 0.6, 180.0), zh), (*polar(L.ROOM_R[f - 1] + 1.6, 180.0), zh - 0.1)]
    out_r = glass_at(f, zh, True) + CHUTE_R + 0.8
    pts.append((*polar(out_r, 181.0), zh - 0.9))
    z_end = 3.4
    n = 14
    for k in range(1, n + 1):
        t = k / n
        zz = (zh - 2.6) * (1 - t) ** 1.15 + z_end * (1 - (1 - t) ** 1.15)
        a = 181.0 + (a_land - 181.0) * t ** 1.3
        r = max(clear_r(zz), clear_r(zz + 2.5), clear_r(zz - 2.5))
        if k == n:
            r = r_land
        pts.append((*polar(r, a), zz))
    # smooth the radii once (keep the ends)
    sm = [pts[0], pts[1], pts[2]]
    for i in range(3, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        rb = max(math.hypot(b[0], b[1]), (math.hypot(a[0], a[1]) + math.hypot(c[0], c[1])) / 2)
        ab = math.degrees(math.atan2(b[1], b[0]))
        sm.append((*polar(rb, ab), b[2]))
    sm.append(pts[-1])
    return sm


def chute_glass(f):
    """The see-through chute of floor f's drop exit (a glass slot in the game). Tint: glass. Never collides."""
    TINT[f"snowglobe_chute_glass_{f}"] = "glass"
    pts = chute_path(f)
    return [tube("Chute", pts, [CHUTE_R] * len(pts), g(1.0), segs=16, twist_free=True)]


def chute(f):
    """The solid half of floor f's drop exit: the gold hatch frame, gold collars along the chute, the flared mouth and
    a snow pile at the landing. Fixed colours. Never collides (the drop is a scripted move to EXIT["lands"])."""
    TINT[f"snowglobe_chute_{f}"] = None
    pts = chute_path(f)
    z = floor_top(f)
    R = L.ROOM_R[f - 1]
    out = []
    # the hatch frame round the DropHatch (4 wide, 7 tall on the wall's inside face)
    for s in (-1, 1):
        x, y = polar(R - 0.5, 180.0 + s * math.degrees(2.4 / R))
        out.append(box(f"Jamb{s}", (0.8, 0.8, 7.4), (x, y, z + 3.7), GOLD))
    x, y = polar(R - 0.5, 180.0)
    out.append(box("Lintel", (0.8, 5.6, 0.8), (x, y, z + 7.4), GOLD))
    out.append(tube("Collar", [pts[0], pts[1]], [CHUTE_R + 0.35] * 2, GOLD, segs=16))
    for k in range(4, len(pts) - 2, 3):
        a, b = pts[k], pts[k + 1]
        d = [b[i] - a[i] for i in range(3)]
        ln = math.sqrt(sum(v * v for v in d)) or 1.0
        out.append(tube(f"Band{k}", [[a[i] - d[i] / ln * 0.3 for i in range(3)], [a[i] + d[i] / ln * 0.3 for i in range(3)]],
                        [CHUTE_R + 0.22] * 2, GOLD, segs=16))
    end, before = pts[-1], pts[-2]
    d = [end[i] - before[i] for i in range(3)]
    ln = math.sqrt(sum(v * v for v in d)) or 1.0
    tip = [end[i] + d[i] / ln * 0.6 for i in range(3)]
    out.append(tube("Mouth", [end, tip], [CHUTE_R + 0.2, CHUTE_R + 0.75], GOLD, segs=16))
    lx, ly = L.EXIT["lands"]
    out.append(blob("SnowPile", 2.6, (lx, ly, 1.0), SNOW, subdiv=2, squash=(1, 1, 0.32), jitter=0.05))
    out.append(blob("SnowPile2", 1.4, (lx + 1.6, ly - 1.0, 1.2), SNOW, subdiv=2, squash=(1, 1, 0.45), jitter=0.05))
    return out


# ---------------------------------------------------------------- outside decor
def decor():
    """A snowman and gift boxes on the plot ring between the pedestal and the moat (not in front of the door, clear of
    the drop landing). Fixed colours. Never collide."""
    TINT["snowglobe_decor"] = None
    out = []
    z = 1.0
    sx, sy = polar(32.9, 35.0)
    face = 35.0                                     # the snowman looks outwards
    for k, (r, zz) in enumerate(((1.7, 1.4), (1.25, 3.85), (0.9, 5.6))):
        out.append(_grad(blob(f"Snowball{k}", r, (sx, sy, z + zz), SNOW, subdiv=2, jitter=0.02, seed=k), SNOW_LO, SNOW))
    fx, fy = polar(0.85, face)
    out.append(cylinder("Nose", 0.22, 1.0, (sx + fx, sy + fy, z + 5.6), rgb(250, 140, 50), segs=6, r_top=0.0,
                        rot=(0, 90, face)))
    for s in (-1, 1):
        ex, ey = polar(0.78, face + s * 28)
        out.append(blob(f"Eye{s}", 0.13, (sx + ex, sy + ey, z + 5.85), rgb(60, 56, 64), subdiv=1, jitter=0))
    out.append(cylinder("HatBrim", 0.95, 0.15, (sx, sy, z + 6.3), rgb(70, 64, 80), segs=12))
    out.append(cylinder("Hat", 0.62, 1.0, (sx, sy, z + 6.4), rgb(78, 72, 90), segs=12))
    out.append(cylinder("HatBand", 0.64, 0.22, (sx, sy, z + 6.5), rgb(220, 60, 60), segs=12))
    out.append(cylinder("Scarf", 1.0, 0.45, (sx, sy, z + 4.75), rgb(220, 60, 60), segs=12, r_top=0.92))
    tx, ty = polar(0.9, face + 40)
    out.append(box("ScarfTail", (0.5, 0.25, 1.4), (sx + tx, sy + ty, z + 4.1), rgb(220, 60, 60), rot=(0, 0, face)))
    for s in (-1, 1):
        ax, ay = polar(1.1, face + s * 90)
        bx, by = polar(2.4, face + s * 90)
        out.append(tube(f"Arm{s}", [(sx + ax, sy + ay, z + 4.0), (sx + bx, sy + by, z + 4.9)], [0.12, 0.08], BARK, segs=5))
    gifts = ((140.0, 32.8, 2.2, rgb(230, 70, 80), GOLD, 10), (147.0, 33.2, 1.6, rgb(70, 170, 110), SNOW, -15),
             (134.5, 33.4, 1.4, rgb(90, 150, 240), GOLD, 25), (322.0, 32.9, 1.9, rgb(120, 190, 250), rgb(230, 70, 80), 5),
             (328.0, 33.3, 1.3, rgb(250, 200, 80), rgb(230, 70, 80), -20))
    for k, (a, r, s, col, rib, yaw) in enumerate(gifts):
        x, y = polar(r, a)
        out.append(_grad(box(f"Gift{k}", (s, s, s * 0.9), (x, y, z + s * 0.45), col, rot=(0, 0, a + yaw)),
                         shade(col, 0.85), col))
        for j in (0, 90):
            out.append(box(f"Rib{k}_{j}", (s + 0.06, s * 0.2, s * 0.9 + 0.06), (x, y, z + s * 0.45), rib,
                           rot=(0, 0, a + yaw + j)))
        for j in (-1, 1):
            bx, by = polar(s * 0.2, a + yaw + 90 * j)
            out.append(blob(f"Bow{k}{j}", s * 0.2, (x + bx, y + by, z + s * 0.9 + s * 0.1), rib, subdiv=1,
                            squash=(1.2, 0.7, 0.7), jitter=0, rot=(0, 0, a + yaw)))
    return out


# ---------------------------------------------------------------- roles and tints
def roles(tid):
    """The tint colour per role in skin `tid` (the jar tower's theme palettes)."""
    from models._base_design_common import theme
    TH = theme(tid)
    return {
        "wood": TH["wood"],
        "deck": mix(TH["wood"], TH["cream"], 0.35),
        "ramp": mix(TH["cream"], TH["wood"], 0.15),
        "glass": TH["glass"],
    }


# PIECES: name -> builder (measuring through _snowglobe_piece.py; shipping through _snowglobe_ship.py)
PIECES = {
    "snowglobe_ped": pedestal, "snowglobe_ped_gold": pedestal_gold, "snowglobe_glass_1": pedestal_glass,
    "snowglobe_glass_2": lambda: globe_glass(2), "snowglobe_glass_2t": lambda: globe_glass(2, True),
    "snowglobe_glass_3": lambda: globe_glass(3), "snowglobe_glass_4": lambda: globe_glass(4, True),
    "snowglobe_dome_s": lambda: dome(4), "snowglobe_dome_l": lambda: dome(3), "snowglobe_crown": crown,
    "snowglobe_deck": deck, "snowglobe_post": lambda: post(1), "snowglobe_core": lambda: core(DECK_NATIVE),
    "snowglobe_snow_2": lambda: snow(2), "snowglobe_snow_3": lambda: snow(3), "snowglobe_snow_4": lambda: snow(4),
    "snowglobe_pine": pines,
    "snowglobe_chute_2": lambda: chute(2), "snowglobe_chute_3": lambda: chute(3), "snowglobe_chute_4": lambda: chute(4),
    "snowglobe_chute_glass_2": lambda: chute_glass(2), "snowglobe_chute_glass_3": lambda: chute_glass(3),
    "snowglobe_chute_glass_4": lambda: chute_glass(4),
    "snowglobe_decor": decor,
}
SHIP = dict(PIECES)
# the tint role of each piece (the builders also record it in TINT); None = fixed colours
ROLE_OF = {"snowglobe_ped": "wood", "snowglobe_deck": "deck", "snowglobe_post": "ramp", "snowglobe_core": "ramp"}
ROLE_OF.update({n: "glass" for n in PIECES if "glass" in n or "dome" in n})
GLASS = {n for n in PIECES if "glass" in n or "dome" in n}


# ---------------------------------------------------------------- the slot plan (models/_snowglobe_meshes.py writes it)
FLOORS = 4
MASCOT_SCALE = 3.8


def _slot_plan():
    """Every mesh slot at 4 floors: floor, name, mesh, offset (x, up, z) after scaling, scale, show, role, glass."""
    out = []

    def slot(floor, name, mesh, up=0.0, scale=1.0, show=None):
        role = ROLE_OF.get(mesh)
        out.append({"floor": floor, "name": name, "mesh": mesh, "offset": [0.0, round(up, 4), 0.0], "scale": scale,
                    "show": show, "role": role, "glass": mesh in GLASS})

    for f in range(1, FLOORS + 1):
        top = None if f == FLOORS else "top"
        covered = None if f == FLOORS else "covered"
        if f == 1:
            slot(1, "Room", "snowglobe_ped")
            slot(1, "RoomGold", "snowglobe_ped_gold")
            slot(1, "Glass", "snowglobe_glass_1")
            slot(1, "Core", "snowglobe_post")
            slot(1, "Decor", "snowglobe_decor")
        else:
            slot(f, "Deck", "snowglobe_deck", floor_top(f) - floor_top(DECK_NATIVE))
            slot(f, "Core", "snowglobe_core", floor_top(f) - floor_top(DECK_NATIVE))
            slot(f, "Snow", f"snowglobe_snow_{f}")
            if f == 2:
                slot(f, "Glass", "snowglobe_glass_2", show=covered)
                slot(f, "GlassTop", "snowglobe_glass_2t", show=top)
            else:
                slot(f, "Glass", f"snowglobe_glass_{f}")
            slot(f, "Pine", "snowglobe_pine", floor_top(f) - floor_top(4), show=top)
            slot(f, "Chute", f"snowglobe_chute_{f}", show=top)
            slot(f, "ChuteGlass", f"snowglobe_chute_glass_{f}", show=top)
        if L.room_out(f) < 27.5:
            slot(f, "Dome", "snowglobe_dome_s", floor_top(f) - floor_top(4), show=top)
        else:
            slot(f, "Dome", "snowglobe_dome_l", floor_top(f) - floor_top(3), show=top)
        slot(f, "Crown", "snowglobe_crown", floor_top(f) - floor_top(4), show=top)
        slot(f, "MascotLook", "goo_jar_mascot", floor_top(f) + L.WALL_H + L.DOME_H + 0.1, MASCOT_SCALE, show=top)
    return out


def slots_for(n, plan=None):
    """The slots standing (and shown) with n floors: a "top" slot only on floor n, a "covered" one only below it."""
    plan = plan or _slot_plan()
    return [s for s in plan if s["floor"] <= n and (s["show"] is None or (s["show"] == "top") == (s["floor"] == n))]
