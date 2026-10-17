from recipes import icon, FRONT
from props import *


def small_book(num, cover):
    p = [rbox("Cover", (2.2, 0.7, 2.7), (0, 0, 0), cover, 0.1), rbox("Pages", (2.0, 0.5, 2.5), (0.1, 0.18, 0), C["cream"], 0.05),
         rbox("Spine", (0.3, 0.8, 2.75), (-1.05, -0.02, 0), shade(cover, 0.7), 0.05),
         text(str(num), 1.1 if len(str(num)) < 3 else 0.82, C["white"], 0.12, (0.1, -0.4, 0.15)),
         prism("BookStar", star_pts(5, 0.34, 0.16), 0.1, C["gold"], (0.1, -0.4, 0.95))]
    return group(p, name="book")


def crown_obj(c):
    pts = [(-1.6, -0.9), (1.6, -0.9), (1.7, 0.9), (0.85, 0.1), (0, 1.3), (-0.85, 0.1), (-1.7, 0.9)]
    p = [prism("Crown", pts, 0.5, c, bevel_w=0.06), rbox("CBand", (3.2, 0.55, 0.45), (0, 0, -0.9), C["gold_d"], 0.05)]
    for i, (x, z, col) in enumerate(((-1.7, 0.95, C["red"]), (0, 1.35, C["blue"]), (1.7, 0.95, C["green"]))):
        p.append(blobc(f"Gem{i}", 0.3, (x, -0.1, z + 0.12), col, subdiv=1))
    return group(p, name="crown")


def key_obj():
    p = [torus("KeyRing", 0.9, 0.3, C["gold"], (0, 0, 1.2), segs=14, rsegs=6), cylinder("KeyShaft", 0.26, 2.6, (0, 0, -1.6), C["gold"], segs=8),
         box("Tooth1", (0.8, 0.3, 0.45), (0.5, 0, -2.9), C["gold_d"]), box("Tooth2", (0.6, 0.3, 0.4), (0.4, 0, -2.2), C["gold_d"])]
    return group(p, name="key")


def hand_obj():
    g = C["white"]
    p = [rbox("Palm", (1.9, 0.9, 1.7), (0, 0, 0), g, 0.25)]
    for i, x in enumerate((-0.7, -0.23, 0.23, 0.7)):
        p.append(rbox(f"F{i}", (0.42, 0.7, 1.1), (x, 0, 1.2), g, 0.15))
    p.append(rbox("Th", (0.5, 0.7, 1.0), (-1.2, 0, 0.3), g, 0.15, rot=(0, -45, 0)))
    p.append(blobc("Goo", 0.6, (0.3, -0.6, -0.5), C["green"], squash=(1, 0.6, 1.2)))
    p.append(blobc("Goo2", 0.35, (-0.5, -0.6, -1.1), C["green"], squash=(1, 0.6, 1.5)))
    return group(p, name="hand")


def medal(emblem, ribbon, plate, ribbon2=None, rim=None):
    parts = []
    rb2 = ribbon2 or shade(ribbon, 0.75)
    for s in (-1, 1):
        parts.append(prism(f"Rib{s}", [(s * 3.0, 5.2), (s * 1.3, 5.2), (s * -0.7, 1.7), (s * 1.0, 1.7)] if s > 0 else [(-3.0, 5.2), (-1.3, 5.2), (0.7, 1.7), (-1.0, 1.7)], 0.45, ribbon, (0, 0.55, 0), bevel_w=0.05))
    parts.append(prism("RibStripeL", [(-2.5, 5.2), (-1.95, 5.2), (-0.1, 1.7), (-0.5, 1.7)], 0.5, rb2, (0, 0.5, 0)))
    parts.append(prism("RibStripeR", [(2.5, 5.2), (1.95, 5.2), (0.1, 1.7), (0.5, 1.7)], 0.5, rb2, (0, 0.5, 0)))
    parts.append(disc("MedalRim", 2.55, 0.55, rim or C["gold_d"], (0, 0, 0), segs=24, bevel_w=0.1))
    parts.append(disc("MedalFace", 2.25, 0.62, C["gold"], (0, -0.02, 0), segs=24))
    gradient(parts[-1], C["gold_d"], C["gold_l"], -2.25, 2.25)
    parts.append(disc("Plate", 1.75, 0.7, plate, (0, -0.05, 0), segs=24))
    gradient(parts[-1], shade(plate, 0.82), shade(plate, 1.15), -1.75, 1.75)
    parts.append(torus("Loop", 0.4, 0.14, C["gold_d"], (0, 0.1, 2.75), segs=10, rsegs=4))
    for o in emblem:
        parts.append(o)
    return parts


def _badge(icon_id, ribbon, plate, build, view=(0, 8)):
    @icon(icon_id, view=view)
    def _fn():
        return medal(build(), ribbon, plate)
    return _fn


def _place(o, pos, scale=1.0, rot=(0, 0, 0)):
    return group([o], pos, rot, scale, "emb")


_badge("Badge_FirstSlime", C["green"], rgb(60, 130, 200), lambda: [slime((130, 240, 150), "happy", (0, -0.5, -1.35), (0, 0, 0), 0.82)])
_badge("Badge_FirstSteal", C["red"], rgb(120, 60, 150), lambda: [_place(hand_obj(), (0, -0.5, -0.5), 1.0)])
_badge("Badge_FirstRebirth", C["teal"], rgb(30, 120, 110), lambda: [clean_circ_arrow(C["green_l"], 1.15, 0.42, 40, 318, 0.3, 0.9, 0.8, pos=(0, -0.5, 0), name="a")])
_badge("Badge_Rebirth5", C["blue"], rgb(40, 70, 150), lambda: [clean_circ_arrow(C["blue_l"], 1.35, 0.32, 40, 318, 0.3, 0.8, 0.7, pos=(0, -0.5, 0), name="a"), text("5", 1.9, C["white"], 0.3, (0, -0.55, 0))])
_badge("Badge_Dex25", C["orange"], rgb(150, 76, 40), lambda: [_place(small_book(25, rgb(236, 150, 80)), (0, -0.5, 0), 1.0)])
_badge("Badge_Dex50", rgb(120, 130, 160), rgb(70, 78, 110), lambda: [_place(small_book(50, rgb(200, 210, 230)), (0, -0.5, 0), 1.0)])
_badge("Badge_Dex100", C["gold_d"], rgb(150, 100, 20), lambda: [_place(small_book(100, rgb(255, 214, 70)), (0, -0.5, 0), 1.0)])
_badge("Badge_FirstLegendary", C["orange"], rgb(190, 60, 70), lambda: [_place(crown_obj(C["gold_l"]), (0, -0.5, 0), 0.9)])
_badge("Badge_FirstSecret", C["purple"], rgb(70, 40, 120), lambda: [_place(padlock(C["gold"]), (0, -0.6, -0.9), 0.62)])
_badge("Badge_Millionaire", C["green_d"], rgb(30, 100, 70), lambda: [text("1M", 1.9, C["gold_l"], 0.3, (0, -0.55, 0.1)), sparkle((1.3, -0.7, 1.3), 0.35, C["white"], "sp")])
