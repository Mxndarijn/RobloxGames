"""Roblox store icons for Steal a Slime's Game Passes and Developer Products (the icon Roblox shows in its purchase
popup, the game page's Store tab and the Roblox Shop). Ids are `Store_<pass or product key>`; products whose item
already has an in-game icon recipe (seats, hats, bases...) reuse it, see games/steal-a-slime/docs/shop-icons/build.py."""
from recipes import icon, FRONT
from props import *
from recipes_upgrade import crescent_pts


# ---------------------------------------------------------------- shared bits
def x2_mark(pos=(0, 0, 0), size=2.6, color=None, name="x2"):
    """Chunky 'x2' with an ink drop shadow (the Boost_Weekend look)."""
    color = color or C["green"]
    a = text("x2", size, C["ink"], size * 0.22, (size * 0.04, size * 0.08, -size * 0.05))
    b = text("x2", size, color, size * 0.22, (0, -size * 0.08, 0))
    return group([a, b], pos, name=name)


def label(string, size, color, pos, shadow=True, name="lbl"):
    parts = [text(string, size, color, size * 0.22, (0, -size * 0.08, 0))]
    if shadow:
        parts.append(text(string, size, C["ink"], size * 0.22, (size * 0.04, size * 0.08, -size * 0.05)))
    return group(parts, pos, name=name)


def thief(pos=(0, 0, 0), rot=(0, 0, 0), scale=1.0):
    """The masked red thief slime of Goal_Steal."""
    import models._slime as S
    g = [slime((235, 100, 100), "mischievous", (0, 0, 0), (0, 0, 0), 1.0)]
    z0, z1 = 1.38, 1.92
    g.append(lathe_obj("Mask", [(0, z0), (S.radius(z0) + 0.07, z0), (S.radius(z1) + 0.07, z1), (0, z1)], C["ink"], segs=20))
    for s in (-1, 1):
        p = S.surface(s * 0.5, 1.62, 0.1)
        g.append(blobc(f"EyeHole{s}", 0.3, tuple(p), C["white"], squash=(1, 0.4, 1.1)))
        p2 = S.surface(s * 0.5, 1.62, 0.2)
        g.append(blobc(f"Pupil{s}", 0.13, tuple(p2), C["ink"], squash=(1, 0.5, 1.1)))
    return group(g, pos, rot, scale, "thief")


def stopwatch(txt, pos=(0, 0, 0), scale=1.0, rim=None, name="watch"):
    rim = rim or C["red"]
    parts = [disc("WRim", 2.0, 0.7, rim, (0, 0.1, 0), segs=24, bevel_w=0.1),
             disc("WFace", 1.68, 0.7, C["white"], (0, -0.12, 0), segs=24),
             cylinder("WStem", 0.32, 0.6, (0, 0, 1.9), C["grey"], segs=8),
             rbox("WKnob", (1.1, 0.7, 0.45), (0, 0, 2.6), rim, 0.12)]
    for s in (-1, 1):
        parts.append(rbox(f"WEar{s}", (0.5, 0.5, 0.4), (s * 1.5, 0, 1.55), C["grey"], 0.1, rot=(0, s * -40, 0)))
    parts.append(text(txt, 1.25 if len(txt) < 3 else 1.0, C["ink"], 0.2, (0, -0.55, -0.05)))
    return group(parts, pos, (0, 0, 0), scale, name)


def flame(pos=(0, 0, 0), s=1.0, name="flame"):
    pts = []
    for i in range(24):
        t = math.tau * i / 24
        x = math.sin(t) * (1.0 - 0.25 * math.cos(t))
        z = -math.cos(t)
        if z > 0:  # pull the top half into a point
            x *= (1 - z) ** 0.9
            z = z * 1.9
        pts.append((x * s, z * s))
    outer = prism(name + "O", pts, 0.6 * s, C["orange"], bevel_w=0.1 * s)
    inner = prism(name + "I", [(x * 0.55, z * 0.55 - 0.35 * s) for x, z in pts], 0.6 * s, C["yellow"], (0, -0.2 * s, 0), bevel_w=0.08 * s)
    return group([outer, inner], pos, name=name)


def crown(pos=(0, 0, 0), scale=1.0, gem=None, name="crown"):
    gem = gem or C["red"]
    parts = []
    band = cylinder("Band", 2.4, 1.4, (0, 0, 0), C["gold"], segs=24)
    gradient(band, C["gold_d"], C["gold_l"], 0, 1.4)
    parts.append(band)
    parts.append(cylinder("Velvet", 2.15, 1.9, (0, 0, 0.1), C["purple"], segs=20))
    parts.append(blobc("VelvetTop", 2.0, (0, 0, 1.95), C["purple"], squash=(1, 1, 0.45)))
    for i in range(5):
        a = math.radians(-90 + i * 72)
        x, y = 2.15 * math.cos(a), 2.15 * math.sin(a)
        p = cone(f"Prong{i}", 0.85, 2.1, (x, y, 1.25), C["gold"], segs=10)
        gradient(p, C["gold"], C["gold_l"], 1.2, 3.3)
        parts.append(p)
        parts.append(blobc(f"Tip{i}", 0.34, (x, y, 3.35), C["gold_l"]))
    parts.append(gem_obj("GemF", 0.5, (0, -2.45, 0.7), gem))
    for s in (-1, 1):
        a = math.radians(-90 + s * 55)
        parts.append(gem_obj(f"GemS{s}", 0.38, (2.45 * math.cos(a), 2.45 * math.sin(a), 0.7), C["blue"]))
    return group(parts, pos, (0, 0, 0), scale, name)


def gem_obj(name, r, pos, color):
    return blobc(name, r, pos, color, squash=(1, 0.55, 1.15), subdiv=1, flat=True)


# ---------------------------------------------------------------- Game Passes
@icon("Store_VIP", view=(14, 14))
def store_vip():
    parts = [crown((0, 0, 0.9), 1.0)]
    plate = rbox("Plate", (4.6, 0.7, 1.7), (0, -2.6, -0.2), C["purple"], 0.2)
    gradient(plate, C["purple_d"], C["purple"], -1.1, 0.7)
    parts.append(plate)
    parts.append(text("VIP", 1.35, C["gold_l"], 0.3, (0, -3.0, -0.25)))
    for i, (x, z, s) in enumerate(((-3.2, 3.6, 0.5), (3.3, 2.6, 0.42), (2.6, 4.6, 0.3))):
        parts.append(sparkle((x, -1.6, z), s, C["yellow"], f"S{i}"))
    return parts


@icon("Store_Income2x", view=(18, 18))
def store_income2x():
    parts = [coin_pile("$")]
    parts.append(x2_mark((1.4, -3.4, 3.6), 3.0, C["green"]))
    parts.append(sparkle((-2.6, -1.0, 3.6), 0.45, C["yellow"], "S0"))
    return parts


@icon("Store_Offline2x", view=(14, 8))
def store_offline2x():
    parts = [disc("Night", 3.5, 0.5, C["night"], (0, 0.75, 0), segs=24, bevel_w=0.1)]
    gradient(parts[-1], rgb(40, 40, 110), rgb(86, 90, 180), -3.5, 3.5)
    moon = prism("Moon", crescent_pts(2.9, 50, 1.1), 0.8, C["gold"], (-0.4, 0.15, 0.3), bevel_w=0.12)
    gradient(moon, C["gold"], C["gold_l"], -3, 3)
    parts.append(moon)
    parts.append(slime((120, 225, 150), "sleepy", (-1.0, -0.5, -1.6), (0, 0, -8), 0.5))
    parts.append(x2_mark((2.0, -1.4, -1.8), 2.4, C["green"]))
    for i, (x, z, s) in enumerate(((1.7, 2.3, 0.38), (2.6, 0.7, 0.28))):
        parts.append(sparkle((x, -0.6, z), s, C["yellow"], f"Star{i}"))
    return parts


@icon("Store_FastBrew", view=(20, 16))
def store_fastbrew():
    parts = [run_model("merge_vat")]
    parts.append(bolt(C["yellow"], 2.3, 1.0, (0, -5.6, 5.6)))
    parts.append(bolt(C["orange"], 2.3, 1.0, (0.18, -5.2, 5.4)))
    for i, (x, z, s) in enumerate(((-4.6, 8.4, 0.7), (4.4, 9.4, 0.55))):
        parts.append(sparkle((x, -4.0, z), s, C["yellow"], f"S{i}"))
    return parts


@icon("Store_WarmNest", view=(18, 18))
def store_warmnest():
    parts = [run_model("mystery_egg_nest")]
    parts.append(run_model("mystery_egg_speckled", (0, 0, 0.3)))
    heat = []
    for k, x in enumerate((-0.65, 0.0, 0.65)):
        pts, rad = [], []
        for i in range(9):
            t = i / 8
            pts.append((x + 0.16 * math.sin(t * math.tau * 1.2 + k), -0.4, 2.75 + t * 1.2))
            rad.append(0.1)
        heat.append(tube(f"Heat{k}", pts, rad, C["orange"], segs=6))
    parts += heat
    parts.append(flame((1.55, -1.6, 0.35), 0.55, "flame"))
    parts.append(prism("Heart", heart_pts(0.42), 0.25, C["pink"], (-1.6, -1.3, 2.2), bevel_w=0.05))
    return parts


@icon("Store_LuckyCharmPlus", view=(0, 6))
def store_luckycharm():
    parts = [clover(C["green"], 1.5, name="clv")]
    plus = [(-0.35, -1.1), (0.35, -1.1), (0.35, -0.35), (1.1, -0.35), (1.1, 0.35), (0.35, 0.35), (0.35, 1.1),
            (-0.35, 1.1), (-0.35, 0.35), (-1.1, 0.35), (-1.1, -0.35), (-0.35, -0.35)]
    parts.append(prism("PlusS", [(x * 1.25, z * 1.25) for x, z in plus], 0.5, C["ink"], (2.65, -0.5, 2.15), bevel_w=0.08))
    parts.append(prism("Plus", plus, 0.6, C["gold"], (2.6, -0.95, 2.2), bevel_w=0.1))
    parts.append(sparkle((-2.7, -0.8, 2.8), 0.45, C["white"], "Gl"))
    parts.append(sparkle((2.4, -0.8, -2.6), 0.35, C["yellow"], "G2"))
    return parts


@icon("Store_ThiefRadar", view=(0, 10))
def store_thiefradar():
    parts = []
    face = disc("Scope", 3.6, 0.5, rgb(12, 52, 54), (0, 0.4, 0), segs=40)
    parts.append(face)
    parts.append(torus("Rim", 3.6, 0.38, C["grey"], (0, 0.2, 0), segs=40, rsegs=8))
    mint = rgb(108, 242, 194)
    for r in (1.2, 2.4):
        parts.append(torus(f"Ring{r}", r, 0.07, shade(mint, 0.7), (0, 0.05, 0), segs=36, rsegs=4))
    parts.append(box("CrossH", (6.8, 0.1, 0.1), (0, 0.05, 0), shade(mint, 0.6)))
    parts.append(box("CrossV", (0.1, 0.1, 6.8), (0, 0.05, 0), shade(mint, 0.6)))
    sweep = [(0, 0)] + [(3.4 * math.cos(math.radians(a)), 3.4 * math.sin(math.radians(a))) for a in range(40, 101, 6)]
    parts.append(prism("Sweep", sweep, 0.12, mint, (0, -0.05, 0)))
    parts.append(blobc("Blip", 0.45, (1.7, -0.2, -1.2), C["red"], squash=(1, 0.5, 1)))
    parts.append(torus("BlipRing", 0.8, 0.07, C["red"], (1.7, -0.1, -1.2), segs=20, rsegs=4))
    parts.append(thief((-1.5, -2.0, -3.4), (0, 0, 14), 0.95))
    return parts


@icon("Store_AutoCollect", view=(0, 10))
def store_autocollect():
    parts = []
    mag = [torus("Arc", 1.9, 0.75, C["red"], (0, 0, 0), a0=180, a1=360, segs=24, rsegs=10)]
    for s in (-1, 1):
        mag.append(cylinder(f"Leg{s}", 0.75, 1.6, (s * 1.9, 0, 0), C["red"], segs=12, rot=(0, 0, 0)))
        mag.append(cylinder(f"Tip{s}", 0.77, 0.9, (s * 1.9, 0, 1.55), C["grey"], segs=12))
    parts.append(group(mag, (-1.6, 0, 1.2), (0, 75, 0), 1.25, "magnet"))
    for i, (x, z, r, rot) in enumerate(((2.4, 2.6, 1.15, -75), (4.4, 3.4, 1.0, -65), (4.0, 0.6, 1.0, -80))):
        parts.append(coin(f"Fly{i}", r, 0.42, (x, -0.4, z), (rot, 0, 15 * i), mark="$"))
    for i, (x, z, ln) in enumerate(((5.6, 4.0, 1.2), (5.4, 1.0, 1.0))):
        parts.append(prism(f"Speed{i}", [(0, 0), (ln, 0.14), (ln, -0.14)], 0.2, C["blue_l"], (x, -0.4, z)))
    parts.append(sparkle((0.6, -1.0, 4.4), 0.5, C["yellow"], "S0"))
    return parts


# ---------------------------------------------------------------- Developer Products: quick buys
FINISH = {1: "5m", 2: "30m", 3: "1h", 4: "1h+"}


def _finish(n):
    def build():
        parts = [run_model("merge_vat")]
        parts.append(bolt(C["yellow"], 1.7, 0.9, (-2.6, -5.4, 5.6)))
        parts.append(stopwatch(FINISH[n], (2.9, -5.6, 3.0), 1.55))
        return parts
    build.__name__ = f"finish_{n}"
    return build


for _n in FINISH:
    icon(f"Store_FinishBrew_{_n}", view=(20, 14))(_finish(_n))


def _hatch(kind):
    def build():
        parts = [run_model("mystery_egg_" + kind)]
        parts.append(bolt(C["yellow"], 0.42, 0.25, (0.95, -0.95, 1.85)))
        for i, (x, z, s) in enumerate(((-1.15, 2.0, 0.22), (1.25, 0.6, 0.17))):
            parts.append(sparkle((x, -0.9, z), s, C["gold_l"], f"S{i}"))
        return parts
    build.__name__ = "hatch_" + kind
    return build


for _k in ("speckled", "shiny", "golden", "cosmic"):
    icon(f"Store_HatchNow_{_k}", view=(18, 12))(_hatch(_k))


@icon("Store_DoubleOffline", view=(18, 22))
def store_doubleoffline():
    parts = [coin_pile("$")]
    moon = prism("Moon", crescent_pts(2.6, 50, 1.0), 0.6, C["purple_l"], (-0.6, 2.0, 3.4), bevel_w=0.1)
    gradient(moon, C["purple"], C["purple_l"], 1, 6)
    parts.append(moon)
    parts.append(sparkle((-3.0, 0.5, 5.2), 0.45, C["yellow"], "S0"))
    parts.append(sparkle((2.6, 0.5, 6.0), 0.35, C["yellow"], "S1"))
    parts.append(x2_mark((1.8, -3.4, 2.6), 2.8, C["gold"]))
    return parts


@icon("Store_ServerLuckPotion", view=(10, 10))
def store_serverluck():
    parts = [potion(None, C["green"], pos=(0, 0, 0.8), rot=(0, 0, 0))]
    parts.append(clover(C["green_l"], 0.55, pos=(0, -2.2, 2.3), name="lbl_clover"))
    for i, (x, tint) in enumerate(((-2.9, (120, 190, 255)), (2.9, (255, 150, 200)))):
        parts.append(slime(tint, "happy", (x, -0.6, 0), (0, 0, -18 if x > 0 else 18), 0.62))
    return parts


@icon("Store_GrowthSnack", view=(16, 18))
def store_growthsnack():
    parts = []
    ck = [cylinder("Cookie", 2.2, 0.7, (0, 0, 0), rgb(214, 156, 92), segs=20)]
    gradient(ck[0], rgb(176, 118, 62), rgb(232, 178, 112), 0, 0.7)
    import random
    r = random.Random(3)
    for i in range(8):
        a, d = r.uniform(0, 360), r.uniform(0.3, 1.7)
        ck.append(blobc(f"Chip{i}", 0.26, (d * math.cos(math.radians(a)), d * math.sin(math.radians(a)), 0.72), C["green"], squash=(1, 1, 0.6)))
    parts.append(group(ck, (0.3, 0.6, 2.2), (72, 0, 0), 1.0, "cookie"))
    arrow = [(0, 1.6), (1.2, 0.3), (0.45, 0.3), (0.45, -1.4), (-0.45, -1.4), (-0.45, 0.3), (-1.2, 0.3)]
    parts.append(prism("ArrowS", [(x * 1.12, z * 1.12) for x, z in arrow], 0.5, C["ink"], (2.65, -0.9, 3.25), bevel_w=0.08))
    parts.append(prism("Arrow", arrow, 0.6, C["green"], (2.6, -1.3, 3.3), bevel_w=0.1))
    parts.append(slime((110, 225, 130), "happy", (-1.8, -1.2, 0.0), (0, 0, 14), 0.75))
    return parts


def _boost(txt):
    def build():
        parts = [stopwatch(txt, (0, 0, 0), 1.45, C["green_d"])]
        parts.append(x2_mark((1.9, -1.6, 2.6), 2.4, C["gold"]))
        return parts
    build.__name__ = "boost_" + txt
    return build


icon("Store_IncomeBoost15", view=(10, 8))(_boost("15m"))
icon("Store_IncomeBoost60", view=(10, 8))(_boost("1h"))


@icon("Store_KeepStreak", view=(10, 12))
def store_keepstreak():
    parts = []
    pg = [rbox("Page", (5.0, 0.5, 5.8), (0, 0, 0), C["white"], 0.15),
          rbox("Head", (5.02, 0.56, 1.35), (0, -0.02, 2.2), C["red"], 0.1),
          rbox("Under", (5.0, 0.3, 5.8), (0.15, 0.4, -0.15), C["cream_d"], 0.1)]
    for x in (-1.5, 0, 1.5):
        pg.append(torus(f"Ring{x}", 0.32, 0.09, C["grey"], (x, -0.4, 2.95), segs=10, rsegs=4))
    pg.append(flame((0, -0.5, -0.9), 1.45, "fl"))
    parts.append(group(pg, rot=(0, 0, 5), name="page"))
    sh = [(0, 1.3), (1.1, 0.95), (1.0, -0.2), (0, -1.3), (-1.0, -0.2), (-1.1, 0.95)]
    parts.append(prism("Shield", sh, 0.5, C["blue"], (2.4, -1.2, -2.3), bevel_w=0.1))
    parts.append(prism("ShieldIn", [(x * 0.62, z * 0.62) for x, z in sh], 0.5, C["blue_l"], (2.4, -1.5, -2.3), bevel_w=0.06))
    return parts


@icon("Store_LockBreak", view=(26, 14))
def store_lockbreak():
    parts = []
    body = rbox("LockBody", (3.0, 1.7, 2.3), (0, 0, 1.15), C["gold"], 0.2)
    gradient(body, C["gold_d"], C["gold_l"], 0.0, 2.3)
    parts.append(body)
    plate = rbox("Plate", (2.45, 0.14, 1.75), (0, -0.86, 1.15), C["red"], 0.07)
    parts.append(plate)
    parts.append(disc("KeyholeTop", 0.26, 0.1, C["ink"], (0, -0.97, 1.35), segs=10))
    parts.append(prism("KeyholeStem", [(-0.13, 0), (0.13, 0), (0.22, -0.55), (-0.22, -0.55)], 0.1, C["ink"], (0, -0.97, 1.3)))
    # shackle popped up and swung open round its left leg
    sh = [cylinder("LegL", 0.29, 1.5, (-0.95, 0, 0), C["grey"], segs=8),
          cylinder("LegR", 0.29, 0.6, (0.95, 0, 0.9), C["grey"], segs=8),
          torus("Shackle", 0.95, 0.29, C["grey"], (0, 0, 1.5), a0=0, a1=180, segs=18, rsegs=8)]
    parts.append(group(sh, (0, 0, 2.6), (0, 0, -40), 1.0, "shackle"))
    # a gold key in the lock
    key = [torus("KeyRing", 0.6, 0.2, C["gold"], (0, 0, 0), segs=16, rsegs=6),
           rbox("KeyShaft", (1.6, 0.3, 0.3), (1.35, 0, 0), C["gold"], 0.08),
           rbox("KeyBit", (0.3, 0.3, 0.6), (1.9, 0, -0.35), C["gold"], 0.06)]
    parts.append(group(key, (-1.1, -1.4, 1.2), (0, 0, 60), 1.0, "key"))
    for i, (x, z, s) in enumerate(((2.2, 4.4, 0.5), (-2.4, 3.6, 0.4))):
        parts.append(sparkle((x, -1.0, z), s, C["yellow"], f"S{i}"))
    return parts


@icon("Store_SummonBoss", view=(10, 10))
def store_summonboss():
    parts = [slime((150, 104, 206), "mischievous", (0, 0, 0), (0, 0, 8), 1.6)]
    parts.append(crown((0.25, 0.1, 3.75), 0.7, C["green"], "bosscrown"))
    bang = [rbox("Bar", (0.7, 0.5, 2.2), (0, 0, 1.25), C["red"], 0.2), blobc("Dot", 0.42, (0, 0, -0.35), C["red"])]
    parts.append(group(bang, (3.4, -1.0, 3.2), (0, 0, 0), 1.0, "bang"))
    return parts


# ---------------------------------------------------------------- Developer Products: carry trails
TRAIL_SLIME = (110, 225, 160)


def _trail(kind):
    def build():
        parts = [slime(TRAIL_SLIME, "happy", (1.6, 0, 0), (0, 0, 28), 1.25)]
        pts = [(-0.5 - i * 1.0, 0.6, 1.5 + i * 0.95 + 0.25 * math.sin(i * 1.7)) for i in range(4)]
        if kind == "sparkle":
            for i, (x, y, z) in enumerate(pts):
                parts.append(sparkle((x, y - 0.6, z + 0.2), 0.85 - i * 0.1, rgb(252, 204, 80) if i % 2 else rgb(255, 236, 150), f"T{i}"))
        elif kind == "goo_drip":
            for i, (x, y, z) in enumerate(pts):
                parts.append(drop((x, y - 0.6, z), 0.7 - i * 0.08, rgb(110, 226, 170) if i % 2 else rgb(150, 240, 200), f"T{i}"))
        elif kind == "hearts":
            for i, (x, y, z) in enumerate(pts):
                parts.append(prism(f"T{i}", heart_pts(0.75 - i * 0.08), 0.35, rgb(250, 150, 182) if i % 2 else rgb(255, 120, 170), (x, y - 0.6, z - 0.6), (0, (i - 2) * 10, 0), bevel_w=0.06))
        elif kind == "starfall":
            for i, (x, y, z) in enumerate(pts):
                c = rgb(255, 230, 120) if i % 2 == 0 else rgb(196, 166, 232)
                parts.append(prism(f"T{i}", star_pts(5, 0.9 - i * 0.1, 0.42 - i * 0.05), 0.35, c, (x, y - 0.6, z + 0.3), (0, i * 17, 0), bevel_w=0.06))
                parts.append(prism(f"Tail{i}", [(0, 0.12), (0, -0.12), (-1.0, 0.0)], 0.12, shade(c, 0.95), (x - 0.4, y - 0.4, z + 0.55)))
        elif kind == "rainbow":
            cols = [C["red"], C["orange"], C["yellow"], C["green"], C["blue"], C["purple"]]
            for k, c in enumerate(cols):
                line = [(0.8 - i * 0.9, 0.8, 2.5 - k * 0.5 + i * 0.75) for i in range(6)]
                parts.append(tube(f"Band{k}", line, [0.3, 0.3, 0.28, 0.26, 0.22, 0.15], c, segs=6))
        return parts
    build.__name__ = "trail_" + kind
    return build


for _t in ("sparkle", "goo_drip", "hearts", "starfall", "rainbow"):
    icon(f"Store_Trail_{_t}", view=FRONT)(_trail(_t))


# ---------------------------------------------------------------- Developer Products: deposit fanfares (still on Roblox)
def _fanfare(kind):
    def build():
        import random
        r = random.Random(7)
        parts = [slime((110, 225, 160), "happy", (0, 0, 0), (0, 0, 0), 1.0)]
        if kind == "confetti":
            cols = [C["blue"], C["pink"], C["yellow"], C["purple"], C["teal"], C["red"], C["orange"]]
            for i in range(22):
                a = math.radians(r.uniform(15, 165))
                d = r.uniform(2.2, 3.6)
                parts.append(box(f"Conf{i}", (0.55, 0.15, 0.28), (d * math.cos(a), -0.6, 1.5 + d * math.sin(a)), cols[i % len(cols)],
                                 rot=(r.uniform(0, 90), 0, r.uniform(0, 180))))
        elif kind == "heart_pop":
            for i, (x, z, s) in enumerate(((-2.4, 3.0, 0.6), (0.0, 4.4, 0.8), (2.4, 3.2, 0.6), (-1.3, 5.0, 0.4), (1.5, 5.2, 0.45))):
                parts.append(prism(f"H{i}", heart_pts(s), 0.35, C["pink"] if i % 2 else rgb(255, 110, 160), (x, -0.6, z - s), (0, (x * 6), 0), bevel_w=0.06))
        elif kind == "goo_splash":
            goo = rgb(110, 226, 170)
            parts.append(blobc("Puddle", 1.6, (0, 0, 0.05), goo, squash=(2.0, 1.4, 0.12)))
            for i in range(7):
                a = math.radians(20 + i * 23)
                d = 2.6
                parts.append(drop((d * math.cos(a), -0.6, 1.8 + d * math.sin(a)), 0.45 + 0.1 * (i % 2), goo if i % 2 else rgb(150, 240, 200), f"D{i}"))
        elif kind == "starburst":
            parts.append(prism("Burst", star_pts(12, 3.9, 2.6), 0.3, C["orange"], (0, 1.2, 2.2), bevel_w=0.08))
            parts.append(prism("Burst2", star_pts(12, 3.2, 2.2, 90 + 7.5), 0.3, C["yellow"], (0, 1.0, 2.2), bevel_w=0.08))
            for i, (x, z, s) in enumerate(((-3.2, 4.4, 0.5), (3.3, 4.0, 0.45), (0.2, 5.6, 0.4))):
                parts.append(sparkle((x, -0.6, z), s, C["white"], f"S{i}"))
        return parts
    build.__name__ = "fanfare_" + kind
    return build


for _f in ("confetti", "heart_pop", "goo_splash", "starburst"):
    icon(f"Store_Fanfare_{_f}", view=FRONT)(_fanfare(_f))
