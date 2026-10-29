# Tree House base (Exclusive): the layout. Numbers only; the building is models/_round_base_layout.py.
# Floors 1-2 are rooms inside the fat bark stump, 3-4 plank cabins widening into the crown; the leaf canopy on top.
from models._base_design_common import floor_top
from models._round_base_layout import WALL_H, build

ID = "treehouse"
NAME = "Tree House"


def roof(f, rim):
    zt = floor_top(f) + WALL_H
    return [(rim + 2.0, zt), (rim - 6.0, zt + 6.0), (12.0, zt + 12.0), (5.0, zt + 15.0)]  # the canopy's leaf roof


SPEC = {
    "ID": ID, "NAME": NAME,
    "ROOM_R": (27.5, 27.5, 29.0, 30.0),
    "PAD_R": (19.0, 16.0, 17.0, 17.5),
    "ROOF": roof,
    "MASCOT_Z": lambda f: floor_top(f) + WALL_H + 15.0,  # in the bird nest on the crown
}
globals().update(build(SPEC))
