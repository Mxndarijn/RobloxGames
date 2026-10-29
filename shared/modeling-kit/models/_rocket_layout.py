# Space Rocket base (Exclusive): the layout. Numbers only; the building is models/_round_base_layout.py.
# Four hull stages, each a wide glass band, tapering a stud per stage; the nose cone on whichever floor is on top.
from models._base_design_common import floor_top
from models._round_base_layout import WALL_H, build

ID = "rocket"
NAME = "Space Rocket"


NOSE_RIM = 26.0  # floor 4's rim (room_out(4)): the nose is built for it and scaled to the top floor's rim


def nose_k(f):
    """The nose on top floor f is floor 4's scaled by this, about its rim (one mesh fits every top floor)."""
    return (SPEC["ROOM_R"][f - 1] + 1.0) / NOSE_RIM


NOSE_H = 30.0  # floor 4's nose height (rim to the cockpit floor)
# the ogive's rows as (radius / rim, height / NOSE_H): a bowed-out bullet, flat-topped for the cockpit
NOSE_ROWS = ((1.0, 0.0), (0.97, 0.14), (0.87, 0.32), (0.70, 0.52), (0.49, 0.72), (0.33, 0.88), (0.23, 1.0))


def roof(f, rim):
    zt = floor_top(f) + WALL_H
    k = rim / NOSE_RIM
    # proportional to the rim, so a uniform scale of floor 4's nose mesh fits every top floor
    return [(rim * a + (0.5 * k if i == 0 else 0.0), zt + NOSE_H * k * b) for i, (a, b) in enumerate(NOSE_ROWS)]


SPEC = {
    "ID": ID, "NAME": NAME,
    "ROOM_R": (28.0, 27.0, 26.0, 25.0),
    "PAD_R": (19.0, 16.0, 16.0, 16.0),
    "ROOF": roof,
    "MASCOT_Z": lambda f: floor_top(f) + WALL_H + NOSE_H * nose_k(f),  # the pilot in the glass cockpit
}
globals().update(build(SPEC))
