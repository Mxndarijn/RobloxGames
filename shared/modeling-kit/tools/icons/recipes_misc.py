from recipes import icon, FRONT
from props import *


def gift_box(box_c=None, rib=None, open_lid=True, sp=True):
    box_c = box_c or C["purple"]
    rib = rib or C["gold"]
    parts = []
    parts.append(rbox("Box", (4.0, 4.0, 2.7), (0, 0, 1.35), box_c, 0.14))
    gradient(parts[-1], shade(box_c, 0.72), shade(box_c, 1.12), 0, 2.7)
    parts.append(rbox("RibA", (0.85, 4.08, 2.72), (0, 0, 1.35), rib, 0.06))
    parts.append(rbox("RibB", (4.08, 0.85, 2.72), (0, 0, 1.35), rib, 0.06))
    lid_z = 3.5 if open_lid else 3.15
    lid = [rbox("Lid", (4.5, 4.5, 0.9), (0, 0, 0), shade(box_c, 1.12), 0.12),
           rbox("LRibA", (0.9, 4.58, 0.92), (0, 0, 0), rib, 0.05), rbox("LRibB", (4.58, 0.9, 0.92), (0, 0, 0), rib, 0.05)]
    for s in (-1, 1):
        lid.append(blobc(f"Bow{s}", 0.9, (s * 0.85, 0, 0.9), rib, squash=(1.2, 0.55, 0.9), rot=(0, s * -28, 0)))
        lid.append(blobc(f"BowIn{s}", 0.45, (s * 0.95, -0.35, 0.95), C["gold_d"], squash=(1.1, 0.4, 0.8), rot=(0, s * -28, 0)))
    lid.append(blobc("Knot", 0.5, (0, 0, 0.75), C["gold_d"]))
    parts.append(group(lid, (0, 0.2 if open_lid else 0, lid_z), (-14 if open_lid else 0, 0, 0), name="lid"))
    if open_lid and sp:
        for i, (x, z, s) in enumerate(((-1.4, 4.0, 0.4), (1.2, 4.5, 0.55), (0.0, 5.6, 0.32))):
            parts.append(sparkle((x, -1.5, z + 0.3), s, C["yellow"], f"S{i}"))
    return parts


@icon("Appraise", view=(22, 12))
def appraise():
    parts = []
    parts.append(slime((120, 225, 140), "surprised", (0.1, 0.9, -1.9), (0, 0, 0), 0.95))
    parts.append(disc("Glass_Lens", 2.4, 0.2, rgb(210, 240, 255), (0, -0.1, 0.5), segs=24))
    parts.append(torus("Frame", 2.55, 0.42, C["gold"], (0, -0.1, 0.5), segs=24, rsegs=8))
    parts.append(torus("FrameIn", 2.2, 0.1, C["gold_l"], (0, -0.45, 0.5), segs=24, rsegs=4))
    parts.append(tube("Handle", [(1.85, -0.1, -1.35), (3.0, -0.1, -2.9), (4.2, -0.1, -4.3)], [0.42, 0.45, 0.55], C["brown"], segs=8))
    parts.append(tube("Grip", [(3.0, -0.1, -2.9), (4.4, -0.1, -4.5)], [0.5, 0.58], C["brown_d"], segs=8))
    parts.append(prism("Glint", [(0, 0), (1.0, 0.2), (0.8, 0.5), (0.1, 0.7)], 0.15, C["white"], (-1.4, -0.5, 1.4), rot=(0, 0, -20)))
    parts.append(sparkle((2.5, -0.8, 2.9), 0.5, C["yellow"], "S1"))
    parts.append(sparkle((-2.9, -0.8, -1.0), 0.35, C["white"], "S2"))
    return parts


@icon("Daily", view=(10, 12))
def daily():
    parts = []
    pg = [rbox("Page", (5.0, 0.5, 5.8), (0, 0, 0), C["white"], 0.15),
          rbox("Head", (5.02, 0.56, 1.35), (0, -0.02, 2.2), C["red"], 0.1),
          rbox("Under", (5.0, 0.3, 5.8), (0.15, 0.4, -0.15), C["cream_d"], 0.1)]
    for x in (-1.5, 0, 1.5):
        pg.append(torus(f"Ring{x}", 0.32, 0.09, C["grey"], (x, -0.4, 2.95), segs=10, rsegs=4))
    pg.append(prism("StarBack", star_pts(5, 2.0, 0.95), 0.3, C["orange"], (0, -0.38, -0.55), bevel_w=0.1))
    pg.append(prism("Star", star_pts(5, 1.7, 0.8), 0.3, C["gold"], (0, -0.55, -0.55), bevel_w=0.08))
    parts.append(group(pg, rot=(0, 0, 5), name="page"))
    parts.append(group(gift_box(C["purple"], C["gold"], False, False), (2.3, -1.0, -3.0), (0, 0, -8), 0.45, "minigift"))
    return parts


@icon("Rebirth", view=(0, 10))
def rebirth():
    parts = [circ_arrow(C["green"], 2.9, 0.62, 40, 320, name="arr")]
    parts.append(slime((130, 235, 170), "happy", (0, 0, -1.35), (0, 0, 0), 0.9))
    for i, (x, z, s) in enumerate(((-3.2, 3.2, 0.45), (3.3, -2.3, 0.4), (0.4, 4.7, 0.35))):
        parts.append(sparkle((x, -1.0, z), s, C["gold_l"], f"S{i}"))
    return parts


@icon("Cash", view=(18, 24))
def cash():
    return [coin_pile("$")]


@icon("Gift", view=(22, 22))
def gift():
    return gift_box()


@icon("Quest", view=(25, 8))
def quest():
    parts = []
    cols = [C["brown"], C["red"], C["white"], C["red"], C["white"], C["red"]]
    rads = [3.4, 3.05, 2.45, 1.85, 1.25, 0.65]
    for i, (c, r) in enumerate(zip(cols, rads)):
        parts.append(disc(f"Ring{i}", r, 0.4, c, (0, -i * 0.12, 0), segs=24))
    for s in (-1, 1):
        parts.append(tube(f"Leg{s}", [(s * 1.4, 0.4, -2.0), (s * 2.3, 1.0, -4.1)], [0.3, 0.3], C["brown_d"], segs=6))
    shaft = tube("Shaft", [(0.15, -1.0, 0.05), (2.2, -2.9, 1.7), (3.6, -4.2, 2.8)], [0.2, 0.2, 0.2], C["gold"], segs=6)
    parts.append(shaft)
    parts.append(tube("Tip", [(0.0, -0.7, 0.0), (0.15, -1.05, 0.05)], [0.1, 0.3], C["grey"], segs=6))
    for i, (a, b) in enumerate(((0, 0.15), (120, 0.15), (240, 0.15))):
        pass
    parts.append(prism("FletchA", [(0, 0), (1.3, 0.6), (1.3, -0.6), (0.2, -0.8)], 0.08, C["red"], (3.2, -3.9, 2.5), rot=(40, 0, 40)))
    parts.append(prism("FletchB", [(0, 0), (1.3, 0.6), (1.3, -0.6), (0.2, -0.8)], 0.08, C["red_d"], (3.2, -3.9, 2.5), rot=(40, 90, 40)))
    parts.append(sparkle((-3.2, -1.2, 3.2), 0.45, C["yellow"], "S"))
    return parts


@icon("Code_SLIMEBOOST", view=(22, 16))
def code_slimeboost():
    return [potion(label="x2", liquid=C["yellow"], label_color=C["red"])]


@icon("Code_WELCOME", view=(18, 24))
def code_welcome():
    return [coin_pile("$")]


@icon("Code_LAUNCH", view=(18, 24))
def code_launch():
    p = coin_pile("$", extra=3)
    return [p, sparkle((-3.2, -1.2, 3.8), 0.5, C["white"], "S1"), sparkle((3.3, -1.2, 4.4), 0.4, C["yellow"], "S2")]
