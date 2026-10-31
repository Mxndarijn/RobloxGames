# Habitat THEME helpers (not an asset). A theme mesh is the middle layer of a habitat (frame + theme + signature
# prop): props on the BACK and SIDES of the dish rim, no ring (the frame mesh supplies it), the front arc clear for
# the species' signature prop. Authored like the old overlays (square layout, round_up maps it onto the dish).
#
# Authored straight in ROUND dish coordinates: pol(r, deg) = the point at radius r, angle deg (90 = back +Y, 0 = right
# +X, 180 = left, -90 = front). theme_finish does NOT run round_up: its clamp shrinks any tall group wider than 1.3
# studs (x, y AND z), which made long props along the band (a barn door, a log, a bale stack) tiny. Instead the THEME
# check enforces the band itself: every vertex above z 0.3 must lie between radius 2.6 and 3.9 (out_band=0) and none
# in the front arc (front_hi=0).
#
# theme_finish() = overlay_finish() without round_up, plus a THEME check (front arc, band, heights). Like
# overlay_finish it writes out/<name>.deck.json (the bbox centre on the deck) on export: the front arc is empty, so
# the bbox is off centre and the game uses that offset to put the mesh back on the dish centre. With HABITAT_PREVIEW=1 it also draws a neutral stand-in frame ring (THEME_FRAME=0 turns it off).
import math, os
from lib import *
from models._habitat_overlay import *
from models._habitat_overlay import on_deck as _flatten
from models._phoenix_pad import lathe

FRONT_ARC = 45.0  # degrees either side of -Y kept below FRONT_Z
FRONT_Z = 0.3
R_IN, R_OUT = INNER / 2, 3.9


def pol(r, deg):
    """Dish point at radius r, angle deg (round coordinates)."""
    a = math.radians(deg)
    return r * math.cos(a), r * math.sin(a)


def ang_from_front(x, y):
    return abs(math.degrees(math.atan2(x, -y)))


def theme_check(parts):
    import bpy
    bpy.context.view_layer.update()
    vs = [p.matrix_world @ v.co for p in parts for v in p.data.vertices]
    front = [v for v in vs if v.z > FRONT_Z and ang_from_front(v.x, v.y) < FRONT_ARC]
    hi = [v for v in vs if v.z > FRONT_Z]
    out_band = [v for v in hi if not (R_IN - 0.02 <= math.hypot(v.x, v.y) <= R_OUT + 0.02)]
    back = max((v.z for v in vs if ang_from_front(v.x, v.y) > 135), default=0)
    side = max((v.z for v in vs if 45 <= ang_from_front(v.x, v.y) <= 120), default=0)
    print(f"THEME front_hi={len(front)} out_band={len(out_band)} back_z={back:.2f} side_z={side:.2f} "
          f"top={max(v.z for v in vs):.2f}")


def stand_in_frame():
    """Preview only: a plain ring where the tier frame mesh goes (r 2.6..3.75, top 0.28)."""
    c = rgb(200, 150, 100)
    return lathe("StandInFrame", [(2.6, 0), (3.75, 0), (3.75, 0.28), (2.6, 0.28), (2.6, 0.0)], segs=40,
                 color_fn=lambda i, k, z: c if i == 2 else shade(c, 0.85))


def theme_finish(name, parts, drop=0.0):
    _flatten(parts, -drop)
    theme_check(parts)
    if PREVIEW:
        from models._goo_jar import cork_stand
        stand = cork_stand()
        for o in stand:
            o.location.z -= DECK
        extra = [stand_in_frame()] if os.environ.get("THEME_FRAME", "1") == "1" else []
        return finish(name, parts + stand + extra)
    check(parts, drop)
    write_deck_offset(name, parts)  # out/<name>.deck.json: bbox centre on the deck (the front is clear, so it is off centre)
    return finish(name, parts)
