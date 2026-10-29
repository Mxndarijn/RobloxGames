# Carousel Tent base (Exclusive): the layout. Numbers only; the building is models/_round_base_layout.py.
# Four round carousel decks behind glass between gold poles, a striped big-top roof on whichever floor is on top.

from models._base_design_common import floor_top
from models._round_base_layout import WALL_H, build

ID = "carousel"
NAME = "Carousel Tent"


def roof(f, rim):
    zt = floor_top(f) + WALL_H
    # the big-top tent from its eave to the finial: two slopes (shallow skirt, steep peak) so it sags like canvas
    return [(rim + 3.0, zt), (17.0, zt + 6.5), (2.0, zt + 20.0)]


SPEC = {
    "ID": ID, "NAME": NAME,
    "ROOM_R": (28.0, 28.0, 28.0, 28.0),
    "PAD_R": (19.0, 16.0, 16.0, 16.0),
    "ROOF": roof,
    "MASCOT_Z": lambda f: floor_top(f) + WALL_H + 26.0,  # on the finial's plate, above the pennant
}
globals().update(build(SPEC))
