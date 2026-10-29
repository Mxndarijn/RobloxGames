# Snow Globe base (Exclusive): the layout. Numbers only; the building is models/_round_base_layout.py.
# Floor 1 is the wooden pedestal; floors 2-4 bulge out and back in so the glass reads as one globe, its dome on top.
from models._base_design_common import floor_top
from models._round_base_layout import WALL_H, build

ID = "snowglobe"
NAME = "Snow Globe"


def roof(f, rim):
    zt = floor_top(f) + WALL_H
    return [(rim + 0.5, zt), (rim - 4.0, zt + 6.0), (rim - 12.0, zt + 10.5), (6.0, zt + 12.5)]  # the glass dome


SPEC = {
    "ID": ID, "NAME": NAME,
    "ROOM_R": (28.0, 25.0, 28.0, 25.0),
    "PAD_R": (19.0, 15.5, 16.0, 15.5),
    "ROOF": roof,
    "MASCOT_Z": lambda f: floor_top(f) + WALL_H + 12.5,
}
globals().update(build(SPEC))
