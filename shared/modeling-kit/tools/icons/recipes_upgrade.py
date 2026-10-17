from recipes import icon, FRONT
from props import *


def crescent_pts(R=2.7, th=50, d=1.0, n=14):
    P = (R * math.cos(math.radians(th)), R * math.sin(math.radians(th)))
    r2 = math.hypot(P[0] - d, P[1])
    phi = math.degrees(math.atan2(P[1], P[0] - d))
    out = [(R * math.cos(math.radians(th + (360 - 2 * th) * i / n)), R * math.sin(math.radians(th + (360 - 2 * th) * i / n))) for i in range(n + 1)]
    a0, a1 = 360 - phi, phi
    out += [(d + r2 * math.cos(math.radians(a0 + (a1 - a0) * i / n)), r2 * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(1, n)]
    return out


@icon("Upgrade_Income", view=(14, 10))
def up_income():
    parts = []
    cookie = disc("Cookie", 2.7, 1.0, C["cream_d"], segs=18, bevel_w=0.2)
    gradient(cookie, rgb(206, 140, 70), rgb(240, 180, 100))
    parts.append(cookie)
    parts.append(disc("CookieTop", 2.5, 1.04, rgb(232, 170, 92), (0, -0.01, 0), segs=18))
    # goo cap with drips
    parts.append(blobc("Goo", 2.35, (0, -0.45, 0.85), C["green"], squash=(1.0, 0.32, 0.62)))
    for i, (x, ln) in enumerate(((-1.7, 1.2), (-0.5, 0.7), (0.9, 1.5), (2.0, 0.8))):
        parts.append(blobc(f"Drip{i}", 0.5, (x, -0.75, 0.55 - ln * 0.5), C["green"], squash=(0.8, 0.5, ln * 1.1)))
        parts.append(blobc(f"DripTip{i}", 0.38, (x, -0.8, 0.55 - ln), C["green_d"], squash=(1, 0.6, 1)))
    # eyes + smile on the cookie below the goo
    for s in (-1, 1):
        parts.append(blobc(f"Eye{s}", 0.42, (s * 0.85, -0.9, -0.45), C["ink"], squash=(1, 0.5, 1.2)))
        parts.append(blobc(f"Shine{s}", 0.13, (s * 0.85 - 0.12, -1.1, -0.3), C["white"], squash=(1, 0.5, 1)))
    parts.append(torus("Smile", 0.55, 0.11, C["ink"], (0, -0.95, -0.85), a0=205, a1=335, segs=18, rsegs=5))
    for i, (x, z) in enumerate(((-1.9, -0.9), (1.8, -1.0), (-0.1, -1.6), (2.0, 0.1))):
        parts.append(blobc(f"Chip{i}", 0.3, (x, -0.85, z), C["brown_d"], squash=(1, 0.5, 0.8), subdiv=1, flat=True))
    return [group(parts, rot=(0, 0, 0), name="cookie")]


@icon("Upgrade_CarrySpeed", view=(6, 8))
def up_carry():
    parts = []
    g, gd, gl = C["green"], C["green_d"], C["green_l"]
    parts.append(tube("UpperArm", [(3.9, 0, 0.9), (1.5, 0, 0.9), (-1.2, 0, 0.9)], [0.95, 1.15, 1.1], gd, segs=10))
    parts.append(blobc("Elbow", 1.3, (-1.4, 0, 0.9), g))
    parts.append(tube("Forearm", [(-1.4, 0, 0.9), (-1.5, 0, 2.6), (-1.3, 0, 4.0)], [1.2, 1.05, 0.95], g, segs=12))
    parts.append(blobc("Bicep", 1.45, (1.0, 0, 2.0), g, squash=(1.2, 1.0, 1.0)))
    parts.append(blobc("BicepShine", 0.4, (0.5, -1.1, 2.7), rgb(235, 255, 225), squash=(1.3, 0.4, 1.4)))
    parts.append(blobc("Fist", 1.35, (-1.3, 0, 5.3), gl, squash=(1, 0.95, 0.95)))
    for i in range(3):
        parts.append(box(f"Finger{i}", (0.1, 0.1, 0.8), (-1.85 + i * 0.55, -1.42, 5.45), gd))
    parts.append(blobc("Thumb", 0.5, (-0.25, -1.1, 4.7), gl, squash=(1, 0.8, 1.3)))
    parts.append(cylinder("Band", 1.2, 0.95, (-1.42, 0, 3.3), C["gold"], segs=12, r_top=1.12))
    parts.append(cylinder("BandRim", 1.24, 0.2, (-1.42, 0, 3.3), C["gold_d"], segs=12))
    for i, (x, z, ln) in enumerate(((2.2, 4.6, 1.5), (2.8, 5.7, 1.2), (2.4, 3.6, 1.0))):
        parts.append(prism(f"Speed{i}", [(0, 0), (ln, 0.12), (ln, -0.12)], 0.2, C["blue"], (x, 0, z)))
    return parts


@icon("Upgrade_OfflineCap", view=(14, 8))
def up_offline():
    parts = [disc("Night", 3.5, 0.5, C["night"], (0, 0.75, 0), segs=24, bevel_w=0.1)]
    gradient(parts[-1], rgb(40, 40, 110), rgb(86, 90, 180), -3.5, 3.5)
    moon = prism("Moon", crescent_pts(2.9, 50, 1.1), 0.8, C["gold"], (0.2, 0.15, 0), bevel_w=0.12)
    gradient(moon, C["gold"], C["gold_l"], -3, 3)
    parts.append(moon)
    parts.append(slime((120, 225, 150), "sleepy", (-0.5, -0.5, -1.7), (0, 0, -8), 0.5))
    for i, (x, z, s) in enumerate(((2.0, 2.2, 0.38), (2.5, 0.2, 0.28), (1.4, -1.6, 0.3))):
        parts.append(sparkle((x, -0.6, z), s, C["yellow"], f"Star{i}"))
    return parts


@icon("Upgrade_Luck", view=(0, 6))
def up_luck():
    parts = [clover(C["green"], 1.5, name="clv")]
    parts.append(coin("Medal", 1.0, 0.5, (0, -0.5, 0), (-90, 0, 0)))
    parts.append(text("$", 1.2, C["gold_d"], 0.12, (0, -0.8, 0)))
    parts.append(sparkle((2.6, -0.8, 2.7), 0.4, C["white"], "Gl"))
    return parts


@icon("Upgrade_RainMagnet", view=(0, 12))
def up_rain():
    o = run_model("rain_magnet")
    parts = [o]
    parts.append(sparkle((2.2, -0.4, 9.2), 0.7, C["blue_l"], "Snow"))
    parts[-1].rotation_euler = (0, 0, 0)
    for i in range(3):
        parts.append(prism(f"SnowArm{i}", [(-0.07, -0.55), (0.07, -0.55), (0.07, 0.55), (-0.07, 0.55)], 0.12, C["white"], (2.2, -0.45, 9.2), (0, 0, i * 60)))
    return parts
