# The round Exclusive bases' shared layout engine (pure data, no bpy): the Carousel Tent, Space Rocket, Tree House,
# Lighthouse and Snow Globe all stand on it. A base's own layout module (models/_<id>_layout.py) gives its numbers
# (ROOM_R, PAD_R, the roof profile) and runs build(); the result has every name _base_design_common.check,
# tools/export_base_shape.py and the plans read, in the same frame as models/_pagoda_layout.py:
# x right, y = plot-local z (y < 0 is the front, the door), z up; 1 unit = 1 stud; floor f walks at floor_top(f).
#
# The building (contract/base-shapes.md §44, the same for all five): each floor is a round room (wall WALL_H tall,
# from the floor to the deck above), its outer wall a frame of kerb, glass band and head band in the meshes so the
# pads always show from outside (the colliders stay where the glass is). In the middle a spiral ramp climbs one floor
# per turn round a post: RAMP_SWEEP degrees of slope and a LANDING-degree flat landing at the front (ARCH_A), where you
# step off onto the deck. Floor 1: the door on -y, the vat and the lock button either side inside, the spawn between.
# Upper floors: a deck ring from the ramp's edge out to the wider of this room and the one below (so a narrower room
# never leaves the floor below open to the sky). The top floor wears the roof (shown only while it is the top one,
# in the plot's TopColliders folder). Owner exit: a hatch on the room wall at HATCH_A on floors 2-4 (open only on the
# top floor), a scripted drop to the plot floor at EXIT_LANDS.
import math
import os

from models._base_design_common import FLOOR_H, PAD, floor_top, polar

FLOORS = int(os.environ.get("LAYOUT_FLOORS", "4"))  # floors standing; tools/export_base_shape.py varies it

WALL_T = 1.0
WALL_H = FLOOR_H - 0.6                 # floor to the underside of the deck above (the top floor: to the roof)
WALL_SEGS = 16                         # collider segments per full circle (22.5 degrees each)
DECK_T = 0.6
POST_R = 1.4
RAMP_IN, RAMP_OUT = 1.6, 8.0           # walking surface between the post and the open shaft edge
ARCH_A = 270.0                         # the landing faces the door: you arrive at the front of every floor
LANDING = 30.0
RAMP_SWEEP = 360.0 - LANDING           # 330
RAMP_A0 = ARCH_A + LANDING / 2         # 285: the ramp leaves the landing here, arrives at 255 a floor up
RAMP_T = 0.8
RAMP_BOXES = 12
HATCH_A = 180.0                        # owner hatch on the -x wall (between the pads at 157.5 and 202.5)
EXIT_A = 200.0                         # where the drop lands, on the plot floor outside
DOOR_W, DOOR_H = 8.0, 11.0
VAT = {"x": 8.5, "y": -20.5}
LOCK_BUTTON = {"x": -8.5, "y": -21.0}
SPAWN = (0.0, -12.5)
FLOOR1_PAD_ANGLES = tuple(-35.0 + k * 255.0 / 7 for k in range(8))   # the front (door, vat, lock, spawn) left free
UPPER_PAD_A0 = 22.5                    # upper floors: 8 pads all round, none in front of the landing


def _box(name, f, role, pos, size, rot=(0.0, 0.0, 0.0), **kw):
    d = {"name": name, "floor": f, "role": role, "kind": "box", "pos": tuple(round(v, 3) for v in pos),
         "size": tuple(round(v, 3) for v in size), "rot": tuple(round(v, 3) for v in rot)}
    d.update(kw)
    return d


def _cyl(name, f, role, pos, diameter, height, **kw):
    d = {"name": name, "floor": f, "role": role, "kind": "cyl", "pos": tuple(round(v, 3) for v in pos),
         "size": (round(diameter, 3), round(diameter, 3), round(height, 3)), "rot": (0, 0, 0)}
    d.update(kw)
    return d


def _circ_segments(r_face, thick, a_from, a_to, max_step):
    """Straight wall boxes circumscribing the circle r_face over an arc (never poke into the room)."""
    n = max(1, int(math.ceil((a_to - a_from) / max_step - 1e-9)))
    step = (a_to - a_from) / n
    rc = r_face + thick / 2
    out = []
    for i in range(n):
        a = a_from + step * (i + 0.5)
        half = rc * math.tan(math.radians(step / 2))
        mx, my = polar(rc, a)
        tx, ty = -math.sin(math.radians(a)), math.cos(math.radians(a))
        out.append(((mx - tx * half, my - ty * half), (mx + tx * half, my + ty * half), a, 2 * half))
    return out


def _ring_facets(name, f, role, r_in, z_in, r_out, z_out, n, thick=0.8, inscribed_out=True, **kw):
    """n planar facets on a cone from (r_in, z_in) to (r_out, z_out) (as models/_pagoda_layout._ring_facets)."""
    out = []
    step = 360.0 / n
    half = math.radians(step / 2)
    ro = r_out * math.cos(half) if inscribed_out else r_out
    run = ro - r_in
    rise = z_out - z_in
    slant = math.hypot(run, rise)
    tilt = math.degrees(math.atan2(-rise, run))
    width = 2 * r_out * math.sin(half)
    nr, nz = -rise / slant, run / slant
    for k in range(n):
        a = k * step + step / 2
        rm = (r_in + ro) / 2
        zm = (z_in + z_out) / 2
        cx, cy = polar(rm - nr * thick / 2, a)
        cz = zm - nz * thick / 2
        out.append(_box(f"{name}_{k + 1}", f, role, (cx, cy, cz), (width, slant, thick), (tilt, 0.0, a + 90), **kw))
    return out


def build(spec):
    """spec: ID, NAME, ROOM_R (inner wall radius per floor), PAD_R (pad ring radius per floor), ROOF(f, r_rim) ->
    [(r, z)] the roof's collider profile from its rim to the crown (absolute z), MASCOT_Z(f) (mascot ball bottom, or
    None), optional ROOF_FACETS (default 16), MESHES, NOTES, extra keys passed through."""
    ROOM_R = tuple(spec["ROOM_R"])
    PAD_R = tuple(spec["PAD_R"])
    floors = int(os.environ.get("LAYOUT_FLOORS", "4"))  # read per build: the exporter reloads only the base module
    g = dict(spec)
    g.update({k: v for k, v in globals().items() if k.isupper() and k not in g})
    g["FLOORS"] = floors

    def room_out(f):
        return ROOM_R[f - 1] + WALL_T

    def deck_r(f):
        """Floor f's deck reaches the wider of its own room and the room below it."""
        return max(ROOM_R[f - 1], ROOM_R[f - 2]) + WALL_T

    door_y = -(ROOM_R[0] + WALL_T / 2)
    door = {"x": 0.0, "y": door_y, "width": DOOR_W, "height": DOOR_H, "facing": -90}

    def pad_angle(j):
        f = (j - 1) // 8 + 1
        k = (j - 1) % 8
        if f == 1:
            return FLOOR1_PAD_ANGLES[k]
        return (UPPER_PAD_A0 + k * 45.0) % 360

    pads = []
    for j in range(1, 33):
        f = (j - 1) // 8 + 1
        x, y = polar(PAD_R[f - 1], pad_angle(j))
        pads.append({"j": j, "floor": f, "x": round(x, 3), "y": round(y, 3), "yaw": round(90 - pad_angle(j), 3)})

    def hatch_pos(f):
        x, y = polar(ROOM_R[f - 1] - 0.5, HATCH_A)
        return (round(x, 3), round(y, 3), floor_top(f) + 2.5)

    exit_ = {"floor": 4, "hatch": hatch_pos(4), "lands": polar(34.0, EXIT_A),
             "floor_check": "radius < ROOM_R[top] and y >= floorTop(top)"}
    inside = {"kind": "round", "radii": list(ROOM_R)}

    obstacles = [{"floor": 1, "x": VAT["x"], "y": VAT["y"], "r": 4.0, "label": "vat"},
                 {"floor": 1, "x": LOCK_BUTTON["x"], "y": LOCK_BUTTON["y"], "r": 1.6, "label": "lock"}]
    for f in range(1, 5):
        obstacles.append({"floor": f, "x": 0.0, "y": 0.0, "r": RAMP_OUT, "label": "ramp shaft"})

    door_half = math.degrees(math.asin(DOOR_W / 2 / (ROOM_R[0] + WALL_T / 2)))

    def room_arcs(f):
        if f == 1:
            return [(270 + door_half, 270 - door_half + 360)]
        return [(0.0, 360.0)]

    walls = []
    for f in range(1, 5):
        for a0, a1 in room_arcs(f):
            for p, q, a, L in _circ_segments(ROOM_R[f - 1], WALL_T, a0, a1, 360 / WALL_SEGS):
                walls.append({"floor": f, "a": p, "b": q, "thick": WALL_T, "h": WALL_H, "role": "room"})

    ramps, landings = [], []
    for f in range(1, 4):
        ramps.append({"name": f"centre ramp {f}->{f + 1}", "floor": f, "kind": "helix", "c": (0.0, 0.0),
                      "r_in": RAMP_IN, "r_out": RAMP_OUT, "a0": RAMP_A0, "sweep": RAMP_SWEEP, "z0": floor_top(f),
                      "rise": FLOOR_H})
    for f in range(2, 5):
        x, y = polar(RAMP_IN + (RAMP_OUT - RAMP_IN) / 2, ARCH_A)
        landings.append({"name": f"landing {f}", "floor": f, "x": x, "y": y, "z": floor_top(f),
                         "sx": 2 * RAMP_OUT * math.sin(math.radians(LANDING / 2)) + 0.6, "sy": RAMP_OUT - RAMP_IN})

    roof_facets = spec.get("ROOF_FACETS", 16)
    colliders = []
    for f in range(1, floors + 1):
        z = floor_top(f)
        top = f == floors
        for i, w in enumerate([w for w in walls if w["floor"] == f]):
            (ax, ay), (bx, by) = w["a"], w["b"]
            L = math.hypot(bx - ax, by - ay)
            yaw = math.degrees(math.atan2(by - ay, bx - ax))
            colliders.append(_box(f"Wall{f}_{i + 1}", f, "room wall", ((ax + bx) / 2, (ay + by) / 2, z + WALL_H / 2),
                                  (L, WALL_T, WALL_H), (0, 0, yaw)))
        # the post runs the whole storey; the ramp up from this floor is built with the floor above
        colliders.append(_cyl(f"Post{f}", f, "post", (0, 0, z + FLOOR_H / 2), 2 * POST_R, FLOOR_H))
        if not top:
            step = RAMP_SWEEP / RAMP_BOXES
            rm = (RAMP_IN + RAMP_OUT) / 2
            slope = math.degrees(math.atan2(FLOOR_H, math.radians(RAMP_SWEEP) * rm))
            for k in range(RAMP_BOXES):
                am = RAMP_A0 + step * (k + 0.5)
                zm = z + FLOOR_H * (k + 0.5) / RAMP_BOXES
                x, y = polar(rm, am)
                ln = 2 * RAMP_OUT * math.sin(math.radians(step / 2)) + 0.4
                colliders.append(_box(f"Ramp{f + 1}_{k + 1}", f + 1, "ramp", (x, y, zm - RAMP_T / 2),
                                      (ln, RAMP_OUT - RAMP_IN, RAMP_T), (0, -slope, am + 90)))
        if f > 1:
            lg = [l for l in landings if l["floor"] == f][0]
            colliders.append(_box(f"Landing{f}", f, "landing", (lg["x"], lg["y"], z - DECK_T / 2),
                                  (lg["sy"], lg["sx"], DECK_T)))
            R = deck_r(f)
            for k in range(16):
                a = k * 22.5 + 11.25
                w = 2 * R * math.tan(math.radians(11.25))
                x, y = polar((RAMP_OUT + R) / 2, a)
                colliders.append(_box(f"Deck{f}_{k + 1}", f, "deck", (x, y, z - DECK_T / 2),
                                      (R - RAMP_OUT + 0.3, w, DECK_T), (0, 0, a)))
            # the owner hatch: on the wall's inside face (the wall stays whole behind it, the drop is a scripted
            # ride), open only on the top floor; two DropShield parts outside block the prompt's line of sight
            hx, hy, _ = hatch_pos(f)
            colliders.append(_box("DropHatch", f, "contract: drop hatch (open only on the top floor)",
                                  (hx, hy, z + 3.5), (0.6, 4.0, 7.0)))
            for s in (-1, 1):
                sx, sy = polar(room_out(f) + 0.4, HATCH_A + s * 7.0)
                colliders.append(_box(f"DropShield_{s}", f, "contract: blocks the prompt's line of sight from outside",
                                      (sx, sy, z + 4.0), (0.4, 3.0, 7.0), (0, 0, HATCH_A + s * 7.0), collide=False))
        if top:
            prof = spec["ROOF"](f, room_out(f))
            for k in range(len(prof) - 1):
                (r0, z0), (r1, z1) = prof[k], prof[k + 1]
                if r1 < 0.5:
                    break
                colliders += _ring_facets(f"Roof{chr(65 + k)}", f, "roof", r1, z1, r0, z0, roof_facets,
                                          inscribed_out=(k == 0))
            r_last, z_last = [p for p in prof if p[0] >= 0.5][-1]
            colliders.append(_cyl("RoofCrown", f, "roof", (0, 0, z_last - 0.6), 2 * r_last, 1.2))
            for c in spec.get("ROOF_EXTRA", lambda f: [])(f):
                colliders.append(c)
            mz = spec.get("MASCOT_Z", lambda f: None)(f)
            if mz is not None:
                colliders.append({"name": "MascotBall", "floor": f, "role": "mascot", "kind": "ball",
                                  "pos": (0, 0, mz + 3.6), "size": (8.0, 8.0, 8.0), "rot": (0, 0, 0)})
    colliders.append(_box("LockBarrier", 1, "lock", (0, door_y - 0.2, floor_top(1) + DOOR_H / 2), (DOOR_W, 1.6, DOOR_H),
                          note="solid for non-owners while locked; off when open"))

    def ramp_surface_heights(x, y):
        r = math.hypot(x, y)
        if not (RAMP_IN - 0.01 <= r <= RAMP_OUT + 0.01):
            return []
        a = math.degrees(math.atan2(y, x)) % 360
        t = ((a - RAMP_A0) % 360) / RAMP_SWEEP
        if t <= 1.0:
            return [floor_top(f) + FLOOR_H * t for f in range(1, 4)]
        return [floor_top(f) for f in range(2, 5)]

    def ceilings(x, y, z, top=4):
        best = None
        for h in ramp_surface_heights(x, y):
            under = h - RAMP_T
            if under > z + 0.05 and (best is None or under < best):
                best = under
        return best

    g.update({
        "FLOORS": floors, "ROOM_R": ROOM_R, "PAD_R": PAD_R, "room_out": room_out, "deck_r": deck_r,
        "DOOR": door, "PADS": pads, "pad_angle": pad_angle, "hatch_pos": hatch_pos, "EXIT": exit_,
        "INSIDE": inside, "OBSTACLES": obstacles, "WALLS": walls, "RAMPS": ramps, "LANDINGS": landings,
        "COLLIDERS": colliders, "CEILINGS": ceilings,
        "BRIDGE": {"width": 10.0, "from": -(ROOM_R[0] + WALL_T), "to": -38.5},
        "DECK_POLYS": {f: [[polar(ROOM_R[f - 1], a) for a in range(0, 360, 10)]] for f in range(1, 5)},
        "MESHES": spec.get("MESHES", []), "NOTES": spec.get("NOTES", {}),
    })
    return g
