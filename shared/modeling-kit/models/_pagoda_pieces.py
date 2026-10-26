# Mushroom Pagoda base: one builder per mesh piece (design only, not uploaded). Every builder returns Blender objects
# at their plot position (kit = plot-local, see _pagoda_layout). Tint pieces are painted in value-only greys: the game
# gives them their colour with MeshPart.Color (assumed multiply, as in LESSONS), so one mesh serves every theme.
# TINT names the colour role of each piece; _base_pagoda_design.py maps roles to theme colours.
import math
import random

import bmesh

from lib import blob, box, cylinder, obj_from_bm, rgb, shade, tube
from models._base_design_common import floor_top, polar
import models._pagoda_layout as L


def g(v):
    """Value-only grey (a tint piece's paint)."""
    return (v, v, v, 1.0)


def _paint_grad(o, lo, hi):
    from lib import gradient
    gradient(o, lo, hi)
    return o


def revolve(name, prof, col, segs=40, cx=0.0, cy=0.0, lo=None, a_from=None, a_to=None, closed=False):
    """Surface of revolution from a (r, z) profile; r = 0 ends close it. a_from/a_to: a part-revolve (open sides)."""
    bm = bmesh.new()
    full = a_from is None
    n = segs if full else segs + 1
    rings = []
    for r, z in prof:
        ring = []
        for k in range(n):
            a = (k * math.tau / segs) if full else math.radians(a_from + (a_to - a_from) * k / segs)
            if r <= 1e-6:
                ring = [bm.verts.new((cx, cy, z))]
                break
            ring.append(bm.verts.new((cx + r * math.cos(a), cy + r * math.sin(a), z)))
        rings.append(ring)
    m = segs if full else segs
    pairs = list(zip(rings, rings[1:])) + ([(rings[-1], rings[0])] if closed else [])
    for a, b in pairs:
        for k in range(m):
            j = (k + 1) % n if full else k + 1
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[k]))
            elif len(b) == 1:
                bm.faces.new((a[k], a[j], b[0]))
            else:
                bm.faces.new((a[k], a[j], b[j], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, col)
    return _paint_grad(o, lo or shade(col, 0.8), col)


def arc_wall(name, cx, cy, r_in, r_out, z0, h, col, a_from, a_to, step=6.0, lo=None):
    n = max(2, int(math.ceil((a_to - a_from) / step)))
    bm = bmesh.new()
    for i in range(n):
        a1 = a_from + (a_to - a_from) * i / n
        a2 = a_from + (a_to - a_from) * (i + 1) / n
        p = [polar(r, a) for r in (r_in, r_out) for a in (a1, a2)]
        (ix1, iy1), (ix2, iy2), (ox1, oy1), (ox2, oy2) = [(cx + x, cy + y) for x, y in p]
        vs = [bm.verts.new(q) for q in (
            (ix1, iy1, z0), (ix2, iy2, z0), (ox2, oy2, z0), (ox1, oy1, z0),
            (ix1, iy1, z0 + h), (ix2, iy2, z0 + h), (ox2, oy2, z0 + h), (ox1, oy1, z0 + h))]
        for fc in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
            bm.faces.new([vs[j] for j in fc])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, col)
    return _paint_grad(o, lo or shade(col, 0.86), col)


def disc_on_wall(name, r_wall, a, z, rad, depth, col, cx=0.0, cy=0.0, segs=14):
    """A round disc standing on a wall face at angle a (window recess, hatch, frame)."""
    x, y = polar(r_wall, a)
    return cylinder(name, rad, depth, (cx + x, cy + y, z), col, segs=segs, rot=(0, 90, a))


# ---------------------------------------------------------------- rooms
WINDOW_ANGLES = {1: (-45, 0, 25, 155, 180, 215), 2: (-60, -15, 25, 155, 230), 3: (-45, 0, 155, 230), 4: (-30, 20, 160, 235)}
TINT = {}


def room(f):
    """Stalk wall of floor f with its door (floor 1) / hatch (2-4), round windows, ring band. Tint: stalk."""
    TINT[f"pagoda_room_{f}"] = "stalk"
    z = floor_top(f)
    r_in, r_out = L.ROOM_R[f - 1], L.room_out(f)
    out = []
    for a0, a1 in L.room_arcs(f):
        out.append(arc_wall(f"Wall{f}_{a0:.0f}", 0, 0, r_in, r_out, z, L.WALL_H, g(0.94), a0, a1, lo=g(0.80)))
        out.append(arc_wall(f"Band{f}_{a0:.0f}", 0, 0, r_out - 0.1, r_out + 0.5, z, 1.6, g(0.58), a0, a1))
    for k, a in enumerate(WINDOW_ANGLES[f]):
        out.append(disc_on_wall(f"WinRim{f}{k}", r_out - 0.2, a, z + 6.6, 2.4, 0.8, g(0.78)))
        out.append(disc_on_wall(f"Win{f}{k}", r_out + 0.05, a, z + 6.6, 1.85, 0.7, g(0.36)))
    if f > 1:
        out.append(disc_on_wall(f"Hatch{f}", r_out - 0.2, L.HATCH_A, z + 3.0, 2.2, 1.2, g(0.55)))
        out.append(disc_on_wall(f"HatchRim{f}", r_out - 0.3, L.HATCH_A, z + 3.0, 2.7, 1.1, g(0.74)))
    return out


def deck(f):
    """Plank floor of an upper room with the turret notch. Tint: wood."""
    TINT[f"pagoda_deck_{f}"] = "wood"
    z = floor_top(f)
    R = L.ROOM_R[f - 1] + 0.5
    out = []
    # outline: the room rim from the turret's right side round the front to its left side, then back along the
    # turret's outer circle (its room-facing half), so the deck meets the turret wall exactly
    bm = bmesh.new()
    tc = L.TURRET_C
    phi = L._turret_gap(f)
    pts = []
    n_rim = 44
    for k in range(n_rim + 1):
        a = 90 + phi + (360 - 2 * phi) * k / n_rim
        pts.append(polar(R, a))
    lx, ly = pts[-1]
    rx, ry = pts[0]
    b_left = math.degrees(math.atan2(ly - tc[1], lx - tc[0])) % 360
    b_right = math.degrees(math.atan2(ry - tc[1], rx - tc[0])) % 360
    n_t = 14
    for k in range(1, n_t):
        bb = b_left + ((b_right - b_left) % 360) * k / n_t
        x, y = polar(L.TURRET_OUT, bb)
        pts.append((tc[0] + x, tc[1] + y))
    segs = len(pts)
    top = [bm.verts.new((x, y, z)) for x, y in pts]
    bot = [bm.verts.new((x, y, z - 0.6)) for x, y in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    for k in range(segs):
        j = (k + 1) % segs
        bm.faces.new((bot[k], bot[j], top[j], top[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    out.append(obj_from_bm(f"Deck{f}", bm, g(0.86)))
    for k in range(-4, 5):
        out.append(box(f"Board{f}{k}", (0.25, 2 * R - 3, 0.06), (k * 4.2, -1.5, z + 0.02), g(0.70)))
    return out


# ---------------------------------------------------------------- caps
# Cap ornaments (spots, snow, sprinkles, moss, flower pots, icicles) are built ONCE on eave cap CAP_NATIVE and the game
# scales that one mesh to every other cap (place_on_cap): the caps are nearly similar cones (inner/outer radius ratio
# 0.78-0.79, the same 3.4-stud rise), so a uniform scale fits within ~0.2 studs. The same ring fits the dome's rim.
CAP_NATIVE = 2
DOME_NATIVE_FLOOR = 4


def eave_top(f):
    """The eave cap's visible top, (r, z) from the next room's wall out to the rim: a slightly domed cone."""
    ri, zi = L.room_out(f + 1), floor_top(f + 1) - 0.6
    re, ze = L.eave_r(f), floor_top(f) + L.CAP_UNDER + 0.8
    rm = ri + 0.5 * (re - ri)
    return [(ri, zi), (rm, (zi + ze) / 2 + 0.45), (re - 0.8, ze + 0.15)]


def surf_z(pts, r):
    """Height of a (r, z) polyline at radius r (pts ordered by r, either way)."""
    q = sorted(pts)
    for (r0, z0), (r1, z1) in zip(q, q[1:]):
        if r0 <= r <= r1:
            return z0 + (z1 - z0) * (r - r0) / max(r1 - r0, 1e-9)
    return q[0][1] if r < q[0][0] else q[-1][1]


def paint_under(o, top_v, under_v):
    """Light top, dark underside: faces looking down get under_v (the gills' shadow), the rest a soft top_v gradient."""
    ca = o.data.color_attributes["Col"]
    zs = [v.co.z for v in o.data.vertices]
    z0, z1 = min(zs), max(zs)
    for poly in o.data.polygons:
        if poly.normal.z < -0.25:
            c = under_v
        else:
            t = (poly.center.z - z0) / max(z1 - z0, 1e-6)
            c = top_v * (0.9 + 0.1 * t)
        for li in poly.loop_indices:
            ca.data[li].color = (c, c, c, 1.0)
    return o


def cap_mid(f):
    """Eave cap of floor f (a room stands on it): a thick drooping rim, dark gills underneath, a domed top. Tint: cap_f."""
    TINT[f"pagoda_cap_{f}_mid"] = f"cap_{f}"
    zu = floor_top(f) + L.CAP_UNDER
    top = eave_top(f)
    (ri, zi), (rm, zm), (r2, z2) = top
    re, ze = L.eave_r(f), floor_top(f) + L.CAP_UNDER + 0.8
    prof = [(0.0, zu), (L.room_out(f) - 0.5, zu), (re - 1.8, ze - 1.6), (re - 0.4, ze - 1.95), (re, ze - 1.2),
            (re - 0.1, ze - 0.4), (r2, z2), (rm, zm), (ri, zi), (0.0, zi)]
    out = [paint_under(revolve(f"Cap{f}", prof, g(0.96), segs=48), 1.0, 0.46)]
    for k in range(40):
        a = k * 9
        x0, y0 = polar(L.room_out(f) + 0.3, a)
        x1, y1 = polar(re - 2.0, a)
        out.append(tube(f"Gill{f}{k}", [(x0, y0, zu - 0.05), (x1, y1, ze - 1.75)], [0.22, 0.22], g(0.38), segs=4))
    return out


def _on_surface(name, pts, r, a, z_off, obj_fn):
    """Put an ornament on a (r, z) surface polyline at radius r, angle a, tilted to its slope."""
    dr = 0.4
    slope = math.degrees(math.atan2(surf_z(pts, r + dr) - surf_z(pts, r - dr), 2 * dr))
    x, y = polar(r, a)
    return obj_fn(name, (x, y, surf_z(pts, r) + z_off), (0, -slope, a))


def _chunky_spot(name, pos, rot, s, col):
    return blob(name, s, pos, col, subdiv=2, squash=(1, 1, 0.3), jitter=0.04, rot=rot)


def spots_mid():
    """Chunky white spots on an eave cap (built on CAP_NATIVE; one mesh scaled per cap). Tint: spots."""
    TINT["pagoda_spots_mid"] = "spots"
    f = CAP_NATIVE
    pts = eave_top(f)
    rr = random.Random(5)
    out = []
    for k in range(8):
        a = k * 45 + rr.uniform(-9, 9)
        r = rr.uniform(pts[0][0] + 1.6, pts[-1][0] - 1.3)
        s = rr.uniform(1.6, 2.2)
        out.append(_on_surface(f"Spot{k}", pts, r, a, 0.2, lambda n, p, rot: _chunky_spot(n, p, rot, s, g(1.0))))
    return out


def dome_top(f=DOME_NATIVE_FLOOR):
    """The dome's visible top: the collider rows with a little bulge between the rim and the first row."""
    pr = L.dome_profile(f)
    (r0, z0), (r1, z1) = pr[0], pr[1]
    bulge = (r0 - 1.6, z0 + (z1 - z0) * 0.4 + 0.4)
    return [pr[0], bulge] + pr[1:]


def dome(f=DOME_NATIVE_FLOOR):
    """The top floor's dome with a thick rim and dark gills, built for floor 4's rim; the game scales it to the top
    floor's eave_r. Tint: dome."""
    TINT["pagoda_dome"] = "dome"
    zu = floor_top(f) + L.CAP_UNDER
    top = dome_top(f)
    rd, zr = top[0]
    prof = [(0.0, zu), (L.room_out(f) - 0.5, zu), (rd - 1.8, zr - 2.6), (rd - 0.4, zr - 2.95), (rd + 0.0, zr - 2.2),
            (rd - 0.05, zr - 0.6)] + top
    out = [paint_under(revolve("Dome", prof, g(0.96), segs=56), 1.0, 0.46)]
    for k in range(44):
        a = k * 360 / 44
        x0, y0 = polar(L.room_out(f) + 0.3, a)
        x1, y1 = polar(rd - 2.0, a)
        out.append(tube(f"DGill{k}", [(x0, y0, zu - 0.05), (x1, y1, zr - 2.75)], [0.22, 0.22], g(0.38), segs=4))
    return out


def dome_spots(f=DOME_NATIVE_FLOOR):
    """Big chunky spots on the dome. Tint: spots."""
    TINT["pagoda_dome_spots"] = "spots"
    pts = dome_top(f)
    rr = random.Random(7)
    out = []
    ring = [(pts[0][0] - 2.2, 7, 2.6), (pts[2][0] - 3.5, 6, 3.0), (5.0, 3, 2.8)]
    k = 0
    for r, n, s in ring:
        for j in range(n):
            a = j * 360 / n + rr.uniform(-8, 8) + r * 3
            ss = s * rr.uniform(0.85, 1.15)
            out.append(_on_surface(f"DSpot{k}", pts, r, a, 0.25, lambda nm, p, rot: _chunky_spot(nm, p, rot, ss, g(1.0))))
            k += 1
    return out


# ---------------------------------------------------------------- turret
def turret_storey(f, top):
    """One storey of the stair turret: wall with the arch, post, landing (floors 2+), slit windows, band.
    top: the top floor's storey stands TURRET_RISE higher. Tint: stalk."""
    TINT["pagoda_turret_top" if top else "pagoda_turret_mid"] = "stalk"
    cx, cy = L.TURRET_C
    z = floor_top(f)
    h = (L.WALL_H + L.TURRET_RISE) if top else 16.0
    a_arch0, a_arch1 = L.ARCH_A - 15, L.ARCH_A + 15
    out = [arc_wall(f"TWall{f}", cx, cy, L.TURRET_IN, L.TURRET_OUT, z, h, g(0.93), a_arch1, a_arch0 + 360, lo=g(0.80)),
           arc_wall(f"TLintel{f}", cx, cy, L.TURRET_IN, L.TURRET_OUT, z + L.ARCH_H, h - L.ARCH_H, g(0.93), a_arch0, a_arch1)]
    # arch frame
    out.append(arc_wall(f"TArch{f}", cx, cy, L.TURRET_OUT - 0.1, L.TURRET_OUT + 0.4, z + L.ARCH_H - 0.6, 0.9, g(0.72),
                        a_arch0 - 3, a_arch1 + 3))
    out.append(cylinder(f"TPost{f}", L.POST_R, h, (cx, cy, z), g(0.80), segs=12))
    if f > 1:
        out.append(arc_wall(f"TLand{f}", cx, cy, L.RAMP_IN, L.RAMP_OUT, z - 0.6, 0.6, g(0.86), a_arch0, a_arch1))
    for k, a in enumerate((20, 120, 160)):
        x, y = polar(L.TURRET_OUT + 0.02, a)
        out.append(box(f"TSlit{f}{k}", (0.4, 1.3, 4.0), (cx + x, cy + y, z + 9.0), g(0.36), rot=(0, 0, a)))
    out.append(arc_wall(f"TBand{f}", cx, cy, L.TURRET_OUT - 0.1, L.TURRET_OUT + 0.4, z + h - 1.4, 1.1, g(0.74), 0, 360))
    return out


def ramp(f):
    """One turn of the turret's spiral ramp, floor f to f + 1, with a raised outer lip. Tint: ramp."""
    TINT["pagoda_ramp"] = "ramp"
    cx, cy = L.TURRET_C
    z0 = floor_top(f)
    segs = 33
    bm = bmesh.new()
    rows = []
    for i in range(segs + 1):
        t = i / segs
        a = L.RAMP_A0 + L.RAMP_SWEEP * t
        z = z0 + 16.0 * t
        row = []
        for r in (L.RAMP_IN, L.RAMP_OUT):
            x, y = polar(r, a)
            row.append(bm.verts.new((cx + x, cy + y, z)))
            row.append(bm.verts.new((cx + x, cy + y, z - L.RAMP_T)))
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
    out = [obj_from_bm(f"Ramp{f}", bm, g(0.95))]
    # tread stripes every 30 degrees (a lighter value)
    for k in range(1, 11):
        t = k / 11
        a = L.RAMP_A0 + L.RAMP_SWEEP * t
        x0, y0 = polar(L.RAMP_IN + 0.3, a)
        x1, y1 = polar(L.RAMP_OUT - 0.3, a)
        z = z0 + 16 * t + 0.03
        out.append(tube(f"Tread{f}{k}", [(cx + x0, cy + y0, z), (cx + x1, cy + y1, z)], [0.15, 0.15], g(0.75), segs=4))
    return out


def turret_cap(top=4):
    """The turret's own little spotted cap. Tint: turret_cap."""
    TINT["pagoda_turret_cap"] = "turret_cap"
    cx, cy = L.TURRET_C
    tz = L.turret_top_z(top)
    prof = [(0.0, tz), (9.2, tz), (9.2, tz + 1.0), (7.2, tz + 2.6), (6.0, tz + 4.4), (2.5, tz + 5.4), (0.0, tz + 5.6)]
    out = [revolve("TCap", prof, g(0.9), segs=28, cx=cx, cy=cy, lo=g(0.62))]
    rr = random.Random(9)
    for k in range(7):
        a = k * 360 / 7 + rr.uniform(-12, 12)
        x, y = polar(7.6, a)
        out.append(blob(f"TSpot{k}", 1.0, (cx + x, cy + y, tz + 2.3), g(1.0), subdiv=1, squash=(1, 1, 0.3), jitter=0,
                        rot=(0, 50, a)))
    return out


# ---------------------------------------------------------------- floor-1 pieces and decor
def door():
    """The round plank door, swung open (the game turns it shut while locked). Tint: wood."""
    TINT["pagoda_door"] = "wood"
    od = L.OPEN_DOOR
    z = floor_top(1) + L.DOOR_DISC + 0.4
    out = [cylinder("Door", L.DOOR_DISC, 1.0, (od["x"], od["y"], z), g(0.88), segs=22, rot=(90, 0, od["yaw"]))]
    for k in (-2, 0, 2):
        dx, dy = math.cos(math.radians(od["yaw"])) * k, math.sin(math.radians(od["yaw"])) * k
        out.append(box(f"DoorPlank{k}", (0.25, 1.15, 8.4), (od["x"] + dx, od["y"] + dy, z), g(0.64),
                       rot=(0, 0, od["yaw"])))
    return out


def door_ring():
    """The doorway's round frame with its hinge pins: fixed colours in every theme (a gameplay signal, like the jar's)."""
    TINT["pagoda_door_ring"] = None
    z = floor_top(1)
    r = L.room_out(1)
    dark = rgb(158, 108, 68)
    out = []
    # a ring of 20 short blocks round the doorway's arch (the doorway itself stays open)
    for k in range(21):
        t = math.radians(180 * k / 20)
        x = -math.cos(t) * (L.DOOR["width"] / 2 + 0.6)
        zz = z + 6.2 + math.sin(t) * 4.8 if k not in (0, 20) else z + 6.2
        out.append(box(f"Ring{k}", (1.3, 1.6, 1.3), (x, -r + 0.2, zz), dark, rot=(0, -math.degrees(t), 0)))
    for s in (-1, 1):
        out.append(box(f"Jamb{s}", (1.3, 1.6, 6.2), (s * (L.DOOR["width"] / 2 + 0.6), -r + 0.2, z + 3.1), dark))
    for k in (2.5, 8.0):
        out.append(cylinder(f"Pin{k}", 0.35, 1.2, (-L.DOOR_DISC - 0.2, L.DOOR["y"] - 0.9, z + k), rgb(168, 148, 110), segs=8))
    return out


def lamps(f):
    """Glow-shroom cluster in the middle of a room. Tint: glow."""
    TINT["pagoda_lamps"] = "glow"
    z = floor_top(f)
    out = []
    for k in range(3):
        x, y = polar(2.2, k * 120 + 30)
        h = 2.0 + k * 0.9
        out.append(cylinder(f"LampStem{f}{k}", 0.45, h, (x, y, z), g(0.8), segs=8))
        out.append(blob(f"LampCap{f}{k}", 1.3, (x, y, z + h + 0.2), g(1.0), subdiv=2, squash=(1, 1, 0.5), jitter=0))
    return out


def vine(f):
    """The owner's vine slide from floor f's hatch, out over the eaves, down into the moat. Tint: vine. Never collides."""
    TINT[f"pagoda_vine_{f}"] = "vine"
    hx, hy, hz = L.hatch_pos(f)
    a0, a1 = L.HATCH_A, 228.0
    pts = [(hx, hy, hz - 0.5)]
    x, y = polar(L.room_out(f) + 1.0, a0)
    pts.append((x, y, hz - 1.2))
    (ri, zt), (re, ze) = L.eave_profile(f - 1)
    x, y = polar(re + 1.6, a0 + 6)
    pts.append((x, y, ze + 0.6))
    n = 6
    for k in range(1, n + 1):
        t = k / n
        a = a0 + 6 + (a1 - a0 - 6) * t
        x, y = polar(36.3, a)
        pts.append((x, y, (ze + 0.6) * (1 - t) ** 1.3 + 1.0 * t))
    out = [tube(f"Vine{f}", pts, [1.4] * len(pts), g(0.82), segs=10)]
    for k in range(2, len(pts) - 1):
        x, y, z = pts[k]
        out.append(blob(f"Leaf{f}{k}", 1.5, (x, y, z + 1.5), g(1.0), subdiv=1, squash=(1.4, 0.7, 0.3), jitter=0.05))
    return out


def foot_decor_classic():
    """Mini mushrooms round the foot (multi-colour, not a tint piece)."""
    TINT["pagoda_foot_decor"] = None
    rr = random.Random(3)
    cols = [rgb(232, 72, 72), rgb(176, 112, 232), rgb(250, 150, 60)]
    out = []
    for k in range(16):
        a = k * 360 / 16 + rr.uniform(-8, 8)
        if -110 < ((a + 180) % 360) - 180 < -70 or 70 < a % 360 < 110:
            continue
        r = rr.uniform(L.ROOM_R[0] + 2.2, 33.6)
        x, y = polar(r, a)
        h = rr.uniform(1.0, 2.4)
        out.append(cylinder(f"MiniStem{k}", 0.35, h, (x, y, 0.9), rgb(246, 232, 204), segs=8))
        c = cols[k % 3]
        out.append(blob(f"MiniCap{k}", 0.9 + h * 0.25, (x, y, 0.9 + h), c, subdiv=1, squash=(1, 1, 0.55), jitter=0))
    return out


# ---------------------------------------------------------------- theme companions (<= 3 meshes per theme, own colours)
# kind: "cap"  one mesh on eave cap CAP_NATIVE, scaled onto every eave cap
#       "rim"  a ring under the eave rim of CAP_NATIVE, scaled onto every eave cap AND the dome's rim
#       "dome" one mesh on the dome (scaled with it)
#       "climber" one small mesh placed twice per floor on the wall (CLIMBER_ANGLES)
#       "foot" the foot decor ring (replaces the classic mini mushrooms)
# "replaces": the base piece the companion stands in for (starlight's star spots replace the white spots).
WHITE_SNOW = rgb(244, 250, 255)


def _rim(f=CAP_NATIVE):
    return L.eave_r(f), floor_top(f) + L.CAP_UNDER + 0.8


def snow_cap():
    """Frost & Sea: a snow blanket on the cap's top with lumps along the rim."""
    pts = eave_top(CAP_NATIVE)
    ri, re = pts[0][0], pts[-1][0]
    rs = [ri + (re - ri) * t for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
    up = [(r, surf_z(pts, r) + 0.55) for r in rs]
    down = [(r, surf_z(pts, r) - 0.05) for r in reversed(rs)]
    out = [revolve("Snow", up + down, WHITE_SNOW, segs=48, lo=rgb(214, 236, 252), closed=True)]
    rr = random.Random(21)
    rim_r, rim_z = _rim()
    for k in range(18):
        a = k * 20 + rr.uniform(-6, 6)
        x, y = polar(rim_r - 0.6, a)
        out.append(blob(f"SnowLump{k}", rr.uniform(0.9, 1.4), (x, y, rim_z + 0.1), WHITE_SNOW, subdiv=1,
                        squash=(1.3, 1, 0.8), jitter=0.08, seed=k))
    return out


def snow_dome():
    """Frost & Sea: a snow cap on the dome's crown with lumps where it ends."""
    pts = dome_top()
    rs = [0.0, 6.0, 12.0, pts[2][0] + 1.0]
    up = [(r, surf_z(pts, r) + 0.6) for r in rs]
    down = [(r, surf_z(pts, r) - 0.05) for r in reversed(rs)]
    out = [revolve("DSnow", up + down, WHITE_SNOW, segs=48, lo=rgb(214, 236, 252))]
    rr = random.Random(22)
    for k in range(16):
        a = k * 22.5 + rr.uniform(-6, 6)
        r = rs[-1] + 0.2
        x, y = polar(r, a)
        out.append(blob(f"DSnowLump{k}", rr.uniform(1.0, 1.6), (x, y, surf_z(pts, r) + 0.2), WHITE_SNOW, subdiv=1,
                        squash=(1.2, 1, 0.7), jitter=0.08, seed=40 + k))
    return out


def icicles():
    """Frost & Sea: icicles hanging under the rim (a rim ring), pointing down."""
    re, ze = _rim()
    rr = random.Random(23)
    out = []
    for k in range(30):
        a = k * 12 + rr.uniform(-3, 3)
        x, y = polar(re - 0.5, a)
        ln = rr.uniform(1.8, 4.0)
        out.append(cylinder(f"Ice{k}", 0.08, ln, (x, y, ze - 1.85 - ln), rgb(206, 236, 255), segs=5, r_top=0.6))
    return out


def flower_pots():
    """Garden: hanging flower baskets under the rim (a rim ring)."""
    re, ze = _rim()
    out = []
    buds = [rgb(250, 150, 182), rgb(252, 216, 110), rgb(196, 166, 232), rgb(255, 255, 255)]
    for k in range(10):
        a = k * 36 + 18
        x, y = polar(re - 1.4, a)
        zb = ze - 4.4
        out.append(tube(f"Rope{k}", [(x, y, ze - 1.9), (x, y, zb + 1.2)], [0.08, 0.08], rgb(120, 90, 60), segs=3))
        out.append(cylinder(f"Pot{k}", 1.0, 1.2, (x, y, zb), rgb(222, 140, 102), segs=10, r_top=1.3))
        for j in range(5):
            bx, by = polar(0.75, j * 72 + k * 13)
            out.append(blob(f"Bud{k}{j}", 0.6, (x + bx, y + by, zb + 1.5), buds[(j + k) % 4], subdiv=1, jitter=0))
        out.append(blob(f"Leaves{k}", 1.1, (x, y, zb + 1.1), rgb(110, 176, 80), subdiv=1, squash=(1.2, 1.2, 0.6),
                        jitter=0.1))
    return out


CLIMBER_ANGLES = {1: (-45.0, 215.0), 2: (-60.0, 230.0), 3: (-45.0, 230.0), 4: (-30.0, 235.0)}


def garden_climber(f, a):
    """Garden: a flower window box under a window and a flowering vine climbing the stalk wall (placed twice a floor)."""
    z = floor_top(f)
    r = L.room_out(f) + 0.6
    cx, cy = polar(r, a)
    tx, ty = -math.sin(math.radians(a)), math.cos(math.radians(a))
    out = [box(f"WBox{f}{a:.0f}", (4.2, 1.4, 1.2), (cx, cy, z + 4.2), rgb(176, 120, 80), rot=(0, 0, a + 90))]
    buds = [rgb(250, 150, 182), rgb(252, 216, 110), rgb(196, 166, 232)]
    for j in range(5):
        u = -1.6 + j * 0.8
        out.append(blob(f"WBud{f}{a:.0f}{j}", 0.7, (cx + tx * u, cy + ty * u, z + 5.1), buds[j % 3], subdiv=1, jitter=0))
    vx, vy = cx + tx * 3.2, cy + ty * 3.2
    pts = [(vx, vy, z + 0.2)]
    for k in range(1, 6):
        s = math.sin(k * 1.3) * 0.9
        pts.append((vx + tx * s, vy + ty * s, z + k * 2.2))
    out.append(tube(f"Vine{f}{a:.0f}", pts, [0.3] * len(pts), rgb(96, 168, 80), segs=6))
    for k in range(1, 6):
        x, y, zz = pts[k]
        out.append(blob(f"VLeaf{f}{a:.0f}{k}", 0.8, (x + tx * 0.6, y + ty * 0.6, zz), rgb(120, 190, 90), subdiv=1,
                        squash=(1.3, 0.5, 0.8), jitter=0.05))
        if k % 2:
            out.append(blob(f"VFlower{f}{a:.0f}{k}", 0.75, (x - tx * 0.5, y - ty * 0.5, zz + 0.4), buds[k % 3], subdiv=1,
                            jitter=0))
    return out


def _star(name, pos, rot, s, col, th=0.35):
    from mathutils import Euler, Matrix, Vector
    bm = bmesh.new()
    pts = [polar(s if k % 2 == 0 else s * 0.45, 90 + k * 36) for k in range(10)]
    top = [bm.verts.new((x, y, th)) for x, y in pts]
    bot = [bm.verts.new((x, y, 0.0)) for x, y in pts]
    c_t, c_b = bm.verts.new((0, 0, th)), bm.verts.new((0, 0, 0))
    for k in range(10):
        j = (k + 1) % 10
        bm.faces.new((c_t, top[k], top[j]))
        bm.faces.new((c_b, bot[j], bot[k]))
        bm.faces.new((bot[k], bot[j], top[j], top[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    m = Matrix.Translation(Vector(pos)) @ Euler([math.radians(v) for v in rot], "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return obj_from_bm(name, bm, col)


STAR_GOLD = rgb(255, 214, 92)


def star_spots_cap():
    """Starlight: gold stars instead of the white spots on the eave caps (replaces pagoda_spots_mid)."""
    pts = eave_top(CAP_NATIVE)
    rr = random.Random(31)
    out = []
    for k in range(9):
        a = k * 40 + rr.uniform(-8, 8)
        r = rr.uniform(pts[0][0] + 1.6, pts[-1][0] - 1.4)
        s = rr.uniform(1.7, 2.3)
        out.append(_on_surface(f"Star{k}", pts, r, a, 0.05,
                               lambda n, p, rot: _star(n, p, rot, s, STAR_GOLD)))
    return out


def star_spots_dome():
    """Starlight: gold stars on the dome (replaces pagoda_dome_spots)."""
    pts = dome_top()
    rr = random.Random(32)
    out = []
    k = 0
    for r, n, s in ((pts[0][0] - 2.2, 8, 2.5), (pts[2][0] - 3.5, 6, 2.8)):
        for j in range(n):
            a = j * 360 / n + rr.uniform(-8, 8)
            out.append(_on_surface(f"DStar{k}", pts, r, a, 0.05,
                                   lambda nm, p, rot: _star(nm, p, rot, s, STAR_GOLD)))
            k += 1
    return out


def star_garland():
    """Starlight: glowing stars dangling under the rim (a rim ring)."""
    re, ze = _rim()
    rr = random.Random(33)
    out = []
    for k in range(18):
        a = k * 20
        x, y = polar(re - 0.6, a)
        d = rr.uniform(1.2, 3.2)
        out.append(tube(f"Str{k}", [(x, y, ze - 1.9), (x, y, ze - 1.9 - d)], [0.07, 0.07], rgb(236, 196, 104), segs=3))
        out.append(_star(f"GStar{k}", (x, y, ze - 2.6 - d), (90, 0, a + 90), 1.2, rgb(255, 236, 150), th=0.4))
    return out


SPRINKLES = [rgb(132, 220, 190), rgb(252, 216, 110), rgb(196, 166, 232), rgb(255, 255, 255), rgb(120, 190, 250)]


def _sprinkle(name, pos, rot, col, along):
    """A sprinkle lying on the surface, its long side radial (along) or round the cap."""
    return box(name, (1.8, 0.5, 0.45) if along else (0.5, 1.8, 0.45), pos, col, rot=rot)


def sprinkles_cap():
    """Candy: big sprinkles all over the eave cap (a cap mesh)."""
    pts = eave_top(CAP_NATIVE)
    rr = random.Random(41)
    out = []
    for k in range(70):
        a = rr.uniform(0, 360)
        r = rr.uniform(pts[0][0] + 1.0, pts[-1][0] - 0.6)
        col = SPRINKLES[k % len(SPRINKLES)]
        spin = rr.uniform(0, 180)
        out.append(_on_surface(f"Spr{k}", pts, r, a, 0.25,
                               lambda n, p, rot: _sprinkle(n, p, rot, col, spin < 90)))
    return out


def sprinkles_dome():
    """Candy: sprinkles on the dome and a cherry on top (a dome mesh)."""
    pts = dome_top()
    rr = random.Random(42)
    out = []
    for k in range(110):
        a = rr.uniform(0, 360)
        r = rr.uniform(3.0, pts[0][0] - 1.0)
        col = SPRINKLES[k % len(SPRINKLES)]
        spin = rr.uniform(0, 180)
        out.append(_on_surface(f"DSpr{k}", pts, r, a, 0.25,
                               lambda n, p, rot: _sprinkle(n, p, rot, col, spin < 90)))
    zt = pts[-1][1]
    out.append(blob("Cherry", 2.4, (5.5, 4.0, zt + 2.2), rgb(214, 36, 84), subdiv=2, jitter=0))
    out.append(blob("CherryHi", 0.6, (4.6, 2.6, zt + 3.4), rgb(255, 190, 210), subdiv=1, jitter=0))
    out.append(tube("CherryStem", [(5.5, 4.0, zt + 4.4), (6.2, 4.6, zt + 6.4), (7.6, 4.4, zt + 7.4)], [0.25, 0.22, 0.18],
                    rgb(110, 150, 70), segs=5))
    return out


def moss_ring():
    """Forest: moss clumps on the cap edge with ivy hanging off the rim (a rim ring)."""
    re, ze = _rim()
    rr = random.Random(51)
    out = []
    for k in range(26):
        a = k * 360 / 26 + rr.uniform(-4, 4)
        x, y = polar(re - 0.9, a)
        out.append(blob(f"Moss{k}", rr.uniform(0.9, 1.4), (x, y, ze + 0.1), rgb(116, 170, 82), subdiv=1,
                        squash=(1.3, 1, 0.55), jitter=0.12, seed=k))
        if k % 2 == 0:
            x2, y2 = polar(re + 0.1, a)
            ln = rr.uniform(1.5, 3.5)
            out.append(tube(f"Ivy{k}", [(x2, y2, ze - 0.6), (x2, y2, ze - 1.9 - ln)], [0.2, 0.1], rgb(96, 160, 80),
                            segs=4))
    return out


def foot_ring(theme):
    """The theme's foot decor ring (classic: the base's mini mushrooms)."""
    if theme == "classic":
        return foot_decor_classic()
    rr = random.Random(11)
    out = []
    for k in range(16):
        a = k * 360 / 16 + rr.uniform(-8, 8)
        if -110 < ((a + 180) % 360) - 180 < -70 or 70 < a % 360 < 110:
            continue
        r = rr.uniform(L.ROOM_R[0] + 2.4, 33.4)
        x, y = polar(r, a)
        if theme == "garden":
            out.append(cylinder(f"SunStem{k}", 0.22, 3.4, (x, y, 0.9), rgb(110, 170, 80), segs=6))
            out.append(cylinder(f"SunHead{k}", 1.3, 0.35, (x, y - 0.1, 4.4), rgb(252, 206, 70), segs=12, rot=(80, 0, 0)))
            out.append(cylinder(f"SunEye{k}", 0.6, 0.4, (x, y - 0.25, 4.45), rgb(140, 90, 50), segs=10, rot=(80, 0, 0)))
        elif theme == "candy":
            out.append(cylinder(f"Stick{k}", 0.16, 2.8, (x, y, 0.9), rgb(252, 240, 236), segs=5))
            out.append(cylinder(f"Pop{k}", 1.2, 0.4, (x, y - 0.1, 4.0), [rgb(246, 146, 192), rgb(132, 220, 190)][k % 2],
                                segs=14, rot=(80, 0, 0)))
        elif theme == "mushroom":
            h = rr.uniform(1.2, 2.6)
            out.append(cylinder(f"TStem{k}", 0.4, h, (x, y, 0.9), rgb(246, 236, 214), segs=8))
            out.append(blob(f"TCap{k}", 1.1 + h * 0.25, (x, y, 0.9 + h), rgb(176, 104, 70), subdiv=1, squash=(1, 1, 0.5),
                            jitter=0))
    return out


# theme -> [(mesh name, kind, builder, replaces)]
THEME_PIECES = {
    "classic": [],
    "crystal": [("pagoda_snow_cap@crystal", "cap", snow_cap, None),
                ("pagoda_snow_dome@crystal", "dome", snow_dome, None),
                ("pagoda_icicles@crystal", "rim", icicles, None)],
    "garden": [("pagoda_flower_pots@garden", "rim", flower_pots, None),
               ("pagoda_climber@garden", "climber", garden_climber, None),
               ("pagoda_foot@garden", "foot", lambda: foot_ring("garden"), "pagoda_foot_decor")],
    "starlight": [("pagoda_star_spots@starlight", "cap", star_spots_cap, "pagoda_spots_mid"),
                  ("pagoda_star_dome@starlight", "dome", star_spots_dome, "pagoda_dome_spots"),
                  ("pagoda_star_garland@starlight", "rim", star_garland, None)],
    "candy": [("pagoda_sprinkles_cap@candy", "cap", sprinkles_cap, None),
              ("pagoda_sprinkles_dome@candy", "dome", sprinkles_dome, None),
              ("pagoda_foot@candy", "foot", lambda: foot_ring("candy"), "pagoda_foot_decor")],
    "mushroom": [("pagoda_moss@mushroom", "rim", moss_ring, None),
                 ("pagoda_foot@mushroom", "foot", lambda: foot_ring("mushroom"), "pagoda_foot_decor")],
}


# PIECES: name -> builder (for measuring through iterate.py, see _pagoda_piece.py)
PIECES = {
    "pagoda_room_1": lambda: room(1), "pagoda_room_2": lambda: room(2), "pagoda_room_3": lambda: room(3),
    "pagoda_room_4": lambda: room(4),
    "pagoda_deck_2": lambda: deck(2), "pagoda_deck_3": lambda: deck(3), "pagoda_deck_4": lambda: deck(4),
    "pagoda_cap_1_mid": lambda: cap_mid(1), "pagoda_cap_2_mid": lambda: cap_mid(2), "pagoda_cap_3_mid": lambda: cap_mid(3),
    "pagoda_dome": lambda: dome(),
    "pagoda_spots_mid": spots_mid, "pagoda_dome_spots": lambda: dome_spots(),
    "pagoda_turret_mid": lambda: turret_storey(2, False), "pagoda_turret_top": lambda: turret_storey(4, True),
    "pagoda_ramp": lambda: ramp(1), "pagoda_turret_cap": lambda: turret_cap(),
    "pagoda_door": door, "pagoda_door_ring": door_ring, "pagoda_lamps": lambda: lamps(2),
    "pagoda_vine_2": lambda: vine(2), "pagoda_vine_3": lambda: vine(3), "pagoda_vine_4": lambda: vine(4),
    "pagoda_foot_decor": foot_decor_classic,
}
for _t, _lst in THEME_PIECES.items():
    for _name, _kind, _fn, _rep in _lst:
        PIECES[_name] = (lambda fn: (lambda: fn(2, 0.0)))(_fn) if _kind == "climber" else _fn
