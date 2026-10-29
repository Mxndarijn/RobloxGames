# Snow Globe base (Exclusive): the layout. Numbers only; the building is models/_round_base_layout.py.
# Floor 1 is the wooden pedestal; floors 2-4 bulge out and back in so the glass reads as one globe, its dome on top.
#
# The globe's curve (the meshes in models/_snowglobe_pieces.py follow it; the roof collider below is sampled from it):
#   barrel  floors 2-4 stacked: r = GLOBE_A - GLOBE_C (z - GLOBE_ZC)^2, from the pedestal top (z 17.2, r 26.5) out to
#           29.8 at floor 3's middle and back to 26.6 at floor 4's top (64.4);
#   dome    an ellipse quarter that starts where the glass below it ends (radius r0, slope s0) and reaches the crown
#           (r CROWN_R) DOME_H above the rim: dome_ellipse(r0, s0) -> (A, B, u), r(z) = A sqrt(1 - ((z - zt + u) / B)^2).
#   The small dome (rim 26, floors 2 and 4) continues the barrel's inward curve; the big one (rim 29, floors 1 and 3)
#   sits on floor 3's nearly upright barrel (or on the pedestal when floor 1 is the top).
import math

from models._base_design_common import floor_top
from models._round_base_layout import WALL_H, build

ID = "snowglobe"
NAME = "Snow Globe"

PED_TOP = floor_top(2) + 0.2            # the pedestal's head band top, where the globe's glass starts
GLOBE_A, GLOBE_ZC = 29.8, 41.0
GLOBE_C = (GLOBE_A - 26.5) / (GLOBE_ZC - PED_TOP) ** 2
DOME_H = 16.0                            # rim to crown
CROWN_R = 6.0


def globe_r(z):
    """The stacked globe's glass radius at height z (floors 2-4)."""
    return GLOBE_A - GLOBE_C * (z - GLOBE_ZC) ** 2


def globe_slope(z):
    return -2 * GLOBE_C * (z - GLOBE_ZC)


def dome_ellipse(r0, s0):
    """(A, B, u) of the dome ellipse through (r0, rim) with slope s0 (dr/dz < 0) and r = CROWN_R at DOME_H up; its
    centre is u below the rim."""
    def crown_r(u):
        b2 = u * u + r0 * u / -s0
        a2 = -s0 * r0 * b2 / u
        t = (DOME_H + u) ** 2 / b2
        return math.sqrt(a2 * (1 - t)) if t < 1 else -1.0
    lo, hi = 0.01, 20.0
    for _ in range(80):
        mid = (lo + hi) / 2
        if crown_r(mid) < CROWN_R:
            lo = mid
        else:
            hi = mid
    u = (lo + hi) / 2
    b2 = u * u + r0 * u / -s0
    return math.sqrt(-s0 * r0 * b2 / u), math.sqrt(b2), u


def dome_start(rim):
    """(r0, s0): where the top floor's dome starts. Small rims (26) meet the barrel's inward curve, big rims (29) the
    nearly upright floor-3 barrel."""
    zt4 = floor_top(4) + WALL_H
    zt3 = floor_top(3) + WALL_H
    if rim < 27.5:
        return round(globe_r(zt4), 3), globe_slope(zt4)
    return rim + 0.5, globe_slope(zt3)


def dome_r(rim, dz):
    """The dome's radius dz above its rim (rim: the top room's outer radius)."""
    r0, s0 = dome_start(rim)
    A, B, u = dome_ellipse(r0, s0)
    t = (dz + u) / B
    return A * math.sqrt(max(0.0, 1 - t * t))


def roof(f, rim):
    zt = floor_top(f) + WALL_H
    return [(round(dome_r(rim, dz), 3), zt + dz) for dz in (0.0, 5.0, 9.5, 13.5, DOME_H)]  # the glass dome


SPEC = {
    "ID": ID, "NAME": NAME,
    "ROOM_R": (28.0, 25.0, 28.0, 25.0),
    "PAD_R": (19.0, 15.5, 16.0, 15.5),
    "ROOF": roof,
    "MASCOT_Z": lambda f: floor_top(f) + WALL_H + DOME_H,
}
globals().update(build(SPEC))
