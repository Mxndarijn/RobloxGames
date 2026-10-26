# The Goo Factory base: detailed design layout (pure data, no bpy). One file drives the scene, the collider overlay,
# the floor plans and the checks (models/_base_design_common.py has the schema and the rules).
#
# Kit coords = plot-local: x right, y = plot z (y < 0 is the front, the door side), z up. Floor f walks at
# floor_top(f) = 1 + 16 (f - 1). This file describes the full 4-floor factory; the game builds floor 1 statically and
# floors 2-4 as Floor_<f> Models while pads are unlocked (CONTRACT §5.3), with the "top" pieces on the current top floor.
#
# The building: a square brick factory, 48 x 48 outside (walls 1 thick, inner faces at +-23), one storey per floor.
# The climb is a switchback core along the back wall, closed off from the factory floor by a full-height core wall:
#   run A (front lane, y 15.7) from x -12 up to x 6, rising 8 -> mid landing x 6..11 (both lanes) -> run B (back lane,
#   y 20.5) from x 6 back to x -12, rising the other 8, arriving on the next floor's deck strip (x < -12), from which
#   the next run A starts straight ahead (+x). Both lanes are 4.5 wide; runs slope atan(8 / 18) = 24 degrees.
# Floor 1 front: a 10 x 11 doorway with a roll-up shutter (the LockBarrier), the merge vat inside left and the lock
# button inside right; spawn at (0, -12.5). 8 pads per floor in two rows of 4. Owner exit: a hatch in the east wall of
# the top floor onto the goo chute, a zig-zag half-pipe down the outside to a splash pool (scripted ride, no collision).
import math

from models._base_design_common import floor_top, FLOOR_H

ID = "factory"
NAME = "Goo Factory"
FLOORS = 4

HALF = 24.0           # outer half-width of the factory
WALL = 1.0            # outer wall thickness
IN = HALF - WALL      # inner wall face (23)
WC = HALF - WALL / 2  # outer wall centre line (23.5)
SLAB = 0.6            # upper-floor slab thickness (under the walking surface)
RAMP_T = 0.8          # ramp board thickness

# Switchback core
XS, XE, XL = -12.0, 6.0, 11.0          # run start x, run end x (landing starts), landing end x
LANE_A, LANE_B, LANE_W = 15.7, 20.5, 4.5
CORE_FRONT_Y, CORE_FRONT_T = 13.2, 0.4  # core wall between the factory floor and the ramps
SPINE_Y, SPINE_T = 18.1, 0.3           # wall between the two lanes
END_X, END_T = 11.2, 0.4               # core end wall past the landing
HALF_RISE = FLOOR_H / 2

# Floor-1 front
DOOR = {"x": 0.0, "y": -WC, "width": 10.0, "height": 11.0, "facing": "-y"}
VAT = {"x": -14.0, "y": -17.5}
LOCK_BUTTON = {"x": 13.0, "y": -18.5}
SPAWN = (0.0, -12.5)
SHUTTER_DRUM_Z = 13.0   # the open shutter rolls up into a drum above the doorway (no open-door collider)

# Pads: two rows of 4, front row first, left to right. Pad j on floor ceil(j / 8).
PAD_X = (-14.1, -4.7, 4.7, 14.1)
PAD_ROWS = (-4.4, 5.0)
PADS = []
for f in range(1, 5):
    for r, y in enumerate(PAD_ROWS):
        for k, x in enumerate(PAD_X):
            PADS.append({"j": (f - 1) * 8 + r * 4 + k + 1, "floor": f, "x": x, "y": y, "yaw": 0.0})

# Goo belts (decor that collides): along the front wall on floors 2-4, 36 long, 3 wide, 1.2 tall.
BELT = {"y": -20.5, "x0": -18.0, "x1": 18.0, "w": 3.0, "h": 1.2}

# Owner exit
HATCH_Y = -14.0
EXIT = {"floor": FLOORS, "hatch": (WC, HATCH_Y, floor_top(FLOORS) + 3.0), "lands": (28.0, 18.0),
        "floor_check": "owner inside the top floor's box: |x|, |y| < 23 and floor_top(top) <= y_root < floor_top(top) + 16"}
CHUTE_X = HALF + 2.0    # the chute's centre line, outside the east wall

# ---- walls (centre lines) per floor ----
WALLS = []
for f in range(1, 5):
    h = FLOOR_H
    if f == 1:
        dw = DOOR["width"] / 2
        WALLS += [{"floor": f, "a": (-WC, -WC), "b": (-dw, -WC), "thick": WALL, "h": h},
                  {"floor": f, "a": (dw, -WC), "b": (WC, -WC), "thick": WALL, "h": h}]
    else:
        WALLS.append({"floor": f, "a": (-WC, -WC), "b": (WC, -WC), "thick": WALL, "h": h})
    WALLS += [{"floor": f, "a": (-WC, WC), "b": (WC, WC), "thick": WALL, "h": h},
              {"floor": f, "a": (-WC, -WC), "b": (-WC, WC), "thick": WALL, "h": h},
              {"floor": f, "a": (WC, -WC), "b": (WC, WC), "thick": WALL, "h": h},
              {"floor": f, "a": (XS, CORE_FRONT_Y), "b": (END_X + END_T / 2, CORE_FRONT_Y), "thick": CORE_FRONT_T, "h": h},
              {"floor": f, "a": (XS, SPINE_Y), "b": (XE, SPINE_Y), "thick": SPINE_T, "h": h},
              {"floor": f, "a": (END_X, CORE_FRONT_Y), "b": (END_X, IN), "thick": END_T, "h": h}]

# ---- obstacles pads must keep clear of ----
OBSTACLES = [{"floor": 1, "x": VAT["x"], "y": VAT["y"], "r": 4.0, "label": "vat"},
             {"floor": 1, "x": LOCK_BUTTON["x"], "y": LOCK_BUTTON["y"], "r": 1.6, "label": "lock"}]
for f in range(2, 5):
    n = 13
    for k in range(n):
        x = BELT["x0"] + (BELT["x1"] - BELT["x0"]) * k / (n - 1)
        OBSTACLES.append({"floor": f, "x": x, "y": BELT["y"], "r": BELT["w"] / 2, "label": "belt"})

# ---- ramps and landings (stair f climbs from floor f to f + 1) ----
RAMPS, LANDINGS = [], []
for f in range(1, FLOORS):
    z = floor_top(f)
    RAMPS.append({"name": f"RunA_{f}", "floor": f, "kind": "line", "a": (XS, LANE_A, z), "b": (XE, LANE_A, z + HALF_RISE),
                  "width": LANE_W})
    LANDINGS.append({"name": f"Landing_{f}", "floor": f, "x": (XE + XL) / 2, "y": (LANE_A + LANE_B) / 2,
                     "z": z + HALF_RISE, "sx": XL - XE, "sy": (LANE_B + LANE_W / 2) - (LANE_A - LANE_W / 2)})
    RAMPS.append({"name": f"RunB_{f}", "floor": f, "kind": "line", "a": (XE, LANE_B, z + HALF_RISE),
                  "b": (XS, LANE_B, z + FLOOR_H), "width": LANE_W})


def _in_hole(x, y):
    return XS <= x <= XL and CORE_FRONT_Y + CORE_FRONT_T / 2 <= y <= IN


def _lane(y):
    if abs(y - LANE_A) <= LANE_W / 2:
        return "A"
    if abs(y - LANE_B) <= LANE_W / 2:
        return "B"
    return None


def _ramp_z(f, x, y):
    """Walking height of stair f's ramp or landing at (x, y), or None."""
    z = floor_top(f)
    if XE <= x <= XL and _lane(y):
        return z + HALF_RISE
    t = (x - XS) / (XE - XS)
    if 0 <= t <= 1:
        if _lane(y) == "A":
            return z + HALF_RISE * t
        if _lane(y) == "B":
            return z + FLOOR_H - HALF_RISE * t
    return None


def CEILINGS(x, y, z):
    """Lowest solid underside above height z at (x, y): slabs, ramps/landings of the stairs above, the top cover,
    the roof."""
    cands = [floor_top(FLOORS) + FLOOR_H]  # roof underside
    for g in range(2, FLOORS + 1):
        if not _in_hole(x, y):
            cands.append(floor_top(g) - SLAB)
    for g in range(1, FLOORS):
        rz = _ramp_z(g, x, y)
        if rz is not None:
            cands.append(rz - RAMP_T)
    # the top floor's cover over lane A and the landing (no stair goes up from the top floor)
    if _in_hole(x, y) and (_lane(y) == "A" or x >= XE):
        cands.append(floor_top(FLOORS) - SLAB)
    above = [c for c in cands if c > z + 0.05]
    return min(above) if above else None


# ---- colliders (the placeholder list; meshes are visual-only) ----
COLLIDERS = []


def C(name, floor, role, kind, pos, size, rot=(0, 0, 0), **kw):
    d = {"name": name, "floor": floor, "role": role, "kind": kind, "pos": pos, "size": size, "rot": rot}
    d.update(kw)
    COLLIDERS.append(d)


def _ramp_box(name, floor, a, b, w):
    (x0, y0, z0), (x1, y1, z1) = a, b
    run = math.hypot(x1 - x0, y1 - y0)
    L = math.hypot(run, z1 - z0)
    slope = math.degrees(math.atan2(z1 - z0, run))
    sign = -1 if x1 > x0 else 1
    C(name, floor, "ramp", "box", ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2 - RAMP_T / 2), (L, w, RAMP_T),
      (0, sign * slope, 0))


# Floor 1 contract parts (they exist for every base; the ones off the footprint are ignored by that check)
C("Base", 1, "contract: plot anchor, never collides", "box", (0, 0, 0.5), (80, 80, 1), collide=False, ignore_footprint=True)
C("PlotFloor", 1, "contract: plot floor disc", "cyl", (0, 0, 0.5), (80, 80, 1), ignore_footprint=True)
C("HomeZone", 1, "contract: deposit zone, ReachUp covers floors 2-4", "box", (0, 0, 1 + 8), (46, 46, 16), collide=False)
C("Bridge", 1, "contract: plank bridge over the moat", "box", (0, -(HALF + 7.5), 1.0), (10, 15, 0.6), ignore_footprint=True)
C("LockSign", 1, "contract: lock status board + name board post", "box", (8.5, -36.5, 6), (0.8, 0.8, 12), ignore_footprint=True)
C("MergeVat", 1, "contract: merge vat", "cyl", (VAT["x"], VAT["y"], 1 + 2.5), (8, 8, 5))
C("LockButton", 1, "contract: lock button", "cyl", (LOCK_BUTTON["x"], LOCK_BUTTON["y"], 1 + 1.6), (3.2, 3.2, 3.2))
C("LockBarrier", 1, "contract: the shutter, solid while locked (owner and guests pass)", "box",
  (DOOR["x"], DOOR["y"], 1 + DOOR["height"] / 2), (DOOR["width"], 1.0, DOOR["height"]))
C("Sign", 1, "contract: name sign over the door", "box", (0, -(HALF + 0.4), 1 + 13.5), (20, 0.8, 4), collide=False)
SILOS = ((-29.0, -5.5), (-29.0, 5.5))  # west yard, radius 3.8, 22 tall; 1.2 from the wall (too narrow to step into)
SILO_R, SILO_H = 3.8, 22.0
for k, (x, y) in enumerate(SILOS):
    C(f"Silo_{k}", 1, "yard silo", "cyl", (x, y, 1 + SILO_H / 2), (2 * SILO_R, 2 * SILO_R, SILO_H))

for f in range(1, FLOORS + 1):
    z = floor_top(f)
    top = f == FLOORS
    zc = z + FLOOR_H / 2
    # outer walls
    if f == 1:
        side = (HALF - DOOR["width"] / 2)
        for s in (-1, 1):
            C(f"WallFront_{s}", f, "wall", "box", (s * (DOOR["width"] / 2 + side / 2), -WC, zc), (side, WALL, FLOOR_H))
        C("WallFrontLintel", f, "wall", "box", (0, -WC, z + DOOR["height"] + (FLOOR_H - DOOR["height"]) / 2),
          (DOOR["width"], WALL, FLOOR_H - DOOR["height"]))
    else:
        C(f"WallFront", f, "wall", "box", (0, -WC, zc), (2 * HALF, WALL, FLOOR_H))
    C("WallBack", f, "wall", "box", (0, WC, zc), (2 * HALF, WALL, FLOOR_H))
    C("WallWest", f, "wall", "box", (-WC, 0, zc), (WALL, 2 * IN, FLOOR_H))
    if f > 1:
        # east wall split round the drop hatch (hatch 4 wide, 7 tall, sill 1 above the floor)
        hy0, hy1 = HATCH_Y - 2, HATCH_Y + 2
        C("WallEast_S", f, "wall", "box", (WC, (-IN + hy0) / 2, zc), (WALL, hy0 + IN, FLOOR_H))
        C("WallEast_N", f, "wall", "box", (WC, (hy1 + IN) / 2, zc), (WALL, IN - hy1, FLOOR_H))
        C("WallEast_Over", f, "wall", "box", (WC, HATCH_Y, z + 8 + (FLOOR_H - 8) / 2), (WALL, 4, FLOOR_H - 8))
        C("WallEast_Sill", f, "wall", "box", (WC, HATCH_Y, z + 0.5), (WALL, 4, 1))
        C("DropHatch", f, "contract: drop hatch (open only on the top floor)", "box", (WC, HATCH_Y, z + 4.5), (0.6, 4, 7))
        for s in (-1, 1):
            C(f"DropShield_{s}", f, "contract: blocks the prompt's line of sight from outside", "box",
              (HALF + 0.3, HATCH_Y + s * 3.5, z + 4), (0.4, 3, 7), collide=False)
    else:
        C("WallEast", f, "wall", "box", (WC, 0, zc), (WALL, 2 * IN, FLOOR_H))
    # floor slab (floor 1 stands on the plot floor; upper floors: 3 slab pieces round the core hole)
    if f == 1:
        C("Slab", f, "floor", "box", (0, 0, z - 0.15), (2 * IN, 2 * IN, 0.3))
    else:
        yb = CORE_FRONT_Y + CORE_FRONT_T / 2
        C("Slab_Main", f, "floor", "box", (0, (-IN + yb) / 2, z - SLAB / 2), (2 * IN, yb + IN, SLAB))
        C("Slab_West", f, "floor", "box", ((-IN + XS) / 2, (yb + IN) / 2, z - SLAB / 2), (XS + IN, IN - yb, SLAB))
        C("Slab_East", f, "floor", "box", ((END_X + END_T / 2 + IN) / 2, (yb + IN) / 2, z - SLAB / 2),
          (IN - END_X - END_T / 2, IN - yb, SLAB))
    # core walls (every floor)
    C("CoreFront", f, "core wall", "box", ((XS + END_X + END_T / 2) / 2, CORE_FRONT_Y, zc),
      (END_X + END_T / 2 - XS, CORE_FRONT_T, FLOOR_H))
    C("CoreSpine", f, "core wall", "box", ((XS + XE) / 2, SPINE_Y, zc), (XE - XS, SPINE_T, FLOOR_H))
    C("CoreEnd", f, "core wall", "box", (END_X, (CORE_FRONT_Y + IN) / 2, zc), (END_T, IN - CORE_FRONT_Y, FLOOR_H))
    if not top:
        # stair f climbs to floor f + 1 and belongs to Floor_<f+1> (built with the floor it reaches, like the jar)
        _ramp_box("RunA", f + 1, (XS, LANE_A, z), (XE, LANE_A, z + HALF_RISE), LANE_W)
        lg = [g for g in LANDINGS if g["floor"] == f][0]
        C("Landing", f + 1, "ramp", "box", (lg["x"], lg["y"], lg["z"] - RAMP_T / 2), (lg["sx"], lg["sy"], RAMP_T))
        _ramp_box("RunB", f + 1, (XE, LANE_B, z + HALF_RISE), (XS, LANE_B, z + FLOOR_H), LANE_W)
    else:
        # top: cover lane A and the landing so the hole only opens where the stair arrives
        C("CoreCapA", f, "floor", "box", ((XS + XL) / 2, LANE_A, z - SLAB / 2), (XL - XS, LANE_W, SLAB))
        C("CoreCapLanding", f, "floor", "box", ((XE + XL) / 2, LANE_B, z - SLAB / 2), (XL - XE, LANE_W, SLAB))
        C("Roof", f, "roof", "box", (0, 0, z + FLOOR_H + 0.4), (2 * HALF, 2 * HALF, 0.8))
    if f > 1:
        C("Belt", f, "goo belt (collides: 1.2 tall)", "box", ((BELT["x0"] + BELT["x1"]) / 2, BELT["y"], z + BELT["h"] / 2),
          (BELT["x1"] - BELT["x0"], BELT["w"], BELT["h"]))

# ---- deck outlines for the plans ----
DECK_POLYS = {1: [[(-IN, -IN), (IN, -IN), (IN, IN), (-IN, IN)]]}
for f in range(2, 5):
    yb = CORE_FRONT_Y + CORE_FRONT_T / 2
    DECK_POLYS[f] = [[(-IN, -IN), (IN, -IN), (IN, yb), (-IN, yb)],
                     [(-IN, yb), (XS, yb), (XS, IN), (-IN, IN)],
                     [(END_X + END_T / 2, yb), (IN, yb), (IN, IN), (END_X + END_T / 2, IN)]]
# the top floor's cover plates over lane A and the landing
DECK_POLYS[FLOORS] += [[(XS, LANE_A - LANE_W / 2), (XL, LANE_A - LANE_W / 2), (XL, LANE_A + LANE_W / 2), (XS, LANE_A + LANE_W / 2)],
                       [(XE, LANE_B - LANE_W / 2), (XL, LANE_B - LANE_W / 2), (XL, LANE_B + LANE_W / 2), (XE, LANE_B + LANE_W / 2)]]

# ---- mesh pieces (visual-only MeshParts). slots = how many stand at 4 floors. tris filled in from measurement. ----
MESHES = [
    # themed: one mesh per theme (classic has no dress); tris = the largest theme
    {"name": "factory_foot", "floors": [1], "variant": "all", "tint": False, "themed": True, "slots": 1,
     "note": "round grass plot, goo moat, concrete yard, bridge + the theme's door-zone, yard and floor-1 storey touches"},
    {"name": "factory_roof_kit", "floors": [1, 2, 3, 4], "variant": "top", "tint": False, "themed": True, "slots": 1,
     "note": "goo tank (mascot seat), 2 brick chimneys, goo puffs + the theme's roof touches"},
    {"name": "factory_dress", "floors": [2, 3, 4], "variant": "all", "tint": False, "themed": True, "slots": 3,
     "note": "the theme's storey touches on floors 2-4 (icicles, window boxes, vines, stripes, gold trim); none in classic"},
    # tint-only (MeshPart.Color = the theme's role colour)
    {"name": "factory_storey_1", "floors": [1], "variant": "all", "tint": True, "slots": 1,
     "note": "ground storey brick shell: doorway, window openings, mortar courses, plinth, pilasters (tint: walls)"},
    {"name": "factory_storey", "floors": [2, 3, 4], "variant": "all", "tint": True, "slots": 3,
     "note": "upper storey brick shell with the hatch opening (tint: walls)"},
    {"name": "factory_trim_1", "floors": [1], "variant": "all", "tint": True, "slots": 1,
     "note": "cream band, sills, lintels, pilaster caps (tint: cream)"},
    {"name": "factory_trim", "floors": [2, 3, 4], "variant": "all", "tint": True, "slots": 3, "note": "as above, upper"},
    {"name": "factory_windows_1", "floors": [1], "variant": "all", "tint": True, "slots": 1,
     "note": "long industrial window strips with mullions (tint: glass)"},
    {"name": "factory_windows", "floors": [2, 3, 4], "variant": "all", "tint": True, "slots": 3, "note": "as above, upper"},
    {"name": "factory_pipes_1", "floors": [1], "variant": "all", "tint": True, "slots": 1,
     "note": "2 goo pipes up the facade with clamps and feet (tint: goo)"},
    {"name": "factory_pipes", "floors": [2, 3, 4], "variant": "all", "tint": True, "slots": 3, "note": "as above, upper"},
    {"name": "factory_parapet", "floors": [1, 2, 3, 4], "variant": "top", "tint": True, "slots": 1,
     "note": "parapet + coping on the top storey (tint: cream)"},
    {"name": "factory_floor_1", "floors": [1], "variant": "all", "tint": True, "slots": 1,
     "note": "floor 1's factory floor inside the walls (tint: path)"},
    {"name": "factory_slab", "floors": [2, 3, 4], "variant": "all", "tint": True, "slots": 3,
     "note": "deck round the core hole, value hazard stripes (tint: path)"},
    {"name": "factory_stair", "floors": [2, 3, 4], "variant": "all", "tint": True, "slots": 3,
     "note": "run A + landing + run B with tread ribs; Floor_<f> carries the stair up from f - 1 (tint: goo)"},
    {"name": "factory_core", "floors": [1, 2, 3, 4], "variant": "all", "tint": True, "slots": 4,
     "note": "core walls: front wall with portholes, spine, end wall (tint: wood_d)"},
    {"name": "factory_core_cap", "floors": [2, 3, 4], "variant": "top", "tint": True, "slots": 1,
     "note": "top floor's cover over lane A and the landing (tint: path)"},
    {"name": "factory_roof", "floors": [1, 2, 3, 4], "variant": "top", "tint": True, "slots": 1,
     "note": "roof slab with sawtooth skylights (tint: metal)"},
    {"name": "factory_hatch", "floors": [2, 3, 4], "variant": "all", "tint": True, "slots": 3,
     "note": "drop hatch door in the east wall (tint: metal)"},
    {"name": "factory_chute_2", "floors": [2], "variant": "top", "tint": True, "slots": 0, "note": "goo chute from floor 2 (tint: goo)"},
    {"name": "factory_chute_3", "floors": [3], "variant": "top", "tint": True, "slots": 0, "note": "goo chute from floor 3 (tint: goo)"},
    {"name": "factory_chute_4", "floors": [4], "variant": "top", "tint": True, "slots": 1, "note": "goo chute from floor 4 (tint: goo)"},
    {"name": "factory_silo", "floors": [1], "variant": "all", "tint": True, "slots": 2, "note": "yard silo x2 (tint: metal)"},
    # fixed colours in every theme
    {"name": "factory_sign", "floors": [1], "variant": "all", "tint": False, "slots": 1,
     "note": "GOO CO sign board on arms over the door, coloured dots (the plot name goes on a SurfaceGui)"},
    {"name": "factory_door_frame", "floors": [1], "variant": "all", "tint": False, "slots": 1,
     "note": "big yellow/black hazard posts and header + the shutter drum (lock signal)"},
    {"name": "factory_shutter", "floors": [1], "variant": "all", "tint": False, "slots": 1,
     "note": "the roll-up shutter (LockBarrier's look)"},
    {"name": "factory_belt", "floors": [2, 3, 4], "variant": "all", "tint": False, "slots": 3,
     "note": "goo conveyor belt with rollers (dark rubber + steel)"},
]
TRIS = {}  # filled from models/_factory_tris.json when present (themed pieces: the largest theme)
try:
    import json
    import os
    _p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_factory_tris.json")
    if os.path.exists(_p):
        TRIS = json.load(open(_p))
except Exception:
    TRIS = {}
for m in MESHES:
    m["tris"] = TRIS.get(m["name"])

NOTES = {
    "LockBarrier": "The shutter box in the doorway (10 x 1 x 11). Locked: rolled down and solid for everyone except the "
                   "owner and guests; the owner's and guests' clients draw it half see-through (PlotDecor."
                   "OWNER_DOOR_TRANSPARENCY). Open: rolled up into the drum above the doorway, so no OpenDoorCollider.",
    "DropPrompt": "Hatch in the east wall of every upper floor at y -14; only the top floor's opens. DropPromptAt "
                  "attachment 1.5 studs inside the wall, line of sight on; two DropShield parts just outside the wall "
                  "either side of the hatch. The goo chute is a scripted ride (CanCollide off) down to the splash pool.",
    "Owner check": "Today: plot-local radius < jarRadius(top). A square floor needs a box test (|x|, |y| < 23 and the "
                   "height band of the top floor): code change in the drop handler.",
    "HomeZone": "Floor 1 box 46 x 46 inside the walls, ReachUp = 3 x 16 so a carrier on any floor deposits.",
    "BuyPadPrompt": "On the next floor's lowest pad (pad 8(f-1)+1, front row west), as today.",
    "Floor_<f>": "Storey walls (front, back, west, east split round the hatch, hatch, shields), 3 slab pieces, core "
                 "walls, the stair up from floor f - 1 (run A, landing, run B), the belt; on the top floor also the "
                 "core cap and the roof. See COLLIDERS by floor.",
    "Lock button sight": "The lock button stands at (13, -18.5), 4.5 studs behind the front wall, below the window "
                         "strip (windows start 8 studs up on floor 1, front windows only either side of the sign). "
                         "Its prompt needs line of sight on and a 6-stud MaxActivationDistance so nobody outside can "
                         "reach it through glass.",
    "Collision": "Everything is a box or cylinder. Visual-only: sawtooth roof, chimneys, tank, mascot, facade pipes, "
                 "sign, chute and splash pool (none can be reached: the roof is closed, the chute is a scripted ride).",
}
