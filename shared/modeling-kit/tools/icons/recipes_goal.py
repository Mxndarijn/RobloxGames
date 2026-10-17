from recipes import icon, FRONT
from props import *
from recipes_misc import gift_box  # noqa: F401


def trophy(num, base_c, scale=1.0):
    parts = []
    cup = lathe_obj("Cup", [(0, 2.9), (0.6, 2.9), (0.9, 3.2), (1.5, 4.0), (1.9, 5.2), (2.0, 6.4), (1.75, 6.5), (0, 6.5)],
                    lambda i, k, z: mix(C["gold_d"], C["gold_l"], min(1, (z - 2.9) / 3.6)), segs=16)
    smooth(cup)
    parts.append(cup)
    parts.append(lathe_obj("CupInside", [(0, 6.05), (1.7, 6.05), (1.75, 6.5), (0, 6.5)], rgb(120, 70, 20), segs=16))
    parts.append(cylinder("Stem", 0.42, 1.2, (0, 0, 1.9), C["gold"], segs=10, r_top=0.32))
    parts.append(blobc("Knob", 0.7, (0, 0, 2.7), C["gold"], squash=(1, 1, 0.7)))
    for s in (-1, 1):
        parts.append(torus(f"Handle{s}", 0.95, 0.2, C["gold"], (s * 2.05, 0, 5.1), a0=-90 if s > 0 else 90, a1=90 if s > 0 else 270, segs=14, rsegs=6))
    parts.append(rbox("Base", (4.8, 2.8, 1.2), (0, 0, 0.6), base_c, 0.14))
    gradient(parts[-1], shade(base_c, 0.78), shade(base_c, 1.1), 0, 1.2)
    parts.append(rbox("BaseTop", (3.6, 2.2, 0.7), (0, 0, 1.45), C["gold"], 0.1))
    n = len(str(num))
    parts.append(text(str(num), 2.1 if n < 3 else 1.2, C["white"], 0.14, (0, -1.5, 0.6)))
    parts.append(slime((120, 230, 140), "happy", (0, 0.1, 5.65), (0, 0, 0), 0.55))
    parts.append(sparkle((-3.1, -1.0, 5.9), 0.4, C["white"], "S1"))
    parts.append(sparkle((3.2, -1.0, 6.6), 0.32, C["yellow"], "S2"))
    return group(parts, scale=scale, name="trophy")


_DEX = {10: rgb(176, 112, 64), 25: rgb(150, 160, 178), 50: rgb(70, 140, 240), 100: rgb(80, 190, 100), 200: rgb(160, 96, 230), 400: rgb(232, 62, 70), 720: rgb(60, 56, 90)}
for _n, _c in _DEX.items():
    def _mk(n=_n, c=_c):
        @icon(f"Dex_{n}", view=(14, 12))
        def _dex():
            return [trophy(n, c)]
    _mk()


@icon("Goal_Catch", view=(18, 18))
def goal_catch():
    parts = []
    parts.append(torus("Hoop", 2.4, 0.22, C["grey"], (0, 0, 4.0), (90, 0, 0), segs=22, rsegs=6))
    parts[-1].rotation_euler = (math.radians(90) * 0, 0, 0)
    parts.pop()
    parts.append(torus("Hoop", 2.4, 0.24, C["grey"], (0, 0, 4.2), (80, 0, 0), segs=22, rsegs=6))
    bag = lathe_obj("GlassClear_Net", [(0, 0.2), (0.9, 0.5), (1.9, 1.5), (2.4, 4.2), (0, 4.2)], rgb(210, 240, 255), segs=14)
    parts.append(bag)
    parts.append(slime((60, 235, 110), "surprised", (0, -0.4, 0.5), (0, 0, 0), 1.05))
    parts.append(tube("Handle", [(2.3, 0.3, 4.0), (4.0, 0.3, 2.3), (6.4, 0.3, -0.3)], [0.3, 0.34, 0.4], C["brown"], segs=8))
    parts.append(sparkle((-3.0, -0.8, 5.6), 0.4, C["white"], "S"))
    return parts


@icon("Goal_Merge", view=(14, 16))
def goal_merge():
    parts = []
    pts, rad = [], []
    for i in range(41):
        a = math.tau * 1.4 * i / 40
        r = 3.5 - 1.6 * i / 40
        pts.append((r * math.cos(a), r * math.sin(a) * 0.9, 0.5 + 3.2 * i / 40))
        rad.append(0.2)
    parts.append(tube("Swirl", pts, rad, C["purple_l"], segs=5))
    parts.append(slime((170, 100, 235), "happy", (0, 0, 0), (0, 0, 0), 1.3))
    parts.append(slime((110, 190, 255), "default", (-3.4, 0, 3.2), (0, 0, 24), 0.55))
    parts.append(slime((255, 140, 190), "default", (3.4, 0, 3.4), (0, 0, -24), 0.55))
    for x in (-1, 1):
        parts.append(sparkle((x * 1.4, -1.8, 5.3), 0.3, C["yellow"], f"S{x}"))
    return parts


@icon("Goal_Steal", view=(12, 12))
def goal_steal():
    import models._slime as S
    parts = []
    g = [slime((235, 100, 100), "mischievous", (0, 0, 0), (0, 0, 0), 1.0)]
    z0, z1 = 1.38, 1.92
    g.append(lathe_obj("Mask", [(0, z0), (S.radius(z0) + 0.07, z0), (S.radius(z1) + 0.07, z1), (0, z1)], C["ink"], segs=20))
    for s in (-1, 1):
        p = S.surface(s * 0.5, 1.62, 0.1)
        g.append(blobc(f"EyeHole{s}", 0.3, tuple(p), C["white"], squash=(1, 0.4, 1.1)))
        p2 = S.surface(s * 0.5, 1.62, 0.2)
        g.append(blobc(f"Pupil{s}", 0.13, tuple(p2), C["ink"], squash=(1, 0.5, 1.1)))
    parts.append(group(g, rot=(0, 12, 0), name="thief"))
    sack = [blobc("Sack", 1.15, (0, 0, 1.1), rgb(150, 110, 70), squash=(1, 0.9, 1.05)),
            cone("SackTop", 0.55, 0.9, (0, 0, 2.0), rgb(150, 110, 70), segs=8), torus("Tie", 0.45, 0.1, C["red"], (0, 0, 2.05), (0, 0, 0)),
            text("$", 1.3, C["gold"], 0.2, (0, -1.1, 1.1))]
    parts[-1].rotation_euler = (0, 0, 0)
    parts.append(group(sack, (2.6, 0.2, 0.0), (0, 0, 14), 0.95, "sack"))
    parts.append(coin("Pop", 0.5, 0.2, (2.0, -0.4, 2.7), (-80, 0, 30)))
    for i, (x, z, ln) in enumerate(((-3.7, 2.2, 1.6), (-4.1, 1.2, 2.0), (-3.5, 0.2, 1.3))):
        parts.append(prism(f"Speed{i}", [(0, 0), (ln, 0.12), (ln, -0.12)], 0.2, C["blue_l"], (x, -0.5, z)))
    return parts


@icon("Goal_Lock", view=(28, 16))
def goal_lock():
    pl = padlock(C["blue"])
    st = [prism("Star", star_pts(5, 0.85, 0.4), 0.2, C["gold"], (0, -1.0, 0.85), bevel_w=0.04)]
    return [pl, group([prism("StarBack", star_pts(5, 0.82, 0.38), 0.18, C["gold"], bevel_w=0.04)], (0, -0.98, 1.25), name="st"),
            sparkle((2.7, -1.0, 3.7), 0.45, C["yellow"], "S")]


@icon("Goal_Pads", view=(25, 28))
def goal_pads():
    parts = []
    parts.append(cylinder("Pad", 3.6, 0.9, (0, 0, 0), C["stone"], segs=8))
    gradient(parts[-1], C["stone_d"], C["stone"])
    parts.append(cylinder("PadTop", 3.1, 0.15, (0, 0, 0.88), C["stone_d"], segs=8))
    parts.append(cylinder("Glow", 2.6, 0.12, (0, 0, 1.0), C["green_l"], segs=16))
    parts.append(torus("GlowRing", 2.75, 0.14, C["green"], (0, 0, 1.1), (90, 0, 0), segs=20, rsegs=5))
    parts[-1].rotation_euler = (0, 0, 0)
    parts.pop()
    parts.append(slime((120, 225, 140), "happy", (0, 0, 1.0), (0, 0, 0), 0.9))
    for i in range(4):
        a = i * 90 + 45
        parts.append(sparkle((3.4 * math.cos(math.radians(a)), 3.4 * math.sin(math.radians(a)), 1.6), 0.3, C["green_l"], f"S{i}"))
    return parts


@icon("Goal_Earn", view=(20, 14))
def goal_earn():
    parts = [stack_of_coins(10, 1.7, 0.5)]
    parts.append(coin("Lean", 1.3, 0.4, (2.8, -1.5, 1.0), (-62, 0, 20), mark="$"))
    parts.append(coin("Lean2", 1.1, 0.4, (-2.6, -1.6, 0.9), (-62, 0, -20)))
    parts.append(sparkle((-2.8, -1.0, 5.2), 0.5, C["yellow"], "S1"))
    parts.append(sparkle((2.9, -1.0, 5.8), 0.35, C["white"], "S2"))
    return parts


@icon("Goal_Rebirth", view=(0, 10))
def goal_rebirth():
    parts = [circ_arrow(C["green"], 3.0, 0.7, 35, 325, name="arr")]
    parts.append(prism("Star", star_pts(5, 1.25, 0.6), 0.5, C["gold"], (0, -0.2, 0), bevel_w=0.08))
    for i, (x, z, s) in enumerate(((-3.4, 3.4, 0.5), (3.5, -2.4, 0.4), (0.3, 4.8, 0.35), (-3.2, -3.0, 0.3))):
        parts.append(sparkle((x, -1.0, z), s, C["gold_l"], f"S{i}"))
    return parts
