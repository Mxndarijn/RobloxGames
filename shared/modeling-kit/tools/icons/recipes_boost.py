from recipes import icon, FRONT
from props import *


@icon("Boost_Code", view=(22, 16))
def boost_code():
    return [potion(bolt=True, liquid=C["yellow"])]


@icon("Boost_Blessed", view=(10, 30))
def boost_blessed():
    parts = [slime((160, 110, 255), "happy", (0, 0, 0), (0, 0, 0), 1.0)]
    halo = torus("Halo", 1.6, 0.32, C["gold_l"], (0, 0.1, 4.0), (90, 0, 0), segs=20, rsegs=6)
    parts.append(halo)
    parts.append(torus("HaloOuter", 2.9, 0.14, C["purple_l"], (0, 0.1, 1.9), (90, 0, 0), segs=24, rsegs=5))
    for i, (x, z, s) in enumerate(((-2.8, 4.2, 0.5), (2.9, 3.6, 0.4), (-2.3, 0.4, 0.3), (2.6, 0.2, 0.32), (0.2, 5.9, 0.34))):
        parts.append(sparkle((x, -0.7, z), s, C["white"] if i % 2 else C["gold_l"], f"S{i}"))
    return parts


@icon("Boost_Weekend", view=FRONT)
def boost_weekend():
    parts = [prism("Burst", star_pts(10, 4.6, 3.1), 0.4, C["orange"], (0, 0.5, 0), bevel_w=0.1)]
    parts.append(prism("Burst2", star_pts(10, 3.8, 2.6, 90 + 9), 0.4, rgb(255, 188, 70), (0, 0.25, 0), bevel_w=0.1))
    parts.append(text("x2", 4.4, C["ink"], 0.9, (0.15, -0.2, -0.2)))
    parts.append(text("x2", 4.4, C["gold"], 0.9, (0, -0.55, 0)))
    cols = [C["blue"], C["pink"], C["green"], C["purple"], C["yellow"], C["teal"], C["red"]]
    import random
    r = random.Random(4)
    for i in range(18):
        a = r.uniform(0, 360)
        d = r.uniform(4.3, 5.8)
        x, z = d * math.cos(math.radians(a)), d * math.sin(math.radians(a))
        parts.append(box(f"Conf{i}", (0.5, 0.15, 0.25), (x, -0.4, z), cols[i % len(cols)], rot=(0, 0, r.uniform(0, 180))))
    cal = [rbox("Cal", (2.3, 0.4, 2.5), (-4.1, -0.9, -3.4), C["white"], 0.1), rbox("CalTop", (2.3, 0.45, 0.8), (-4.1, -0.95, -2.6), C["red"], 0.08),
           text("2", 1.4, C["ink"], 0.1, (-4.1, -1.2, -3.7))]
    parts += cal
    return parts


@icon("Boost_Friend", view=FRONT)
def boost_friend():
    parts = [slime((110, 225, 130), "happy", (-2.6, 0, 0), (0, 0, -14), 1.0)]
    parts.append(slime((120, 190, 255), "happy", (2.6, 0, 0), (0, 0, 14), 1.0))
    parts.append(blobc("HandL", 0.55, (-0.5, -1.0, 2.2), C["green"]))
    parts.append(blobc("HandR", 0.55, (0.5, -1.0, 2.2), rgb(120, 190, 255)))
    parts.append(prism("Heart", heart_pts(2.4), 0.8, C["pink"], (0, -0.8, 3.1), bevel_w=0.14))
    for s in (-1, 1):
        parts.append(sparkle((s * 1.5, -1.2, 4.9), 0.35, C["yellow"], f"Z{s}"))
    return parts


@icon("Perk_income", view=(22, 14))
def perk_income():
    parts = []
    prof = [(0, 0), (1.5, 0), (2.3, 0.8), (2.4, 1.9), (1.8, 3.0), (0.9, 3.5), (0.7, 3.9), (0, 3.9)]
    parts.append(lathe_obj("Bag", prof, lambda i, k, z: mix(rgb(190, 140, 80), rgb(236, 190, 120), min(1, z / 3)), segs=16))
    smooth(parts[-1])
    parts.append(torus("Tie", 0.8, 0.2, C["red"], (0, 0, 3.55), (90, 0, 0), segs=12, rsegs=5))
    parts[-1].rotation_euler = (0, 0, 0)
    for s in (-1, 1):
        parts.append(prism(f"Frill{s}", [(0, 0), (s * 0.9, 0.7), (s * 1.3, -0.1)], 0.5, rgb(214, 160, 96), (0, 0, 3.7)))
    parts.append(text("$", 2.4, C["green_d"], 0.3, (0, -2.5, 1.7)))
    # ears
    for s in (-1, 1):
        parts.append(blobc(f"Ear{s}", 0.55, (s * 0.7, 0.2, 4.8), C["green"], squash=(0.8, 0.7, 1.5), rot=(0, s * 20, 0)))
    parts.append(coin("Pop", 1.1, 0.4, (1.9, -1.0, 4.6), (-80, 0, 20), mark="$"))
    parts.append(sparkle((-2.3, -1.2, 4.7), 0.4, C["gold_l"], "S"))
    return [group(parts, rot=(0, 0, -15), name="bag")]


@icon("Perk_luck", view=(0, 8))
def perk_luck():
    parts = []
    for i, a in enumerate((90, 210, 330)):
        pts = rot_pts(heart_pts(2.3), a + 90)
        parts.append(prism(f"Leaf{i}", pts, 0.5, shade(C["green"], 1.0 + 0.06 * (i - 1)), bevel_w=0.08))
    parts.append(tube("Stem", [(0, -0.3, -0.2), (0.3, -0.3, -2.0), (0.9, -0.3, -2.8)], [0.17, 0.15, 0.12], C["green_d"], segs=6))
    # ladybug on the upper-right leaf
    bx, bz = 1.5, 1.7
    parts.append(blobc("Bug", 0.75, (bx, -0.7, bz), C["red"], squash=(1, 0.7, 0.85)))
    parts.append(blobc("BugHead", 0.36, (bx - 0.75, -0.7, bz + 0.2), C["ink"]))
    parts.append(box("BugLine", (0.07, 0.5, 1.3), (bx, -1.1, bz), C["ink"]))
    for i, (dx, dz) in enumerate(((-0.28, 0.25), (0.3, 0.25), (-0.28, -0.25), (0.3, -0.25))):
        parts.append(blobc(f"Dot{i}", 0.13, (bx + dx, -1.2, bz + dz), C["ink"], subdiv=1, squash=(1, 0.5, 1)))
    parts.append(sparkle((-2.5, -0.9, 2.8), 0.4, C["white"], "S"))
    return parts


def dna(sparse=False, h=7.0, turns=1.6, R=1.4):
    parts = []
    steps = 40
    for k, (col, ph) in enumerate(((C["purple"], 0), (C["green"], math.pi))):
        pts = [(R * math.cos(math.tau * turns * i / steps + ph), 0.0 + R * math.sin(math.tau * turns * i / steps + ph) * 0.45, h * i / steps) for i in range(steps + 1)]
        parts.append(tube(f"Strand{k}", pts, [0.34] * len(pts), col, segs=6))
    for i in range(1, 9):
        t = i / 9
        a = math.tau * turns * t
        x1, y1 = R * math.cos(a), R * math.sin(a) * 0.45
        parts.append(tube(f"Rung{i}", [(x1, y1, h * t), (-x1, -y1, h * t)], [0.14, 0.14], C["white"] if i % 2 else C["gold_l"], segs=5))
    return parts


@icon("Perk_mutation", view=(20, 8))
def perk_mutation():
    parts = [group(dna(), (0, 0, 0), name="dna")]
    for i, (x, y, z, s) in enumerate(((2.3, -0.5, 1.5, 0.35), (-2.4, -0.4, 3.6, 0.45), (2.0, -0.6, 5.8, 0.3), (-1.9, -0.6, 7.2, 0.26))):
        parts.append(blobc(f"Bub{i}", s, (x, y, z), C["green_l"] if i % 2 else C["purple_l"]))
    return parts


@icon("Event_luck", view=FRONT)
def event_luck():
    parts = []
    cols = [C["red"], C["orange"], C["yellow"], C["green"], C["blue"], C["purple"]]
    for i, c in enumerate(cols):
        parts.append(torus(f"Rb{i}", 5.0 - i * 0.62, 0.34, c, (0, 0.6, 0), a0=0, a1=180, segs=26, rsegs=6))
    parts.append(clover(C["green"], 0.95, (0, -0.4, 1.0), name="clv"))
    pot = lathe_obj("Pot", [(0, 0), (1.0, 0), (1.6, 0.6), (1.7, 1.4), (1.35, 1.8), (1.55, 1.95), (0, 1.95)], lambda i, k, z: mix(rgb(40, 36, 52), rgb(90, 86, 110), min(1, z / 1.8)), segs=14, pos=(4.1, -0.7, 0))
    parts.append(pot)
    for i, (x, y, z) in enumerate(((3.5, -0.7, 1.95), (4.1, -0.9, 2.1), (4.7, -0.7, 1.95), (3.9, -0.5, 2.3), (4.4, -0.5, 2.25))):
        parts.append(coin(f"G{i}", 0.5, 0.25, (x, y, z), (-30 + i * 15, 0, i * 40)))
    parts.append(sparkle((-3.6, -0.5, 4.2), 0.4, C["gold_l"], "S"))
    return parts


@icon("Event_mutation", view=(22, 14))
def event_mutation():
    parts = []
    prof = [(0, 0), (1.9, 0), (2.7, 0.5), (2.1, 1.9), (1.2, 3.2), (0.75, 3.6), (0.75, 4.4), (0.95, 4.55), (0, 4.55)]
    parts.append(lathe_obj("Glass_Flask", prof, lambda i, k, z: rgb(190, 225, 250), segs=16))
    prof2 = [(0, 0.1), (1.8, 0.1), (2.55, 0.55), (2.3, 1.2), (0, 1.2)]
    parts.append(lathe_obj("Liquid", prof2, lambda i, k, z: mix(C["green_d"], C["green"], z), segs=16))
    parts.append(slime((120, 255, 170), "surprised", (0, 0, 0.5), (0, 0, 0), 0.62))
    for i, (x, y, z, s) in enumerate(((-0.9, -0.8, 3.3, 0.3), (0.6, -0.6, 4.1, 0.24), (-0.3, -0.5, 5.2, 0.34), (0.8, -0.4, 6.0, 0.22))):
        parts.append(blobc(f"Bub{i}", s, (x, y, z), C["green_l"]))
    parts.append(sparkle((2.9, -0.8, 4.6), 0.5, C["pink"], "S1"))
    parts.append(sparkle((-3.0, -0.8, 3.6), 0.4, C["gold_l"], "S2"))
    return parts


@icon("Event_rain", view=FRONT)
def event_rain():
    parts = []
    for i, (x, z, r) in enumerate(((-2.4, 0, 1.7), (-0.8, 0.9, 2.2), (1.2, 0.8, 2.0), (2.7, -0.1, 1.5), (0.0, -0.2, 2.1))):
        parts.append(blobc(f"Cloud{i}", r, (x, 0, z + 4.2), rgb(96, 130, 200) if i % 2 else rgb(120, 160, 225), squash=(1, 0.8, 0.85)))
    parts.append(box("CloudFlat", (6.6, 3.0, 0.3), (0.2, 0, 2.6), rgb(80, 108, 176)))
    for i, (x, z) in enumerate(((-2.4, 1.0), (-0.9, -0.4), (0.7, 0.9), (2.2, -0.2), (-1.6, -2.0), (0.0, -2.3), (1.7, -1.9))):
        parts.append(group([drop((0, 0, 0), 0.5, C["green"], f"D{i}")], (x, -1.2, z + 0.8), name="drop"))
    return parts
