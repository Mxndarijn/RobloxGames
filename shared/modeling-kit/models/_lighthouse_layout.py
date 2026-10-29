# Lighthouse base (Exclusive): the layout. Numbers only; the building is models/_round_base_layout.py.
# A striped tower narrowing per floor, each floor a wide window band; the gallery and lantern room on top.
from models._base_design_common import floor_top
from models._round_base_layout import WALL_H, _cyl, _ring_facets, build

ID = "lighthouse"
NAME = "Lighthouse"
LANTERN_R = 9.5
LANTERN_H = 9.0


def roof(f, rim):
    zt = floor_top(f) + WALL_H
    return [(rim + 3.0, zt + 0.6), (LANTERN_R + 1.5, zt + 1.2)]  # the gallery deck (a flat ring)


def roof_extra(f):
    zt = floor_top(f) + WALL_H + 1.2
    out = [_cyl("Lantern", f, "roof", (0, 0, zt + LANTERN_H / 2), 2 * LANTERN_R, LANTERN_H)]
    out += _ring_facets("LanternCap", f, "roof", 0.8, zt + LANTERN_H + 8.0, LANTERN_R + 1.5, zt + LANTERN_H, 12)
    return out


SPEC = {
    "ID": ID, "NAME": NAME,
    "ROOM_R": (28.0, 26.5, 25.0, 23.5),
    "PAD_R": (19.0, 15.5, 15.5, 15.0),
    "ROOF": roof,
    "ROOF_EXTRA": roof_extra,
    "MASCOT_Z": None,
}
SPEC["MASCOT_Z"] = lambda f: floor_top(f) + WALL_H + 1.2 + LANTERN_H + 8.0
globals().update(build(SPEC))
