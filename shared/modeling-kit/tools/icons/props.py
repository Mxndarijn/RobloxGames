"""Reusable props for several icons (padlock, potion, coins, clover, arrows ...)."""
import math
from helpers import *


def bev(o, w=0.12, seg=1):
    bevel(o, w, seg, 50)
    return o


def rbox(name, size, pos, color, w=0.14, rot=(0, 0, 0), top=None):
    o = box(name, size, pos, color, rot)
    if top is not None:
        gradient(o, color, top, pos[2] - size[2] / 2, pos[2] + size[2] / 2) if False else None
    return bev(o, w, 1)


def padlock(face=None, pos=(0, 0, 0), rot=(0, 0, 0), scale=1.0, shackle_up=1.0):
    face = face or C["blue"]
    parts = []
    body = rbox("LockBody", (3.0, 1.7, 2.3), (0, 0, 1.15), C["gold"], 0.2)
    gradient(body, C["gold_d"], C["gold_l"], 0.0, 2.3)
    parts.append(body)
    plate = rbox("Plate", (2.45, 0.14, 1.75), (0, -0.86, 1.15), face, 0.07)
    gradient(plate, shade(face, 0.8), shade(face, 1.15), 0.28, 2.0)
    parts.append(plate)
    parts.append(disc("KeyholeTop", 0.26, 0.1, C["ink"], (0, -0.97, 1.35), segs=10))
    parts.append(prism("KeyholeStem", [(-0.13, 0), (0.13, 0), (0.22, -0.55), (-0.22, -0.55)], 0.1, C["ink"], (0, -0.97, 1.3)))
    zc = 2.3
    h = 0.55 * shackle_up
    for s in (-1, 1):
        parts.append(cylinder(f"ShackleLeg{s}", 0.29, h + 0.05, (s * 0.95, 0, zc - 0.05), C["grey"], segs=8))
    parts.append(torus("Shackle", 0.95, 0.29, C["grey"], (0, 0, zc + h), a0=0, a1=180, segs=18, rsegs=8))
    parts[-1].data.update()
    return group(parts, pos, rot, scale, "padlock")


def potion(label=None, liquid=None, label_color=None, bolt=False, pos=(0, 0, 0), rot=(0, 0, -20), scale=1.0, glow=True):
    liquid = liquid or C["yellow"]
    parts = []
    glass = rgb(206, 232, 250)
    prof = [(0, 0), (1.15, 0), (1.75, 0.45), (2.05, 1.3), (1.9, 2.2), (1.3, 2.95), (0.72, 3.4), (0.7, 4.3), (0, 4.3)]

    def col(i, k, z):
        if z > 2.95:
            return glass
        return mix(shade(liquid, 0.82), liquid, min(1, z / 2.2))
    parts.append(lathe_obj("Flask", prof, col, segs=16))
    parts.append(lathe_obj("Lip", [(0, 4.25), (0.95, 4.25), (0.95, 4.65), (0.72, 4.7), (0, 4.7)], glass, segs=14))
    parts.append(cylinder("Cork", 0.62, 0.8, (0, 0, 4.65), C["brown"], segs=8, r_top=0.52))
    gradient(parts[-1], C["brown_d"], C["brown"])
    if label or bolt:
        parts.append(disc("Label", 1.12, 0.14, C["cream"], (0, -1.99, 1.4), segs=14))
        if bolt:
            parts.append(prism("LabelBolt", [(0.5 * x, 0.5 * z) for x, z in BOLT], 0.14, C["orange"], (0, -2.1, 1.4), bevel_w=0.04))
        if label:
            parts.append(text(label, 1.0 if len(label) < 4 else 0.8, label_color or C["red_d"], 0.12, (0, -2.12, 1.4)))
    parts.append(blobc("Shine", 0.2, (-1.2, -1.2, 2.2), rgb(255, 255, 255), squash=(0.6, 0.4, 1.9)))
    g = group(parts, pos, rot, scale, "potion")
    if glow:
        for i, (x, y, z, s) in enumerate(((-1.5, -0.4, 5.6, 0.34), (1.7, -0.3, 6.1, 0.26), (0.1, -0.9, 6.7, 0.3))):
            sp = sparkle((x, y, z), s, C["gold_l"], f"Spark{i}")
            sp.parent = None
            parts.append(sp)
        return group([g] + parts[-3:], name="potion_all")
    return g


BOLT = [(0.2, 1.6), (-0.9, -0.1), (-0.1, -0.1), (-0.4, -1.6), (0.9, 0.3), (0.1, 0.3), (0.7, 1.6)]


def bolt(color=None, s=1.0, depth=0.5, pos=(0, 0, 0), rot=(0, 0, 0)):
    return prism("Bolt", [(x * s, z * s) for x, z in BOLT], depth, color or C["yellow"], pos, rot, bevel_w=0.08 * s)


def coin(name, r, h, pos, rot=(0, 0, 0), face=None, mark=None, segs=16):
    """A gold coin standing on its edge or flat: an axis-Z cylinder with a darker rim and a lighter inset."""
    parts = [cylinder(name + "Rim", r, h, (0, 0, 0), C["gold_d"], segs=segs)]
    parts.append(cylinder(name + "Face", r * 0.82, h * 1.12, (0, 0, -h * 0.06), face or C["gold"], segs=segs))
    gradient(parts[-1], C["gold"], C["gold_l"])
    if mark:
        parts.append(text(mark, r * 1.3, rgb(160, 92, 12), h * 0.5, (0, 0, h * 1.05), rot=(-90, 0, 0)))
    return group(parts, pos, rot, 1.0, name)


def coin_pile(mark="$", top_tilt=True, extra=0):
    parts = []
    z = 0.0
    for i, (x, y, r) in enumerate(((0, 0, 1.9), (0.1, 0.1, 1.75), (-0.1, 0, 1.55))):
        parts.append(coin(f"C{i}", r, 0.5, (x, y, z), (0, 0, i * 25)))
        z += 0.5
    parts.append(coin("Lean", 1.35, 0.42, (-0.1, -0.2, z + 0.5), (-55, 0, 0), mark=mark))
    parts.append(coin("Side1", 1.1, 0.4, (2.15, -0.5, 0.2), (0, 0, 0)))
    parts.append(coin("Side2", 1.0, 0.4, (-2.3, -0.7, 0.2), (0, 0, 0)))
    parts.append(coin("Side3", 0.95, 0.38, (1.0, -2.0, 0.19), (0, 0, 0)))
    for i in range(extra):
        parts.append(coin(f"X{i}", 1.0, 0.38, (-1.6 + i * 1.5, -3.3 - (i % 2) * 0.3, 0.19), (0, 0, 0)))
    return group(parts, name="coinpile")


def clover(color=None, size=1.0, pos=(0, 0, 0), rot=(0, 0, 0), flat=True, name="clover"):
    """Four-leaf clover lying in the XZ plane (faces -Y)."""
    color = color or C["green"]
    parts = []
    hp = heart_pts(1.0)
    for i in range(4):
        a = 45 + i * 90
        ang = math.radians(a)
        pts = [(x * math.cos(math.radians(a - 90 + 180 + 0)) - z * math.sin(math.radians(a - 90 + 180)),
                x * math.sin(math.radians(a - 90 + 180)) + z * math.cos(math.radians(a - 90 + 180))) for x, z in hp]
        # heart tip at origin pointing out: heart_pts has its tip at the bottom (0, -1.0 * k)
        c = shade(color, 1.0 - 0.06 * (i % 2))
        pts = rot_pts(hp, a + 90)
        pts = [(x + 0.0, z + 0.0) for x, z in pts]
        parts.append(prism(f"Leaf{i}", [(x * size, z * size) for x, z in pts], 0.45 * size, c, bevel_w=0.07 * size))
    parts.append(cylinder("Stem", 0.14 * size, 1.6 * size, (0.18 * size, 0, -1.9 * size), C["green_d"], segs=6, rot=(0, 18, 0)))
    return group(parts, pos, rot, 1.0, name)


def heart_pts(s=1.0, n=20):
    """Heart outline, tip at (0,0), lobes up, height ~2.1*s."""
    out = []
    for i in range(n):
        t = math.tau * i / n
        x = 16 * math.sin(t) ** 3
        z = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        out.append((x / 16 * s, (z + 17) / 16 * s))
    return out[::-1]


def rot_pts(pts, deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [(x * c - z * s, x * s + z * c) for x, z in pts]


def circ_arrow(color=None, R=1.8, r=0.42, a0=35, a1=320, pos=(0, 0, 0), rot=(0, 0, 0), name="arrow"):
    """Circular (rebirth) arrow in the XZ plane: arc + triangular head at the end (counter-clockwise)."""
    color = color or C["green"]
    parts = [torus("Arc", R, r, color, a0=a0, a1=a1, segs=22, rsegs=6)]
    ang = math.radians(a1)
    tip = (R * math.cos(ang), R * math.sin(ang))
    tx, tz = -math.sin(ang), math.cos(ang)  # tangent (ccw)
    nx, nz = math.cos(ang), math.sin(ang)
    hw, hl = r * 2.3, r * 3.0
    pts = [(tip[0] + tx * hl, tip[1] + tz * hl), (tip[0] + nx * hw, tip[1] + nz * hw), (tip[0] - nx * hw, tip[1] - nz * hw)]
    parts.append(prism("Head", pts, r * 1.8, shade(color, 1.08), bevel_w=0.06))
    return group(parts, pos, rot, 1.0, name)


def drop(pos, s=0.5, color=None, name="Drop"):
    color = color or C["blue"]
    b = blobc(name + "B", s, (0, 0, 0), color, squash=(1, 1, 1.05))
    t = cone(name + "T", s * 0.78, s * 1.5, (0, 0, s * 0.55), shade(color, 1.25), segs=8)
    return group([b, t], pos, name=name)


def stack_of_coins(n=6, r=1.5, h=0.42):
    parts = []
    for i in range(n):
        parts.append(coin(f"S{i}", r, h, (0.12 * ((i * 7) % 3 - 1), 0.1 * ((i * 5) % 3 - 1), i * h), (0, 0, i * 31)))
    return group(parts, name="coinstack")
