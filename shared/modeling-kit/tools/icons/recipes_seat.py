from recipes import icon
from helpers import run_model

# Pet seat icons (Skins menu, Cloud tab): the mount a follow pet rides on, alone (no slime), rebuilt from its own
# shipping script (models/pet_cloud.py, models/pet_mount_<id>.py; see models/PET_MOUNTS.md) so the vertex colours
# match the FBX in out/. Seen from a bit higher than the item default so the seat top reads.
__all__ = []  # registers via @icon; exports nothing
SEAT_VIEW = (30, 30)
SEATS = ["cloud", "jelly", "rainbow_cloud", "storm_cloud", "sunset_cloud", "ice_cloud", "flame_cloud", "leaf",
         "bubble", "magic_carpet", "ufo", "lily_pad", "star_cushion", "crescent_moon", "mushroom", "pancakes",
         "hoverboard", "clam_shell", "royal_cushion"]
# per-seat overrides: (yaw, pitch) and fill
VIEW = {"crescent_moon": (20, 62), "bubble": (30, 45)}
FILL = {}
# icon-only colour lift for near-white pastel seats that blow out to plain white under the key light:
# (saturation multiplier, value multiplier) on the vertex colours. The shipped FBX is untouched.
TINT = {"bubble": (1.9, 0.92)}


def _tint(o, sat, val):
    import colorsys
    for d in o.data.color_attributes["Col"].data:
        r, g, b, a = d.color
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        d.color = (*colorsys.hsv_to_rgb(h, min(1.0, s * sat), v * val), a)


def _seat(sid):
    model = "pet_cloud" if sid == "cloud" else "pet_mount_" + sid

    def build():
        o = run_model(model)
        if sid in TINT:
            _tint(o, *TINT[sid])
        return [o]
    build.__name__ = "seat_" + sid
    return build


for _sid in SEATS:
    icon("PetSeat_" + _sid, view=VIEW.get(_sid, SEAT_VIEW), fill=FILL.get(_sid))(_seat(_sid))
