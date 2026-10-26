# Mushroom Pagoda base: the layout (pure data, no bpy). Design only, not built in the game.
# Read by _base_design_common.check / plans, models/_pagoda_pieces.py and models/_base_pagoda_design.py.
# Coordinates: kit = plot-local. x right, y = plot-local z (y < 0 is the front, the door), z up. 1 unit = 1 stud.
# Floor f walks at floor_top(f) = 1 + 16 (f - 1). Angles: a point at angle a, radius r is (r cos a, r sin a); -90 is
# the door side, +90 the back, where the stair turret stands.
#
# The base: each floor is a round stalk room (wall WALL_H tall) under a mushroom cap. A cap is an EAVE cap (a straight
# cone from the next room's wall out to the eave) while a room stands on it, and the DOME while its floor is the top
# one. The stair turret is a fat mushroom stalk at the back, half sunk into the rooms: inside, a spiral ramp climbs
# one floor per turn round a post (330 degrees of slope + a 30-degree flat landing at the arch into each room).
import math
import os

from models._base_design_common import FLOOR_H, PAD, floor_top, polar

ID = "pagoda"
NAME = "Mushroom Pagoda"
FLOORS = int(os.environ.get("LAYOUT_FLOORS", "4"))  # floors standing; tools/export_base_shape.py varies it

# ---- room shells ----
ROOM_R = (28.0, 25.5, 23.5, 22.0)      # inner wall radius per floor
WALL_T = 1.0
WALL_H = 11.6                          # stalk wall height (the cap sits on it)
CAP_UNDER = 11.2                       # cap underside at the wall, above the floor
EAVE = (4.5, 5.0, 5.0, 5.0)            # cap overhang past the wall's outer face
WALL_SEGS = 16                         # collider segments per full circle (22.5 degrees each)


def room_out(f):
    return ROOM_R[f - 1] + WALL_T


def eave_r(f):
    return room_out(f) + EAVE[f - 1]


# ---- stair turret ----
TURRET_C = (0.0, 25.0)                 # turret centre
TURRET_IN = 8.0                        # inner face of the turret wall
TURRET_T = 1.0
TURRET_OUT = TURRET_IN + TURRET_T      # 9.0
POST_R = 1.4
RAMP_IN, RAMP_OUT = 1.6, 8.0           # walking surface between the post and the wall
ARCH_A = 270.0                         # turret-local angle of the arch (towards the room centre)
LANDING = 30.0                         # flat landing arc at the arch, degrees
RAMP_SWEEP = 360.0 - LANDING           # 330
RAMP_A0 = ARCH_A + LANDING / 2         # 285: the ramp leaves the landing here and arrives at 255 a floor up
RAMP_T = 0.8                           # ramp collider thickness
RAMP_BOXES = 12                        # collider boxes per ramp turn
ARCH_H = 9.0                           # arch height; a lintel closes the wall above it
TURRET_SEGS = 12                       # wall collider segments per turn (30 degrees; the arch is one of them)
TURRET_RISE = 15.0                     # the turret stands this far above the top room's wall: its cap peeks over the dome from the front


def turret_top_z(top):
    return floor_top(top) + WALL_H + TURRET_RISE


# ---- floor 1 front ----
DOOR = {"x": 0.0, "y": -(ROOM_R[0] + WALL_T / 2), "width": 8.0, "height": 11.0, "facing": -90}
VAT = {"x": 8.5, "y": -20.5}
LOCK_BUTTON = {"x": -8.5, "y": -21.0}
SPAWN = (0.0, -12.5)
BRIDGE = {"width": 10.0, "from": -(ROOM_R[0] + WALL_T), "to": -38.5}

# ---- pads ----
PAD_R = (20.25, 17.0, 15.5, 14.0)
FLOOR1_PAD_ANGLES = (-33.0, -6.0, 21.0, 48.0, 132.0, 159.0, 186.0, 213.0)   # 27 degrees apart, the front left free
UPPER_PAD_ARC = {2: (136.0, 404.0), 3: (132.0, 408.0), 4: (132.0, 408.0)}  # 8 pads per floor, clear of the turret at 90


def pad_angle(j):
    f = (j - 1) // 8 + 1
    k = (j - 1) % 8
    if f == 1:
        return FLOOR1_PAD_ANGLES[k]
    a0, a1 = UPPER_PAD_ARC[f]
    return (a0 + k * (a1 - a0) / 7) % 360


PADS = []
for _j in range(1, 33):
    _f = (_j - 1) // 8 + 1
    _x, _y = polar(PAD_R[_f - 1], pad_angle(_j))
    PADS.append({"j": _j, "floor": _f, "x": round(_x, 3), "y": round(_y, 3), "yaw": round(90 - pad_angle(_j), 3)})

# ---- the owner exit: a curved glass goo tube over the caps (a scripted move, never collides) ----
HATCH_A = 191.0                         # on the room wall between pads at 171.4 and 210.9 (floors 2-4)


def hatch_pos(f):
    x, y = polar(ROOM_R[f - 1] - 0.5, HATCH_A)
    return (round(x, 3), round(y, 3), floor_top(f) + 2.5)


EXIT = {"floor": 4, "hatch": hatch_pos(4), "lands": polar(34.0, 252),  # beside the glass tube's pool (_drop_exit_styles.pagoda_cap_pool_at)
        "floor_check": "radius < ROOM_R[top] and y >= floorTop(top)"}
# The game's inside test (the drop exit's owner check, the lock guard): the round room of each floor.
# the stair turret counts as inside too (its ramps reach past the upper rooms' radii; reached only from inside)
INSIDE = {"kind": "round", "radii": list(ROOM_R), "extra": [{"x": TURRET_C[0], "z": TURRET_C[1], "r": TURRET_IN}]}

# ---- lamps (glow-shroom cluster in each room's middle) ----
LAMP_R = 3.7

OBSTACLES = [{"floor": 1, "x": VAT["x"], "y": VAT["y"], "r": 4.0, "label": "vat"},
             {"floor": 1, "x": LOCK_BUTTON["x"], "y": LOCK_BUTTON["y"], "r": 1.6, "label": "lock"}]
for _f in range(1, 5):
    OBSTACLES.append({"floor": _f, "x": 0.0, "y": 0.0, "r": LAMP_R, "label": "lamps"})


# ---- helpers ----
def _norm(a):
    return a % 360.0


def _turret_gap(f):
    """Half-angle (about +90) of the room wall inside the turret's outer face."""
    rc = ROOM_R[f - 1] + WALL_T / 2
    d = TURRET_C[1]
    c = (rc * rc + d * d - TURRET_OUT * TURRET_OUT) / (2 * rc * d)
    return math.degrees(math.acos(c))


def _door_gap():
    rc = ROOM_R[0] + WALL_T / 2
    return math.degrees(math.asin(DOOR["width"] / 2 / rc))


def room_arcs(f):
    """Angle ranges (from, to) where floor f's room wall stands."""
    g = _turret_gap(f)
    gaps = [(90 - g, 90 + g)]
    if f == 1:
        d = _door_gap()
        gaps.append((270 - d, 270 + d))
    gaps.sort()
    arcs = []
    for k, (g0, g1) in enumerate(gaps):
        n0 = gaps[(k + 1) % len(gaps)][0]
        arcs.append((g1, n0 if n0 > g1 else n0 + 360))
    return arcs


def _circ_segments(cx, cy, r_face, thick, a_from, a_to, max_step):
    """Wall segments for an arc whose inner face is the circle r_face: straight boxes circumscribing it (the collider
    never pokes into the room; at the joints it sits at most r_face (1/cos(step/2) - 1) behind the visible face)."""
    n = max(1, int(math.ceil((a_to - a_from) / max_step - 1e-9)))
    step = (a_to - a_from) / n
    rc = r_face + thick / 2
    out = []
    for i in range(n):
        a = a_from + step * (i + 0.5)
        half = rc * math.tan(math.radians(step / 2))
        mx, my = polar(rc, a)
        tx, ty = -math.sin(math.radians(a)), math.cos(math.radians(a))
        out.append(((cx + mx - tx * half, cy + my - ty * half), (cx + mx + tx * half, cy + my + ty * half), a, 2 * half))
    return out


def _turret_segments(arch_only=None):
    """Turret wall segments (local angle mids ARCH_A + k*30); arch_only True/False picks the arch segment or the rest."""
    step = 360.0 / TURRET_SEGS
    out = []
    for k in range(TURRET_SEGS):
        a0 = ARCH_A - step / 2 + k * step
        seg = _circ_segments(TURRET_C[0], TURRET_C[1], TURRET_IN, TURRET_T, a0, a0 + step, step)[0]
        is_arch = k == 0
        if arch_only is None or arch_only == is_arch:
            out.append(seg)
    return out


WALLS = []
for _f in range(1, 5):
    for _a0, _a1 in room_arcs(_f):
        for _p, _q, _a, _L in _circ_segments(0, 0, ROOM_R[_f - 1], WALL_T, _a0, _a1, 360 / WALL_SEGS):
            WALLS.append({"floor": _f, "a": _p, "b": _q, "thick": WALL_T, "h": WALL_H, "role": "room"})
    for _p, _q, _a, _L in _turret_segments(arch_only=False):
        WALLS.append({"floor": _f, "a": _p, "b": _q, "thick": TURRET_T, "h": FLOOR_H, "role": "turret"})

# ---- ramps (turret spiral, floor f -> f + 1) ----
RAMPS = []
LANDINGS = []
for _f in range(1, 4):
    RAMPS.append({"name": f"turret ramp {_f}->{_f + 1}", "floor": _f, "kind": "helix", "c": TURRET_C,
                  "r_in": RAMP_IN, "r_out": RAMP_OUT, "a0": RAMP_A0, "sweep": RAMP_SWEEP, "z0": floor_top(_f),
                  "rise": FLOOR_H})
for _f in range(2, 5):
    _x, _y = polar(RAMP_IN + (RAMP_OUT - RAMP_IN) / 2, ARCH_A)
    LANDINGS.append({"name": f"landing {_f}", "floor": _f, "x": TURRET_C[0] + _x, "y": TURRET_C[1] + _y,
                     "z": floor_top(_f), "sx": 2 * RAMP_OUT * math.sin(math.radians(LANDING / 2)) + 0.6,
                     "sy": RAMP_OUT - RAMP_IN})


# ---- caps (the cone the next room stands on, or the dome) ----
def eave_profile(f):
    """Eave cap of floor f (a room stands on it): straight cone top from the next room's wall to the eave, a rounded lip.
    (r, z) from the inside out; the collider facets follow the cone."""
    zt = floor_top(f + 1) - 0.4       # 0.2 above the visual cap at both ends: the domed top bulges 0.45 in the middle
    ze = floor_top(f) + CAP_UNDER + 1.2
    return [(room_out(f + 1), zt), (eave_r(f), ze)]


def dome_profile(f, rim=None):
    """Dome of floor f as the top floor: (r, z) rim -> crown. rim = the dome's rim radius (eave_r(f))."""
    rd = eave_r(f) if rim is None else rim
    zc = floor_top(f) + CAP_UNDER
    return [(rd, zc + 1.0), (rd - 4.0, zc + 6.4), (rd - 11.0, zc + 10.4), (rd - 14.0, zc + 11.2), (0.0, zc + 11.6)]


DOME_FACETS = 12                         # per row; 2 rows + a crown disc


# ---- colliders (every collidable primitive, the placeholder list; FLOORS = 4) ----
def _box(name, f, role, pos, size, rot=(0.0, 0.0, 0.0), **kw):
    d = {"name": name, "floor": f, "role": role, "kind": "box", "pos": tuple(round(v, 3) for v in pos),
         "size": tuple(round(v, 3) for v in size), "rot": tuple(round(v, 3) for v in rot)}
    d.update(kw)
    return d


def _cyl(name, f, role, pos, diameter, height, **kw):
    d = {"name": name, "floor": f, "role": role, "kind": "cyl", "pos": pos, "size": (diameter, diameter, height),
         "rot": (0, 0, 0)}
    d.update(kw)
    return d


def _ring_facets(name, f, role, r_in, z_in, r_out, z_out, n, thick=0.8, inscribed_out=True):
    """n planar facets on a cone from (r_in, z_in) to (r_out, z_out): each facet's outer edge is the chord between two
    points on the outer circle (corners exactly on r_out). Top face = the cone surface along each facet's mid line."""
    out = []
    step = 360.0 / n
    half = math.radians(step / 2)
    ro = r_out * math.cos(half) if inscribed_out else r_out
    run = ro - r_in
    rise = z_out - z_in
    slant = math.hypot(run, rise)
    tilt = math.degrees(math.atan2(-rise, run))  # facet rises towards the inside when the cone falls outward
    width = 2 * r_out * math.sin(half)
    for k in range(n):
        a = k * step + step / 2
        rm = (r_in + ro) / 2
        zm = (z_in + z_out) / 2
        # move the centre down along the facet normal by thick / 2
        nr, nz = rise / slant, run / slant      # outward-up normal of the cone line (r, z) is (-rise, run)/slant
        nr = -rise / slant
        cx, cy = polar(rm - nr * thick / 2, a)
        cz = zm - nz * thick / 2
        out.append(_box(f"{name}_{k + 1}", f, role, (cx, cy, cz), (width, slant, thick), (tilt, 0.0, a + 90)))
    return out


COLLIDERS = []
for _f in range(1, FLOORS + 1):
    _z = floor_top(_f)
    _top = _f == FLOORS
    # room wall
    for _i, _w in enumerate([w for w in WALLS if w["floor"] == _f and w["role"] == "room"]):
        (_ax, _ay), (_bx, _by) = _w["a"], _w["b"]
        _L = math.hypot(_bx - _ax, _by - _ay)
        _yaw = math.degrees(math.atan2(_by - _ay, _bx - _ax))
        COLLIDERS.append(_box(f"Wall{_f}_{_i + 1}", _f, "room wall", ((_ax + _bx) / 2, (_ay + _by) / 2, _z + WALL_H / 2),
                              (_L, WALL_T, WALL_H), (0, 0, _yaw)))
    # turret wall: full storey except the arch; a lintel over the arch; the top floor's turret runs up TURRET_RISE more
    _h = FLOOR_H if not _top else WALL_H + TURRET_RISE
    for _i, (_p, _q, _a, _L) in enumerate(_turret_segments(arch_only=False)):
        _yaw = math.degrees(math.atan2(_q[1] - _p[1], _q[0] - _p[0]))
        COLLIDERS.append(_box(f"TurretWall{_f}_{_i + 1}", _f, "turret wall",
                              ((_p[0] + _q[0]) / 2, (_p[1] + _q[1]) / 2, _z + _h / 2), (_L, TURRET_T, _h), (0, 0, _yaw)))
    _p, _q, _a, _L = _turret_segments(arch_only=True)[0]
    _yaw = math.degrees(math.atan2(_q[1] - _p[1], _q[0] - _p[0]))
    COLLIDERS.append(_box(f"TurretLintel{_f}", _f, "turret wall", ((_p[0] + _q[0]) / 2, (_p[1] + _q[1]) / 2,
                          _z + ARCH_H + (_h - ARCH_H) / 2), (_L, TURRET_T, _h - ARCH_H), (0, 0, _yaw)))
    COLLIDERS.append(_cyl(f"TurretPost{_f}", _f, "turret post", (TURRET_C[0], TURRET_C[1], _z + _h / 2), 2 * POST_R, _h))
    # ramp up from this floor (built with the floor above: Floor_<f+1>)
    if not _top:
        _step = RAMP_SWEEP / RAMP_BOXES
        _rm = (RAMP_IN + RAMP_OUT) / 2
        _slope = math.degrees(math.atan2(FLOOR_H, math.radians(RAMP_SWEEP) * _rm))
        for _k in range(RAMP_BOXES):
            _am = RAMP_A0 + _step * (_k + 0.5)
            _zm = _z + FLOOR_H * (_k + 0.5) / RAMP_BOXES
            _x, _y = polar(_rm, _am)
            _len = 2 * RAMP_OUT * math.sin(math.radians(_step / 2)) + 0.4
            COLLIDERS.append(_box(f"Ramp{_f + 1}_{_k + 1}", _f + 1, "ramp",
                                  (TURRET_C[0] + _x, TURRET_C[1] + _y, _zm - RAMP_T / 2),
                                  (_len, RAMP_OUT - RAMP_IN, RAMP_T), (0, -_slope, _am + 90)))
    # landing and deck (upper floors; floor 1 walks on the plot floor)
    if _f > 1:
        _g = [g for g in LANDINGS if g["floor"] == _f][0]
        COLLIDERS.append(_box(f"Landing{_f}", _f, "landing", (_g["x"], _g["y"], _z - 0.3), (_g["sy"], _g["sx"], 0.6)))
        COLLIDERS.append(_cyl(f"DeckCentre{_f}", _f, "deck", (0, 0, _z - 0.3), 18.0, 0.6))
        _R = ROOM_R[_f - 1] + WALL_T / 2
        for _k in range(16):
            _a = _k * 22.5 + 11.25
            _w = 2 * _R * math.tan(math.radians(11.25))
            # clip the sector box where it would reach into the turret: its far corners stay outside the turret's
            # outer face (they may sit inside the turret wall, never in the stair)
            _r_end = _R
            for _t in (-1, 1):
                for _r in [x / 4 for x in range(36, int(_R * 4) + 1)]:
                    _cx, _cy = polar(_r, _a)
                    _ex, _ey = _cx - math.sin(math.radians(_a)) * _t * _w / 2, _cy + math.cos(math.radians(_a)) * _t * _w / 2
                    if math.hypot(_ex - TURRET_C[0], _ey - TURRET_C[1]) < TURRET_IN + 0.2:
                        _r_end = min(_r_end, _r - 0.25)
                        break
            if _r_end <= 9.2:
                continue
            _x, _y = polar((9.0 + _r_end) / 2, _a)
            COLLIDERS.append(_box(f"Deck{_f}_{_k + 1}", _f, "deck", (_x, _y, _z - 0.3), (_r_end - 9.0 + 0.5, _w, 0.6),
                                  (0, 0, _a)))
        # deck skirt: closes the slots between the clipped deck boxes and the turret's curved wall (room side)
        for _k, _am in enumerate((210.0, 240.0, 300.0, 330.0)):
            _x, _y = polar(9.6, _am)
            COLLIDERS.append(_box(f"DeckSkirt{_f}_{_k + 1}", _f, "deck", (TURRET_C[0] + _x, TURRET_C[1] + _y, _z - 0.3),
                                  (2.4, 2 * 10.8 * math.tan(math.radians(15)), 0.6), (0, 0, _am)))
    # caps: a floor with a room on it wears an eave cap, the top floor the dome
    if not _top:
        (_ri, _zi), (_ro, _zo) = eave_profile(_f)
        COLLIDERS += _ring_facets(f"Eave{_f}", _f, "eave cap", _ri, _zi, _ro, _zo, 16)
    else:
        _pr = dome_profile(_f)
        COLLIDERS += _ring_facets("DomeA", _f, "dome", _pr[1][0], _pr[1][1], _pr[0][0], _pr[0][1], DOME_FACETS)
        COLLIDERS += _ring_facets("DomeB", _f, "dome", _pr[2][0], _pr[2][1], _pr[1][0], _pr[1][1], DOME_FACETS,
                                  inscribed_out=False)
        # crown disc: top at zc + 11.0, the visual dome runs 10.4 (its edge) .. 11.6 (the middle): +-0.6
        COLLIDERS.append(_cyl("DomeCrown", _f, "dome", (0, 0, _pr[2][1] - 0.3), 2 * _pr[2][0], 1.8))
        COLLIDERS.append({"name": "MascotBall", "floor": _f, "role": "mascot", "kind": "ball",
                          "pos": (0, 0, _pr[4][1] + 3.6), "size": (8.0, 8.0, 8.0), "rot": (0, 0, 0)})
        _tz = turret_top_z(_f)
        COLLIDERS.append(_cyl("TurretCapRim", _f, "turret cap", (TURRET_C[0], TURRET_C[1], _tz + 0.5), 2 * 9.2, 1.0))
        COLLIDERS.append(_cyl("TurretCapTop", _f, "turret cap", (TURRET_C[0], TURRET_C[1], _tz + 2.8), 2 * 6.0, 3.6))
    # owner hatch (floors 2-4): a door on the inside face of the room wall (the wall stays whole behind it; the drop is
    # a scripted ride), open only on the top floor; two DropShield parts outside the wall either side block the
    # prompt's line of sight from outside (CanQuery, never collide)
    if _f > 1:
        _hx, _hy, _hz = hatch_pos(_f)
        COLLIDERS.append(_box("DropHatch", _f, "contract: drop hatch (open only on the top floor)", (_hx, _hy, _z + 3.5),
                              (0.6, 4.0, 7.0)))
        for _s in (-1, 1):
            _sx, _sy = polar(room_out(_f) + 0.4, HATCH_A + _s * 7.0)
            COLLIDERS.append(_box(f"DropShield_{_s}", _f, "contract: blocks the prompt's line of sight from outside",
                                  (_sx, _sy, _z + 4.0), (0.4, 3.0, 7.0), (0, 0, HATCH_A + _s * 7.0), collide=False))
# floor 1: the lock (cork-style door barrier) and the open door's collider
COLLIDERS.append(_box("LockBarrier", 1, "lock", (0, DOOR["y"] - 0.2, floor_top(1) + DOOR["height"] / 2),
                      (DOOR["width"], 1.6, DOOR["height"]), note="solid for non-owners while locked; off when open"))
# the open round door: swung DOOR_SWING degrees out round its hinge at the doorway's left edge (a cylinder on its side
# in the game, like the jar's; drawn as a box of the disc's size here)
DOOR_SWING = 130.0
DOOR_DISC = 4.6
_hx = -DOOR_DISC
_dx, _dy = polar(DOOR_DISC, -DOOR_SWING)
OPEN_DOOR = {"x": _hx + _dx, "y": DOOR["y"] + _dy, "yaw": -DOOR_SWING}
COLLIDERS.append(_box("OpenDoorCollider", 1, "door", (OPEN_DOOR["x"], OPEN_DOOR["y"], floor_top(1) + DOOR_DISC + 0.4),
                      (2 * DOOR_DISC, 1.0, 2 * DOOR_DISC), (0, 0, OPEN_DOOR["yaw"]),
                      note="solid while open, off while locked", ignore_footprint=True))


# ---- headroom ----
def _ramp_surface_heights(x, y):
    """Walking heights of every ramp/landing at (x, y) if inside the turret's walk ring, else []."""
    dx, dy = x - TURRET_C[0], y - TURRET_C[1]
    r = math.hypot(dx, dy)
    if not (RAMP_IN - 0.01 <= r <= RAMP_OUT + 0.01):
        return []
    a = math.degrees(math.atan2(dy, dx)) % 360
    t = ((a - RAMP_A0) % 360) / RAMP_SWEEP
    hs = []
    if t <= 1.0:
        hs += [floor_top(f) + FLOOR_H * t for f in range(1, 4)]
    else:
        hs += [floor_top(f) for f in range(2, 5)]  # landings
    return hs


def CEILINGS(x, y, z, top=4):
    best = None
    for h in _ramp_surface_heights(x, y):
        under = h - RAMP_T
        if under > z + 0.05 and (best is None or under < best):
            best = under
    # turret cap
    if math.hypot(x - TURRET_C[0], y - TURRET_C[1]) < TURRET_IN:
        under = turret_top_z(top)
        if under > z + 0.05 and (best is None or under < best):
            best = under
    return best


# ---- deck outlines for the floor plans ----
DECK_POLYS = {f: [[polar(ROOM_R[f - 1], a) for a in range(0, 360, 10)]] for f in range(1, 5)}

# ---- meshes (visual-only MeshParts; colliders above do the colliding) ----
# variant: "mid" = a floor stands above, "top" = top floor, "all" = either. tint: one colour role, value-only vertex
# colours, MeshPart.Color themes it. slots = MeshParts on one plot at 4 floors. tris filled from _pagoda_pieces runs.
MESHES = [
    {"name": "pagoda_room_1", "floors": [1], "variant": "all", "tint": True, "slots": 1, "note": "stalk wall, round windows (dark recess)"},
    {"name": "pagoda_room_2", "floors": [2], "variant": "all", "tint": True, "slots": 1, "note": "+ closed hatch"},
    {"name": "pagoda_room_3", "floors": [3], "variant": "all", "tint": True, "slots": 1, "note": "+ closed hatch"},
    {"name": "pagoda_room_4", "floors": [4], "variant": "all", "tint": True, "slots": 1, "note": "+ closed hatch"},
    {"name": "pagoda_deck_2", "floors": [2], "variant": "all", "tint": True, "slots": 1, "note": "plank floor with the turret notch"},
    {"name": "pagoda_deck_3", "floors": [3], "variant": "all", "tint": True, "slots": 1, "note": ""},
    {"name": "pagoda_deck_4", "floors": [4], "variant": "all", "tint": True, "slots": 1, "note": ""},
    {"name": "pagoda_cap_1_mid", "floors": [1], "variant": "mid", "tint": True, "slots": 1, "note": "eave cone + gills"},
    {"name": "pagoda_cap_2_mid", "floors": [2], "variant": "mid", "tint": True, "slots": 1, "note": ""},
    {"name": "pagoda_cap_3_mid", "floors": [3], "variant": "mid", "tint": True, "slots": 1, "note": ""},
    {"name": "pagoda_dome", "floors": [1, 2, 3, 4], "variant": "top", "tint": True, "slots": 1, "note": "one mesh, scaled to the top floor's rim"},
    {"name": "pagoda_spots_mid", "floors": [1, 2, 3], "variant": "mid", "tint": True, "slots": 3, "note": "chunky white spots, own MeshPart so the cap can tint; built on cap 2, scaled per cap"},
    {"name": "pagoda_dome_spots", "floors": [1, 2, 3, 4], "variant": "top", "tint": True, "slots": 1, "note": "scaled with the dome"},
    {"name": "pagoda_turret_mid", "floors": [1, 2, 3], "variant": "mid", "tint": True, "slots": 3, "note": "one storey of turret wall + arch + post + landing"},
    {"name": "pagoda_turret_top", "floors": [1, 2, 3, 4], "variant": "top", "tint": True, "slots": 1, "note": "taller storey, no ramp"},
    {"name": "pagoda_ramp", "floors": [1, 2, 3], "variant": "mid", "tint": True, "slots": 3, "note": "one turn of spiral ramp"},
    {"name": "pagoda_turret_cap", "floors": [1, 2, 3, 4], "variant": "top", "tint": True, "slots": 1, "note": "spots as a lighter value"},
    {"name": "pagoda_door", "floors": [1], "variant": "all", "tint": True, "slots": 1, "note": "round plank door; jar door hinge + lock code"},
    {"name": "pagoda_door_ring", "floors": [1], "variant": "all", "tint": False, "slots": 1, "note": "doorway frame + hinge pins, same colours in every theme"},
    {"name": "pagoda_lamps", "floors": [1, 2, 3, 4], "variant": "all", "tint": True, "slots": 4, "note": "glow-shroom cluster"},
    {"name": "pagoda_vine_2", "floors": [2], "variant": "top", "tint": True, "slots": 0, "note": "curved glass tube from floor 2, solid half (only the top one shows)"},
    {"name": "pagoda_vine_3", "floors": [3], "variant": "top", "tint": True, "slots": 0, "note": ""},
    {"name": "pagoda_vine_4", "floors": [4], "variant": "top", "tint": True, "slots": 1, "note": ""},
    {"name": "pagoda_foot_decor", "floors": [1], "variant": "all", "tint": False, "slots": 1, "note": "mini mushrooms round the foot (classic); themes swap it"},
]
REUSED = ["goo_jar_foot (plot floor + moat)", "goo_cork_stand (pads)", "merge_vat", "lock button", "goo_jar_mascot + crown"]

NOTES = {
    "LockBarrier": "A box in the doorway (LockBarrier above). Locked: solid for everyone but the owner/guests; the "
                   "owner's client shows the round door half see-through (PlotDecor.OWNER_DOOR_TRANSPARENCY). Open: the "
                   "door swings out on its hinges like the jar door (DOOR_SWING) and OpenDoorCollider turns on.",
    "Drop exit": "Floors 2-4 each have a hatch on the room wall at 191 degrees; only the top floor's opens. DropPrompt on "
                 "a DropPromptAt attachment just inside the wall; two DropShield parts (CanQuery, no collide) outside "
                 "either side. A curved glass goo tube runs over the caps and down to a goo pool near 243 degrees "
                 "(the drop is a scripted move beside it); it never collides, so nobody can climb it from the moat.",
    "Owner check": "Round rooms: the jar's jarRadius(top) check works as ROOM_R[top] and y >= floorTop(top). Standing in "
                   "the turret does not count.",
    "HomeZone": "ReachUp up to the top floor's ceiling: floorTop(4) + CAP_UNDER - 1 = 59.2 studs.",
    "BuyPadPrompt": "On the next floor's lowest pad (pad 8f + 1), as on the jar: the next room shows with its pads locked.",
    "Floor_<f>": "Floor_f (f >= 2) holds: room wall f, deck f, cap f (eave or dome by variant), turret storey f, the "
                 "ramp from f - 1 (it ends on this floor's landing), landing f, lamps f, hatch f, pads 8f-7..8f. "
                 "When Floor_(f+1) is built, cap f swaps dome -> eave, turret f swaps top -> mid, and the dome, "
                 "turret cap, mascot and vine move up.",
    "Windows": "Visual only: dark recessed rounds in the wall mesh. The wall colliders are solid and CanQuery, so the "
               "lock button's prompt has no line of sight from outside through them.",
    "Ceilings": "No ceiling colliders: the cap underside is 11.2 studs up in every room, out of jump reach.",
}

# Measured through iterate.py (models/_pagoda_piece.py, --quick), 2026-10-26, after the look pass.
MESH_TRIS = {
    "pagoda_room_1": 1872, "pagoda_room_2": 1920, "pagoda_room_3": 1792, "pagoda_room_4": 1792,
    "pagoda_deck_2": 336, "pagoda_deck_3": 336, "pagoda_deck_4": 336,
    "pagoda_cap_1_mid": 1248, "pagoda_cap_2_mid": 1248, "pagoda_cap_3_mid": 1248, "pagoda_dome": 1648,
    "pagoda_spots_mid": 640, "pagoda_dome_spots": 1280,
    "pagoda_turret_mid": 1652, "pagoda_turret_top": 1652, "pagoda_ramp": 388, "pagoda_turret_cap": 420,
    "pagoda_door": 120, "pagoda_door_ring": 332, "pagoda_lamps": 324,
    "pagoda_vine_2": 296, "pagoda_vine_3": 296, "pagoda_vine_4": 296, "pagoda_foot_decor": 624,
}
for _m in MESHES:
    _m["tris"] = MESH_TRIS.get(_m["name"])

# Theme companions (_pagoda_pieces.THEME_PIECES): own colours, <= 3 per theme. kind: cap = one mesh scaled onto each
# eave cap; rim = a ring scaled onto each eave cap and the dome rim; dome = on the dome; climber = placed twice a floor;
# foot = replaces pagoda_foot_decor. slots = MeshParts on one plot at 4 floors.
THEME_MESHES = {
    "classic": [],
    "crystal": [("pagoda_snow_cap@crystal", "cap", 3, 1320), ("pagoda_snow_dome@crystal", "dome", 1, 896),
                ("pagoda_icicles@crystal", "rim", 4, 480)],
    "garden": [("pagoda_flower_pots@garden", "rim", 4, 1640), ("pagoda_climber@garden", "climber", 8, 340),
               ("pagoda_foot@garden", "foot", 0, 1300)],
    "starlight": [("pagoda_star_spots@starlight", "cap", 0, 360), ("pagoda_star_dome@starlight", "dome", 0, 560),
                  ("pagoda_star_garland@starlight", "rim", 4, 864)],
    "candy": [("pagoda_sprinkles_cap@candy", "cap", 3, 840), ("pagoda_sprinkles_dome@candy", "dome", 1, 1446),
              ("pagoda_foot@candy", "foot", 0, 884)],
    "mushroom": [("pagoda_moss@mushroom", "rim", 4, 676), ("pagoda_foot@mushroom", "foot", 0, 576)],
}
