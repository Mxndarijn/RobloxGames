# Space Rocket base (Exclusive): the layout. Numbers only; the building is models/_round_base_layout.py.
# Four hull stages, each a wide glass band, tapering a stud per stage; the nose cone on whichever floor is on top.
from models._base_design_common import floor_top
from models._round_base_layout import WALL_H, build

ID = "rocket"
NAME = "Space Rocket"


def roof(f, rim):
    zt = floor_top(f) + WALL_H
    return [(rim + 0.5, zt), (rim * 0.8, zt + 9.0), (rim * 0.42, zt + 23.0), (6.0, zt + 29.0)]  # an ogive nose


SPEC = {
    "ID": ID, "NAME": NAME,
    "ROOM_R": (28.0, 27.0, 26.0, 25.0),
    "PAD_R": (19.0, 16.0, 16.0, 16.0),
    "ROOF": roof,
    "MASCOT_Z": lambda f: floor_top(f) + WALL_H + 29.0,  # the pilot in the glass cockpit
}
globals().update(build(SPEC))
