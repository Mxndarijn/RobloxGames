# Shared builder for ranch_crate / ranch_crate_goo: a 3 x 3 x 3 stud slatted crate that
# stacks: flat top and bottom (z = 0 and z = 3), same footprint, nothing proud of either.
# Corner posts 0.8, slats/planks >= 0.4 thick, soft bevels, dark-below/light-above per part.
# Colours come from the calling script (C = dict of palette colours).
import math
import bmesh
from lib import *

S = 3.0            # footprint and height
H = S / 2
PLANK = 0.42       # top/bottom deck plank thickness
POST = 0.8


def pbox(name, size, pos, bot, top, bev=0.1, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    bevel(o, bev)
    gradient(o, bot, top)
    return o


def crate(C, slat_lo, slat_hi, post_lo, post_hi, deck_lo, deck_hi, seed=0):
    """Returns the parts list. slat_* = side slats, post_* = corner posts, deck_* = top/bottom planks."""
    parts = []
    # dark-ish core so the gaps between slats read as depth, not see-through
    core = box("Core", (S - 0.5, S - 0.5, S - 2 * PLANK + 0.02), (0, 0, H), C["core"])
    parts.append(core)
    # top and bottom decks: 3 planks each, running along X; slightly uneven widths
    widths = (0.98, 1.04, 0.98)
    for zc, nm in ((PLANK / 2, "Bot"), (S - PLANK / 2, "Top")):
        y = -H
        for k, w in enumerate(widths):
            lo, hi = (deck_lo, deck_hi) if nm == "Top" else (mix(deck_lo, deck_hi, -0.0), deck_lo)
            parts.append(pbox(f"{nm}{k}", (S, w - 0.04, PLANK), (0, y + w / 2, zc), lo, hi, bev=0.09))
            y += w
    # corner posts between the decks
    ph = S - 2 * PLANK
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(pbox(f"Post{sx}{sy}", (POST, POST, ph + 0.02), (sx * (H - POST / 2), sy * (H - POST / 2), H),
                              post_lo, post_hi, bev=0.12))
    # side slats between the posts: 2 per face, a bit proud of the core, inset from the posts
    span = S - 2 * POST + 0.1
    for face in range(4):
        a = face * 90
        for k, (zc, hgt) in enumerate(((1.08, 0.78), (1.98, 0.74))):
            jit = 0.03 * ((face + k + seed) % 3 - 1)
            o = pbox(f"Slat{face}{k}", (span, 0.42, hgt), (0, -H + 0.27, zc + jit), slat_lo, slat_hi, bev=0.09)
            o.rotation_euler = (0, 0, math.radians(a))
            apply_transforms(o)
            parts.append(o)
    return parts
