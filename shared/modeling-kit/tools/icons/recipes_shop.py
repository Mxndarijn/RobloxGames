from recipes import icon, FRONT
from props import *


@icon("Lock", view=(30, 18))
def lock():
    return [padlock(C["blue"])]


@icon("LockUpgrade", view=(30, 18))
def lock_upgrade():
    pl = padlock(C["teal"], pos=(-0.8, 0, 0))
    parts = [pl]
    # stopwatch hung on the shackle (right side)
    sw = [disc("Watch", 1.05, 0.5, C["white"], (0, 0, 0), segs=16),
          disc("WatchRim", 1.2, 0.36, C["red"], (0, 0.06, 0), segs=16),
          disc("Hand", 0.1, 0.1, C["ink"], (0, -0.3, 0), segs=6),
          prism("HandA", [(-0.07, 0), (0.07, 0), (0.07, 0.75), (-0.07, 0.75)], 0.1, C["ink"], (0, -0.31, 0)),
          prism("HandB", [(-0.07, 0), (0.07, 0), (0.07, 0.55), (-0.07, 0.55)], 0.1, C["ink"], (0, -0.31, 0), rot=(0, 0, -70)),
          cylinder("Knob", 0.2, 0.35, (0, 0, 1.15), C["red_d"], segs=8)]
    parts.append(group(sw, (2.5, -1.0, 1.35), name="watch"))
    parts.append(prism("Arrow", [(0, 1.0), (0.8, 0.1), (0.3, 0.1), (0.3, -0.9), (-0.3, -0.9), (-0.3, 0.1), (-0.8, 0.1)], 0.45, C["green"], (2.7, -1.6, 3.7), bevel_w=0.07))
    return parts


@icon("SpeedCoil", view=(25, 28))
def speed_coil():
    parts = []
    # chunky spring: stacked tilted rings
    n = 7
    for i in range(n):
        z = 0.9 + i * 0.62
        parts.append(torus(f"Coil{i}", 1.55, 0.3, C["gold"] if i % 2 == 0 else C["gold_d"], (0, 0, z), (90, 0, 0), a0=0, a1=360, segs=14, rsegs=6))
        parts[-1].rotation_euler = (math.radians(90), 0, 0)
        parts[-1].rotation_euler.x = math.radians(90)
    parts = []
    # build as a helix tube instead
    pts, rad = [], []
    turns, steps = 4.0, 64
    for i in range(steps + 1):
        a = math.tau * turns * i / steps
        pts.append((1.6 * math.cos(a), 1.6 * math.sin(a), 1.0 + 4.2 * i / steps))
        rad.append(0.34)
    spring = tube("Spring", pts, rad, C["gold"], segs=6)
    gradient(spring, C["gold_d"], C["gold_l"])
    parts.append(spring)
    parts.append(cylinder("BaseDisc", 2.1, 0.5, (0, 0, 0.0), C["grey_d"], segs=14))
    parts.append(cylinder("BaseRing", 1.6, 0.3, (0, 0, 0.5), C["grey"], segs=14))
    parts.append(cylinder("TopDisc", 2.1, 0.5, (0, 0, 5.4), C["grey_d"], segs=14))
    parts.append(cylinder("TopCap", 1.6, 0.3, (0, 0, 5.9), C["grey"], segs=14))
    parts.append(bolt(C["yellow"], 1.45, 0.6, (0, -2.05, 3.5), (0, 0, 0)))
    parts.append(bolt(C["white"], 0.9, 0.62, (0.02, -2.2, 3.5), (0, 0, 0)))
    return parts


@icon("MysteryEgg", view=(18, 14))
def mystery_egg():
    parts = []
    prof = [(0, 0), (1.5, 0.05), (2.3, 0.7), (2.65, 1.8), (2.5, 3.0), (1.95, 4.1), (1.1, 4.8), (0, 5.05)]

    def col(i, k, z):
        return mix(C["cream_d"], C["cream"], min(1, z / 3.0))
    egg = lathe_obj("Egg", prof, col, segs=18)
    smooth(egg, True)
    parts.append(egg)
    spots = [(-1.7, -1.4, 1.2, 0.5, C["purple"]), (1.7, -1.3, 3.4, 0.42, C["purple"]), (-1.2, -1.8, 3.9, 0.3, C["purple_d"]),
             (1.9, -0.9, 1.3, 0.34, C["purple_d"]), (-0.3, -2.4, 0.75, 0.3, C["purple"])]
    for i, (x, y, z, r, c) in enumerate(spots):
        parts.append(blobc(f"Spot{i}", r, (x, y, z), c, squash=(1, 0.35, 1)))
    parts.append(text("?", 3.2, C["purple_d"], 0.28, (0, -2.45, 2.45)))
    parts.append(text("?", 3.2, C["white"], 0.1, (-0.08, -2.62, 2.55)))
    for i, (x, z, s) in enumerate(((-2.9, 4.4, 0.4), (2.9, 4.9, 0.32), (3.0, 2.2, 0.26))):
        parts.append(sparkle((x, -1.0, z), s, C["gold_l"], f"S{i}"))
    return parts


@icon("Slap", view=(15, 10))
def slap():
    parts = []
    glove = C["white"]
    palm = rbox("Palm", (3.0, 1.2, 3.0), (0, 0, 1.6), glove, 0.35)
    parts.append(palm)
    for i, (x, h) in enumerate(((-1.15, 1.9), (-0.38, 2.3), (0.38, 2.3), (1.15, 1.9))):
        parts.append(rbox(f"Finger{i}", (0.72, 0.95, h), (x, 0, 3.0 + h / 2 - 0.1), glove, 0.25))
    parts.append(rbox("Thumb", (0.85, 0.95, 1.9), (-2.0, 0, 2.4), glove, 0.25, rot=(0, -50, 0)))
    parts.append(rbox("Cuff", (3.3, 1.5, 0.9), (0, 0, 0.35), C["orange"], 0.2))
    parts.append(rbox("CuffStripe", (3.35, 1.55, 0.25), (0, 0, 0.55), C["orange_d"], 0.08))
    for i, (x, z, ln) in enumerate(((3.2, 4.4, 2.0), (3.6, 3.0, 2.4), (3.3, 1.6, 1.8))):
        parts.append(prism(f"Swoosh{i}", [(0, 0), (ln, 0.14), (ln, -0.14)], 0.25, C["orange"], (x, 0, z)))
    for sgn in (-1,):
        parts.append(sparkle((-2.7, -0.7, 5.2), 0.5, C["yellow"], "Pow"))
    return parts
