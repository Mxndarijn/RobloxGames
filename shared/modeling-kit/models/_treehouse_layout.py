# Tree House base (Exclusive): the layout. Numbers only; the building is models/_round_base_layout.py.
# Floors 1-2 are rooms inside the fat bark stump, 3-4 plank cabins widening into the crown; the leaf canopy on top.
from models._base_design_common import floor_top
from models._round_base_layout import WALL_H, build

ID = "treehouse"
NAME = "Tree House"


ROOF_NATIVE_RIM = 31.0  # floor 4's room_out: the canopy mesh is built there and scaled onto lower top floors


def roof_k(rim):
    """The canopy is one similar shape for every top floor: scaled by rim / ROOF_NATIVE_RIM about its rim's foot."""
    return rim / ROOF_NATIVE_RIM


def roof(f, rim):
    zt = floor_top(f) + WALL_H
    k = roof_k(rim)
    return [(33.0 * k, zt), (29.0 * k, zt + 6.0 * k), (21.0 * k, zt + 13.0 * k), (11.0 * k, zt + 18.5 * k),
            (5.0 * k, zt + 20.0 * k)]  # the canopy's leaf dome


SPEC = {
    "ID": ID, "NAME": NAME,
    "ROOM_R": (27.5, 27.5, 29.0, 30.0),
    "PAD_R": (19.0, 16.0, 17.0, 17.5),
    "ROOF": roof,
    "MASCOT_Z": lambda f: floor_top(f) + WALL_H + 20.0 * roof_k((27.5, 27.5, 29.0, 30.0)[f - 1] + 1.0),  # the nest
}
globals().update(build(SPEC))
