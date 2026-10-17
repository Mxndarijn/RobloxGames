"""Shop gear icons (CONTRACT.md §27): consumables + the PvP tools (knockback gloves, traps, goo blasters, fun toys)."""
from recipes import icon, FRONT
from props import *

GOO = rgb(120, 235, 120)
GOO_D = rgb(70, 190, 90)


def puddle(name, r, pos, color, h=0.35):
    return blobc(name, r, pos, color, squash=(1, 1, h / r * 1.0))


def goo_drip(pos, s, color=GOO, name="Drip"):
    return drop(pos, s, color, name)


# ------------------------------------------------------------------ consumables
@icon("Consumable_MutationSpray", view=(24, 16))
def mutation_spray():
    parts = []
    glass = rgb(206, 232, 250)
    prof = [(0, 0), (1.5, 0), (1.8, 0.3), (1.8, 3.2), (1.5, 3.5), (0.8, 3.7), (0, 3.7)]
    parts.append(lathe_obj("Bottle", prof, lambda i, k, z: mix(C["purple_d"], GOO, min(1, z / 3.2)), segs=16))
    smooth(parts[-1])
    parts.append(disc("Label", 1.2, 0.14, C["cream"], (0, -1.78, 1.5), segs=14))
    parts.append(text("DNA", 0.8, C["purple_d"], 0.12, (0, -1.9, 1.5)))
    parts.append(cylinder("Neck", 0.8, 0.7, (0, 0, 3.6), C["grey"], segs=10))
    parts.append(rbox("Head", (1.7, 1.2, 0.9), (0.15, 0, 4.6), C["purple"], 0.2))
    parts.append(cylinder("Nozzle", 0.28, 1.2, (-0.7, -0.1, 4.6), C["grey_d"], segs=8, rot=(0, -90, 0)))
    parts.append(rbox("Trigger", (0.4, 0.5, 1.2), (1.1, 0, 3.9), C["purple_d"], 0.08, rot=(0, -20, 0)))
    parts.append(blobc("Shine", 0.2, (-1.2, -1.2, 2.2), rgb(255, 255, 255), squash=(0.6, 0.4, 1.9)))
    for i, (x, z, r, c) in enumerate(((-2.0, 4.7, 0.3, GOO), (-2.8, 5.3, 0.22, C["purple"]), (-3.1, 4.3, 0.2, GOO), (-2.4, 3.8, 0.17, C["purple_l"]))):
        parts.append(blobc(f"Mist{i}", r, (x, -0.2, z), c))
    for i, (x, z, s) in enumerate(((-3.3, 6.0, 0.5), (-1.5, 6.4, 0.35), (-3.6, 3.2, 0.3))):
        parts.append(sparkle((x, -0.5, z), s, C["gold_l"] if i != 1 else C["white"], f"S{i}"))
    return parts


@icon("Consumable_LuckPotion", view=(22, 16))
def luck_potion():
    p = potion(liquid=C["green"], glow=False, rot=(0, 0, -12))
    parts = [p, disc("Badge", 1.15, 0.14, C["cream"], (0.35, -2.0, 1.45), segs=14, rot=(0, 0, 0)),
             clover(C["green_d"], 0.5, (0.35, -2.2, 1.45))]
    for i, (x, z, s) in enumerate(((-1.8, 5.2, 0.4), (1.9, 5.8, 0.3), (0.2, 6.5, 0.32))):
        parts.append(sparkle((x, -0.5, z), s, C["gold_l"], f"S{i}"))
    return parts


@icon("Consumable_WeatherTotem", view=(20, 16))
def weather_totem():
    parts = []
    parts.append(rbox("Base", (3.4, 3.0, 0.8), (0, 0, 0.4), C["stone_d"], 0.18))
    for i, (z, c) in enumerate(((0.8, C["stone"]), (2.5, rgb(184, 172, 160)), (4.2, C["stone"]))):
        parts.append(rbox(f"Seg{i}", (2.5, 2.3, 1.7), (0, 0, z + 0.85), c, 0.2))
    # carved faces
    parts.append(prism("Eye1", [(-0.5, 0.1), (0.5, 0.1), (0, 0.5)], 0.12, C["ink"], (-0.0, -1.2, 5.3)))
    parts.append(rbox("Mouth", (1.2, 0.12, 0.3), (0, -1.2, 4.6), C["ink"], 0.04))
    parts.append(prism("Zig", [(-0.9, 0), (-0.3, 0.5), (0.3, 0), (0.9, 0.5), (0.9, 0.2), (0.3, -0.3), (-0.3, 0.2), (-0.9, -0.3)], 0.12, C["blue"], (0, -1.2, 2.5)))
    parts.append(disc("Sun", 0.5, 0.12, C["gold"], (0, -1.2, 0.85 + 0.0), segs=10))
    # cloud + sun on top
    parts.append(blobc("Sun", 0.85, (-0.75, -0.2, 7.2), C["gold"]))
    for i in range(8):
        a = math.radians(i * 45)
        parts.append(prism(f"Ray{i}", [(-0.12, 0.95), (0.12, 0.95), (0, 1.5)], 0.2, C["gold_l"], (-0.75, -0.2, 7.2), rot=(0, -i * 45, 0)))
    for i, (x, z, r) in enumerate(((0.4, 6.9, 0.8), (1.3, 7.2, 0.95), (2.2, 6.9, 0.75), (1.3, 6.55, 0.9))):
        parts.append(blobc(f"Cloud{i}", r, (x, -0.5, z), C["white"], squash=(1, 0.8, 0.9)))
    for i, (x, z) in enumerate(((0.8, 5.5), (1.6, 5.7), (2.3, 5.4))):
        parts.append(goo_drip((x, -0.6, z), 0.2, C["blue_l"], f"Rain{i}"))
    return parts


# ------------------------------------------------------------------ knockback gloves
GLOVE_TIERS = {
    1: (C["green"], C["green_d"]),
    2: (C["blue"], C["blue_d"]),
    3: (C["purple"], C["purple_d"]),
    4: (C["orange"], C["orange_d"]),
    5: (C["gold"], C["gold_d"]),
}


def glove(tier):
    col, dark = GLOVE_TIERS[tier]
    parts = []
    parts.append(rbox("Fist", (3.4, 2.8, 3.0), (0, 0, 3.0), col, 0.55))
    gradient(parts[-1], dark, col, 1.5, 4.5)
    for i, x in enumerate((-1.2, -0.4, 0.4, 1.2)):
        parts.append(rbox(f"Knuckle{i}", (0.8, 0.5, 1.4), (x, -1.45, 3.7), col, 0.22))
        parts.append(rbox(f"Crease{i}", (0.06, 0.1, 1.0), (x + 0.4, -1.72, 3.7), dark, 0.02))
    parts.append(rbox("Thumb", (1.0, 1.5, 1.8), (-2.0, -0.4, 2.4), col, 0.35, rot=(0, 0, 20)))
    parts.append(cylinder("Cuff", 1.35, 1.5, (0, 0, 0.0), C["white"], segs=14, r_top=1.2))
    parts.append(cylinder("CuffBand", 1.4, 0.4, (0, 0, 1.2), dark, segs=14))
    if tier >= 2:
        parts.append(rbox("Stripe", (3.45, 0.1, 0.3), (0, -1.43, 2.2), C["white"], 0.04))
    if tier == 3:
        for i, (x, z, s) in enumerate(((-2.6, 5.4, 0.55), (2.4, 5.0, 0.45), (2.7, 2.4, 0.35))):
            parts.append(sparkle((x, -1.0, z), s, C["purple_l"] if i else C["white"], f"S{i}"))
    if tier == 4:
        parts.append(bolt(C["yellow"], 0.9, 0.3, (0.3, -1.65, 3.0)))
        parts.append(bolt(C["yellow"], 0.7, 0.3, (3.0, -0.8, 5.3)))
        parts.append(bolt(C["yellow"], 0.55, 0.3, (-3.0, -0.8, 5.6)))
    if tier == 5:
        c = [rbox("CrownBase", (2.2, 0.8, 0.45), (0, 0, 5.2), C["gold_l"], 0.1)]
        for i, x in enumerate((-0.9, 0, 0.9)):
            c.append(cone(f"Pt{i}", 0.4, 0.9, (x, 0, 5.4), C["gold_l"], segs=4))
            c.append(blobc(f"Jewel{i}", 0.17, (x, -0.42, 5.45), [C["red"], C["blue"], C["green"]][i]))
        parts += c
        for i, (x, z, s) in enumerate(((-2.7, 5.6, 0.45), (2.7, 4.2, 0.4))):
            parts.append(sparkle((x, -1.0, z), s, C["gold_l"], f"S{i}"))
    return parts


for _t, _n in enumerate(("Bonk", "Bounce", "Boom", "Thunder", "Royal"), 1):
    icon(f"Pvp_KnockGlove{_t}", view=(18, 16))(lambda t=_t: glove(t))


# ------------------------------------------------------------------ traps
def jaws(n, w, col, z0=0.0, y=0.0, size=0.8):
    out = []
    for i in range(n):
        x = -w / 2 + w * (i + 0.5) / n
        out.append(cone(f"Tooth{i}", size * 0.5, size * 1.4, (x, y, z0), col, segs=4))
    return out


@icon("Pvp_GooTrap1", view=(15, 28))
def goo_trap1():
    parts = [puddle("Puddle", 3.2, (0, 0, 0.1), GOO, 1.0), puddle("Puddle2", 2.0, (0.3, -0.1, 0.5), rgb(160, 250, 150), 0.8)]
    parts.append(puddle("Bit", 1.0, (2.9, -1.8, 0.1), GOO, 0.5))
    parts.append(blobc("Bubble", 0.55, (-0.8, -0.5, 0.85), rgb(210, 255, 210)))
    parts.append(blobc("Bubble2", 0.3, (0.9, 0.3, 0.9), rgb(210, 255, 210)))
    parts.append(goo_drip((-2.2, -1.5, 0.7), 0.4, GOO_D, "Dr"))
    parts.append(sparkle((2.0, -1.5, 2.3), 0.4, C["white"], "S0"))
    return parts


@icon("Pvp_GooTrap2", view=(15, 30))
def goo_trap2():
    parts = [puddle("Puddle", 3.4, (0, 0, 0.1), GOO, 1.0)]
    parts.append(cylinder("Plate", 2.4, 0.35, (0, 0, 0.4), C["grey_d"], segs=16))
    parts.append(cylinder("PlateTop", 1.9, 0.2, (0, 0, 0.7), C["red"], segs=16))
    for i in range(8):
        a = math.radians(i * 45 + 22)
        parts.append(cone(f"Spike{i}", 0.38, 1.6, (2.3 * math.cos(a), 2.3 * math.sin(a), 0.4), C["grey"], segs=5))
    parts.append(cone("Mid", 0.5, 1.5, (0, 0, 0.8), C["red_d"], segs=5))
    parts.append(goo_drip((-2.6, -1.6, 0.5), 0.35, GOO_D, "Dr"))
    return parts


JAW_SX, JAW_SZ = 0.85, 1.5  # jaws are tall ellipses (taller than wide) so the trap fills the frame height


def _trap_jaw(sgn, R, tilt, name, drips=None):
    """Half-ring jaw (arch in XZ, hinged on the X axis) lined with big inward-pointing teeth, tilted open.
    Appends world-space positions of the tooth tips to `drips` (for goo drips hanging off them)."""
    METAL, METAL_D = rgb(70, 76, 96), rgb(40, 44, 62)
    parts = [torus(name + "Rim", R, 0.7, METAL, a0=0, a1=180, segs=36, rsegs=8),
             torus(name + "Rim2", R - 0.7, 0.4, METAL_D, a0=0, a1=180, segs=36, rsegs=6)]
    n = 5
    for i in range(n):
        a = math.radians(18 + (144 * i) / (n - 1))
        rr = R - 0.7
        tx, tz = rr * math.cos(a), rr * math.sin(a)
        phi = math.degrees(math.atan2(-math.cos(a), -math.sin(a)))
        parts.append(cone(f"{name}T{i}", 1.0, 2.2, (tx, 0, tz), C["white"], segs=4, rot=(0, phi, 0)))
        if drips is not None:
            L = 1.5
            lx, lz = (tx - math.cos(a) * L) * JAW_SX, (tz - math.sin(a) * L) * JAW_SZ
            t = math.radians(tilt * sgn)
            drips.append((lx, -lz * math.sin(t), lz * math.cos(t)))
    parts.append(cylinder(name + "PinL", 0.6, 1.0, (-R, 0, 0), METAL_D, segs=8, rot=(0, 90, 0)))
    parts.append(cylinder(name + "PinR", 0.6, 1.0, (R, 0, 0), METAL_D, segs=8, rot=(0, 90, 0)))
    inner = group(parts, (0, 0, 0), scale=(JAW_SX, 1.0, JAW_SZ), name=name + "S")
    return group([inner], (0, 0, 0), rot=(tilt * sgn, 0, 0), name=name)


@icon("Pvp_GooTrap3", view=(12, 38))
def goo_trap3():
    R = 4.2
    parts = [puddle("Puddle", 5.0, (0, -0.2, 0.1), GOO, 0.9), puddle("Puddle2", 3.4, (-1.2, -0.8, 0.3), rgb(160, 250, 150), 0.8)]
    parts.append(puddle("Puddle3", 1.5, (4.4, -2.6, 0.1), GOO, 0.6))
    parts.append(cylinder("Base", 3.6, 0.5, (0, 0, 0.3), rgb(40, 44, 62), segs=20))
    parts.append(cylinder("Plate", 2.2, 0.3, (0, 0, 0.7), C["red_d"], segs=16))
    parts.append(blobc("Eye", 1.3, (0, -0.1, 0.9), rgb(255, 120, 30), squash=(1, 1, 0.8)))
    parts.append(blobc("EyeCore", 0.7, (0, -0.5, 1.3), rgb(255, 235, 120), squash=(1, 0.8, 1)))
    tips = []
    parts.append(_trap_jaw(1, R, FRONT_TILT, "JawF"))
    parts.append(_trap_jaw(-1, R, BACK_TILT, "JawB", tips))
    # goo drips hanging off the front jaw's tooth tips, plus puddle bubbles and glints
    for i, (x, y, z) in enumerate(tips):
        d = goo_drip((x, y, z), 0.6 + 0.12 * (i % 2), GOO if i % 2 else GOO_D, f"Dr{i}")
        d.rotation_euler.x = math.radians(180)
        parts.append(d)
    for i, (x, y, s) in enumerate(((-3.2, -3.4, 0.45), (3.0, -3.4, 0.32), (0.8, -3.6, 0.28))):
        parts.append(blobc(f"Bub{i}", s, (x, y, 0.5 + s), rgb(210, 255, 210)))
    for i, (x, z, s) in enumerate(((-4.3, 8.0, 0.6), (4.4, 6.5, 0.45))):
        parts.append(sparkle((x, -1.0, z), s, rgb(255, 130, 40) if i == 0 else C["white"], f"S{i}"))
    return parts


FRONT_TILT, BACK_TILT = 70, 14


# ------------------------------------------------------------------ blasters
def gun(tier):
    sz = {1: 1.0, 2: 1.3, 3: 1.65}[tier]
    body_c = {1: C["teal"], 2: C["blue"], 3: C["purple"]}[tier]
    dark = shade(body_c, 0.75)
    parts = []
    parts.append(rbox("Body", (4.2 * sz, 1.5 * sz, 1.6 * sz), (0, 0, 2.0 * sz), body_c, 0.35 * sz))
    parts.append(cylinder("Barrel", 0.5 * sz, 2.2 * sz, (-1.8 * sz, 0, 2.2 * sz), C["grey"], segs=10, rot=(0, -90, 0)))
    parts.append(cylinder("Muzzle", 0.7 * sz, 0.5 * sz, (-3.9 * sz, 0, 2.2 * sz), dark, segs=10, rot=(0, -90, 0)))
    parts.append(rbox("Grip", (0.9 * sz, 1.0 * sz, 1.9 * sz), (1.3 * sz, 0, 0.55 * sz), dark, 0.22 * sz, rot=(0, 15, 0)))
    parts.append(rbox("Trigger", (0.25 * sz, 0.4 * sz, 0.8 * sz), (0.0, 0, 0.95 * sz), C["yellow"], 0.06))
    # goo tank on top
    tr = {1: 0.9, 2: 1.15, 3: 1.45}[tier]
    tank = blobc("Tank", tr, (0.4 * sz, 0, 3.6 * sz + tr * 0.4), GOO, squash=(1, 0.9, 1.05))
    parts.append(tank)
    parts.append(blobc("TankShine", tr * 0.22, (0.4 * sz - tr * 0.4, -tr * 0.7, 3.6 * sz + tr * 0.7), rgb(235, 255, 235)))
    parts.append(cylinder("Cap", 0.45 * sz, 0.35 * sz, (0.4 * sz, 0, 3.6 * sz + tr * 1.3), C["grey_d"], segs=8))
    # goo splat at muzzle
    parts.append(blobc("Squirt", 0.5 * sz, (-4.5 * sz, 0, 2.2 * sz), GOO))
    parts.append(goo_drip((-5.0 * sz, 0, 1.3 * sz), 0.3 * sz, GOO_D, "Dr"))
    if tier >= 2:
        parts.append(rbox("Stripe", (2.0 * sz, 1.55 * sz, 0.3 * sz), (0.5 * sz, 0, 1.6 * sz), C["white"], 0.06))
    if tier >= 3:
        parts.append(torus("Ring1", 0.8 * sz, 0.15 * sz, C["gold"], (-2.6 * sz, 0, 2.2 * sz), (0, 90, 0), segs=12, rsegs=5))
        parts[-1].rotation_euler = (0, 0, math.radians(90))
        parts.append(cylinder("Fin", 0.15, 1.4 * sz, (2.0 * sz, 0, 2.8 * sz), C["red"], segs=6))
        parts.append(sparkle((-4.4 * sz, -0.8, 4.2 * sz), 0.5, C["gold_l"], "S0"))
        parts.append(sparkle((2.8 * sz, -0.8, 4.8 * sz), 0.4, C["white"], "S1"))
    return parts


for _t in (1, 2, 3):
    icon(f"Pvp_GooBlaster{_t}", view=(-24, 16))(lambda t=_t: gun(t))


# ------------------------------------------------------------------ fun
CONF = [C["red"], C["blue"], C["yellow"], C["green"], C["pink"], C["purple"]]


@icon("Pvp_FunConfetti", view=(20, 18))
def confetti():
    parts = []
    tilt = 28  # cone leans toward +x, mouth up-left
    ax = Vector((math.sin(math.radians(-tilt)), 0, math.cos(math.radians(-tilt))))
    base = Vector((2.4, 0, 0.0))
    cn = cone("Cone", 1.8, 5.2, tuple(base), C["pink"], segs=12)
    cn.rotation_euler = (0, math.radians(-tilt), 0)
    gradient(cn, C["pink_d"], C["pink"])
    parts.append(cn)
    for i, (t, rr) in enumerate(((0.22, 1.4), (0.45, 1.05), (0.68, 0.72))):
        p = base + ax * 5.2 * t
        parts.append(cylinder(f"Band{i}", rr, 0.4, tuple(p - ax * 0.2), C["yellow"], segs=12, rot=(0, -tilt, 0)))
    tip = base + ax * 5.2
    parts.append(blobc("Tip", 0.3, tuple(tip), C["red"]))
    import random
    r = random.Random(7)
    for i in range(24):
        d = r.uniform(1.0, 4.2)
        a = math.radians(r.uniform(-20, 90))
        x, z = base.x + ax.x * 5.2 - d * math.cos(a) - 0.3, base.z + ax.z * 5.2 + d * math.sin(a) * 0.9 + 0.3
        parts.append(box(f"Conf{i}", (0.55, 0.15, 0.3), (x, -0.8 - r.random(), z), CONF[i % 6], rot=(0, r.uniform(0, 180), r.uniform(0, 180))))
    parts.append(sparkle((-2.6, -1, 5.6), 0.5, C["gold_l"], "S0"))
    return parts


@icon("Pvp_FunBalloon", view=(14, 12))
def balloon():
    parts = [blobc("Balloon", 2.3, (0, 0, 4.6), GOO, squash=(1, 1, 1.18))]
    gradient(parts[-1], GOO_D, rgb(170, 255, 160))
    parts.append(cone("Knot", 0.35, 0.5, (0, 0, 1.75), GOO_D, segs=6, rot=(180, 0, 0)))
    parts[-1].location.z = 2.0
    parts.append(blobc("Shine", 0.3, (-0.9, -1.8, 5.7), rgb(255, 255, 255), squash=(0.7, 0.4, 1.6)))
    pts = [(0, 0, 1.9), (0.5, 0, 1.2), (-0.4, 0, 0.5), (0.3, 0, -0.2)]
    parts.append(tube("String", pts, [0.06] * 4, C["ink"], segs=4))
    # goo splats on the balloon
    parts.append(puddle("SplatA", 0.7, (1.2, -2.0, 5.2), rgb(100, 210, 255), 0.3))
    parts.append(puddle("SplatB", 0.5, (-1.0, -2.1, 3.8), rgb(255, 130, 180), 0.3))
    parts.append(goo_drip((1.2, -2.2, 4.4), 0.2, rgb(100, 210, 255), "Dr"))
    parts.append(sparkle((2.9, -1, 6.6), 0.4, C["gold_l"], "S0"))
    return parts


@icon("Pvp_FunBubbles", view=(16, 16))
def bubbles():
    parts = []
    parts.append(cylinder("Handle", 0.35, 4.4, (0, 0, 0), C["pink"], segs=8))
    parts.append(cylinder("Grip", 0.5, 1.4, (0, 0, 0), C["pink_d"], segs=8))
    parts.append(torus("Loop", 1.45, 0.24, C["pink"], (0, 0, 5.9), (0, 0, 0), segs=20, rsegs=6))
    parts.append(disc("Film", 1.25, 0.05, rgb(190, 230, 255), (0, 0, 5.9), segs=20))
    parts[-1].name = "GlassClear_Film"
    for i, (x, z, r, c) in enumerate(((2.4, 7.0, 0.95, C["blue_l"]), (3.4, 5.0, 0.6, C["pink"]), (1.4, 8.2, 0.5, C["purple_l"]), (-2.4, 7.6, 0.7, C["teal"]))):
        b = blobc(f"GlassBubble{i}", r, (x, -0.5, z), c)
        parts.append(b)
        parts.append(blobc(f"Glint{i}", r * 0.2, (x - r * 0.4, -0.5 - r * 0.8, z + r * 0.4), rgb(255, 255, 255), squash=(1, 0.5, 1)))
    return parts


@icon("Pvp_FunBouncePad", view=(15, 26))
def bounce_pad():
    parts = [cylinder("Base", 3.6, 0.9, (0, 0, 0), C["blue_d"], segs=16)]
    parts.append(cylinder("Ring", 3.7, 0.4, (0, 0, 0.9), C["gold"], segs=16))
    parts.append(cylinder("Top", 3.2, 0.7, (0, 0, 1.2), C["red"], segs=16, r_top=3.0))
    parts.append(torus("Mark", 1.6, 0.15, C["white"], (0, 0, 1.95), (90, 0, 0), segs=16, rsegs=4))
    parts[-1].rotation_euler = (0, 0, 0)
    parts[-1].location = (0, 0, 1.95)
    parts.pop()
    parts.append(prism("ArrowUp", [(0, 1.3), (1.1, 0), (0.4, 0), (0.4, -1.1), (-0.4, -1.1), (-0.4, 0), (-1.1, 0)], 0.4, C["white"], (0, -0.2, 3.3), rot=(0, 0, 0), bevel_w=0.08))
    for i, (x, z) in enumerate(((-2.6, 4.4), (2.7, 5.0), (2.0, 7.0))):
        parts.append(prism(f"Chev{i}", [(-0.7, 0), (0, 0.5), (0.7, 0), (0.7, -0.3), (0, 0.2), (-0.7, -0.3)], 0.25, C["yellow"], (x, -0.4, z)))
    parts.append(sparkle((-2.4, -0.8, 6.6), 0.45, C["gold_l"], "S0"))
    return parts


@icon("Pvp_FunSqueaky", view=(22, 18))
def squeaky():
    parts = []
    parts.append(cylinder("Handle", 0.38, 5.2, (0, 0, 0), C["brown"], segs=8))
    parts.append(cylinder("Grip", 0.5, 1.5, (0, 0, 0), C["red"], segs=8))
    parts.append(blobc("Pommel", 0.55, (0, 0, 0.0), C["red_d"]))
    head = cylinder("Head", 1.4, 3.8, (-1.9, 0, 5.6), C["yellow"], segs=14, rot=(0, 90, 0))
    gradient(head, C["gold"], C["yellow"])
    parts.append(head)
    for s_ in (-1, 1):
        parts.append(cylinder(f"End{s_}", 1.55, 0.45, (-1.9 if s_ < 0 else 1.45, 0, 5.6), C["red"], segs=14, rot=(0, -90 if s_ < 0 else 90, 0)))
    parts.append(blobc("Squeak", 0.55, (0, -1.35, 6.9), C["white"], squash=(1, 0.5, 0.8)))
    parts.append(prism("Zap1", [(0, 0.5), (0.25, 0), (0.6, 0.2), (0.3, -0.5)], 0.2, C["orange"], (3.3, -0.8, 7.0)))
    parts.append(prism("Zap2", [(0, 0.5), (0.25, 0), (0.6, 0.2), (0.3, -0.5)], 0.2, C["orange"], (3.6, -0.8, 5.0)))
    parts.append(text("!", 1.4, C["red"], 0.2, (-3.6, -0.8, 7.4)))
    return parts


@icon("Pvp_FunHatLauncher", view=(20, 18))
def hat_launcher():
    parts = []
    t = 38
    ax = Vector((math.sin(math.radians(t)), 0, math.cos(math.radians(t))))
    base = Vector((-3.0, 0, 1.3))
    tube = cylinder("Tube", 1.05, 4.2, tuple(base), C["red"], segs=14, r_top=1.35, rot=(0, t, 0))
    gradient(tube, C["red_d"], C["red"])
    parts.append(tube)
    parts.append(cylinder("Ring", 1.5, 0.45, tuple(base + ax * 3.9), C["gold"], segs=14, rot=(0, t, 0)))
    parts.append(cylinder("Ring2", 1.2, 0.3, tuple(base + ax * 1.4), C["gold"], segs=14, rot=(0, t, 0)))
    parts.append(rbox("Stand", (3.8, 2.4, 0.8), (-2.6, 0, 0.4), C["grey_d"], 0.2))
    for s_ in (-1, 1):
        parts.append(cylinder(f"Wheel{s_}", 0.85, 0.4, (-2.6 + s_ * 1.0, -1.2, 0.8), C["ink"], segs=10, rot=(90, 0, 0)))
    hat = [cylinder("HatBrim", 1.5, 0.22, (0, 0, 0), C["ink"], segs=14), cylinder("HatTop", 1.0, 1.5, (0, 0, 0.2), C["ink"], segs=14),
           cylinder("HatBand", 1.03, 0.3, (0, 0, 0.35), C["purple"], segs=14)]
    parts.append(group(hat, (3.2, -0.2, 6.6), (-12, 8, 25), 1.0, "hat"))
    parts.append(slime((110, 225, 130), "happy", (3.9, 0, 2.0), (0, 0, 0), 0.75))
    for i, (x, z) in enumerate(((0.9, 5.7), (1.8, 6.1), (2.4, 5.2))):
        parts.append(blobc(f"Puff{i}", 0.55 - i * 0.1, (x, -0.8, z), C["white"], squash=(1, 0.7, 0.9)))
    parts.append(sparkle((5.4, -1, 7.4), 0.5, C["gold_l"], "S0"))
    return parts


@icon("Pvp_FunDanceBomb", view=(15, 18))
def dance_bomb():
    parts = []
    parts.append(blobc("Bomb", 3.0, (0, 0, 3.0), rgb(210, 214, 230), subdiv=3))
    # mirror tiles: coloured cubes on the sphere
    import random
    r = random.Random(3)
    cols = [C["blue_l"], C["pink"], C["white"], C["purple_l"], C["teal"], C["gold_l"]]
    for i in range(60):
        v = Vector((r.uniform(-1, 1), r.uniform(-1, 0.4), r.uniform(-1, 1)))
        if v.length < 0.2:
            continue
        v.normalize()
        pos = (v.x * 2.95, v.y * 2.95, 3.0 + v.z * 2.95)
        b = box(f"Tile{i}", (0.95, 0.95, 0.25), (0, 0, 0), cols[i % 6])
        q = v.to_track_quat("Z", "Y")
        b.rotation_euler = q.to_euler()
        b.location = pos
        parts.append(b)
    parts.append(cylinder("Cap", 0.55, 0.5, (0, 0, 6.0), C["grey_d"], segs=8))
    pts = [(0, 0, 6.4), (0.6, 0, 7.2), (-0.2, 0, 7.8), (0.7, 0, 8.4)]
    parts.append(tube("Fuse", pts, [0.12] * 4, C["brown_d"], segs=5))
    parts.append(blobc("Spark", 0.4, (0.9, 0, 8.6), C["orange"]))
    parts.append(sparkle((1.0, -0.4, 8.9), 0.65, C["yellow"], "FuseS"))
    for i, (x, z, s) in enumerate(((-3.9, 6.4, 0.5), (4.0, 5.6, 0.45), (-4.2, 1.6, 0.35))):
        parts.append(sparkle((x, -0.8, z), s, C["gold_l"] if i != 1 else C["white"], f"S{i}"))
    parts.append(prism("Note", heart_pts(0.9), 0.3, C["pink"], (4.0, -0.8, 2.0), bevel_w=0.05))
    return parts


@icon("Pvp_FunFireworks", view=(14, 14))
def fireworks():
    parts = []
    for i, (x, h, c) in enumerate(((-1.5, 3.6, C["red"]), (0.2, 4.4, C["blue"]), (1.9, 3.4, C["green"]))):
        parts.append(cylinder(f"Tube{i}", 0.7, h, (x, 0, 0), c, segs=10))
        parts.append(cylinder(f"Band{i}", 0.74, 0.35, (x, 0, h * 0.4), C["white"], segs=10))
        parts.append(cone(f"Tip{i}", 0.7, 0.9, (x, 0, h), shade(c, 0.8), segs=10))
        parts.append(cylinder(f"Stick{i}", 0.1, 0.9, (x, 0, h + 0.8), C["brown"], segs=5))
    # burst
    cx, cz = 0.4, 8.2
    cols = [C["gold_l"], C["pink"], C["blue_l"], C["green_l"], C["orange"], C["purple_l"]]
    for i in range(10):
        a = math.radians(i * 36)
        parts.append(prism(f"Ray{i}", [(-0.13, 0.9), (0.13, 0.9), (0.0, 2.8)], 0.25, cols[i % 6], (cx, -0.3, cz), rot=(0, -i * 36, 0)))
        parts.append(blobc(f"Dot{i}", 0.3, (cx + 3.3 * math.sin(a), -0.3, cz + 3.3 * math.cos(a)), cols[(i + 2) % 6]))
    parts.append(sparkle((cx, -0.6, cz), 0.9, C["white"], "Core"))
    parts.append(goo_drip((cx + 0.1, -0.5, cz - 4.1), 0.35, GOO, "GooDrop"))
    return parts
