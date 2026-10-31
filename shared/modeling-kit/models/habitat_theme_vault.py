# habitat_theme_vault: Treasure Vault theme props on the rim (Midas, Jackpot, Goo God). No frame ring (the frame mesh
# supplies it). Back: a round steel vault door with a gold wheel and bolts in a stone frame; back-sides: a big ruby on
# a coin pile and a heap of gold coins; sides: a gold bar stack and a coin pile with an emerald; front-sides: a
# sapphire and loose coins; flat coins at the front keep the bbox centred and the front arc clear.
import math, random
from mathutils import Matrix
from lib import *
from models._habitat import frame_obj, lathe
from models._habitat_overlay import *

GOLD_LO, GOLD, GOLD_HI = rgb(232, 146, 34), rgb(246, 186, 44), rgb(255, 226, 110)
STEEL_LO, STEEL, STEEL_HI = rgb(150, 160, 184), rgb(186, 196, 216), rgb(226, 232, 244)
WALL_LO, WALL_HI = rgb(124, 136, 172), rgb(170, 182, 212)  # vault steel (darker than the door)
DARK = rgb(96, 104, 134)
GEMS = {"ruby": (rgb(214, 36, 70), rgb(255, 120, 150)), "emerald": (rgb(30, 176, 100), rgb(120, 245, 170)),
        "sapphire": (rgb(40, 100, 230), rgb(130, 190, 255)), "amethyst": (rgb(150, 70, 230), rgb(214, 160, 255))}
R = random.Random(11)
parts = []


def sq(r, deg):
    """Square-layout point that round_up lands on radius r, direction deg."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    m = max(abs(c), abs(s))
    return r * c / m, r * s / m


def put(objs, r, deg, yaw=None):
    """Move parts built round the origin (local -Y = toward the slime) to (r, deg) on the rim."""
    x, y = sq(r, deg)
    m = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(deg - 90 if yaw is None else yaw), 4, "Z")
    for o in objs:
        frame_obj(o, m)
    parts.extend(objs)
    return objs


def coin(n, pos, tilt=0, toward=0, r=0.18):
    """Gold coin: a thin 6-sided disc, rim dark, face bright, tilted tilt degrees toward `toward`."""
    c = cylinder(f"Coin{n}", r, 0.07, (0, 0, -0.035), None, segs=6)
    gradient(c, GOLD_LO, GOLD_HI)
    m = (Matrix.Translation(pos) @ Matrix.Rotation(math.radians(toward), 4, "Z") @ Matrix.Rotation(math.radians(tilt), 4, "X"))
    return [frame_obj(c, m)]


def pile(n, rad, h, coins=7):
    """Coin heap: a gold mound with tilted coins lying on its surface."""
    prof = [(0, 0), (rad, 0), (rad * 0.82, h * 0.35), (rad * 0.5, h * 0.8), (0, h)]
    out = [lathe(f"Heap{n}", prof, segs=9, phase=0.3, color_fn=lambda i, k, z: [GOLD_LO, GOLD, GOLD_HI, GOLD_HI][i] if (k + i) % 3 else shade(GOLD, 0.94))]
    for k in range(coins):
        a = k * 2.4 + n
        t = 0.25 + 0.6 * ((k * 0.37) % 1)
        rr = rad * (1 - t) * 0.95 + 0.04
        z = h * t * 0.92
        out += coin(f"{n}_{k}", (rr * math.cos(a), rr * math.sin(a), z), tilt=20 + 25 * (1 - t), toward=math.degrees(a) + 90)
    return out


def gem(n, kind, s=1.0, tilt=0.0, toward=0.0, pos=(0, 0, 0)):
    """Brilliant-cut gem standing on its point: pavilion cone, girdle, crown, flat table; facet shades alternate."""
    lo, hi = GEMS[kind]
    prof = [(0, 0), (0.34 * s, 0.42 * s), (0.36 * s, 0.5 * s), (0.22 * s, 0.68 * s), (0, 0.7 * s)]

    def col(i, k, z):
        base = [lo, mix(lo, hi, 0.4), mix(lo, hi, 0.75), hi][i]
        return shade(base, 1.0 if k % 2 else 0.86)
    g = lathe(f"Gem{n}", prof, segs=8, phase=math.pi / 8, color_fn=col)
    m = Matrix.Translation(pos) @ Matrix.Rotation(math.radians(toward), 4, "Z") @ Matrix.Rotation(math.radians(tilt), 4, "X")
    return [frame_obj(g, m)]


def vault():
    """Round vault door in a steel frame, facing -Y: steel door, raised ring, gold wheel with 4 spokes, bolts."""
    out = []
    wall = box("Wall", (1.12, 0.26, 1.34), (0, 0.12, 0.67))
    gradient(wall, WALL_LO, WALL_HI)
    out.append(wall)
    out.append(box("WallCap", (1.18, 0.32, 0.12), (0, 0.12, 1.4), STEEL_HI))
    out.append(box("WallFoot", (1.18, 0.32, 0.14), (0, 0.12, 0.07), STEEL))
    cz = 0.72
    door = cylinder("Door", 0.47, 0.14, (0, -0.02, cz), None, segs=14, rot=(90, 0, 0))
    gradient(door, STEEL, STEEL_HI)
    out.append(door)
    ring = [(0.49 * math.cos(k * math.tau / 16), -0.12, cz + 0.49 * math.sin(k * math.tau / 16)) for k in range(17)]
    out.append(tube("Ring", ring, [0.075] * 17, GOLD, segs=5))
    for k in range(8):
        a = k * math.tau / 8 + math.pi / 8
        out.append(cylinder(f"Bolt{k}", 0.05, 0.06, (0.37 * math.cos(a), -0.15, cz + 0.37 * math.sin(a)), DARK, segs=5, rot=(90, 0, 0)))
    out.append(cylinder("Hub", 0.1, 0.14, (0, -0.15, cz), GOLD_HI, segs=8, rot=(90, 0, 0)))
    wheel = [(0.24 * math.cos(k * math.tau / 10), -0.25, cz + 0.24 * math.sin(k * math.tau / 10)) for k in range(11)]
    out.append(tube("Wheel", wheel, [0.045] * 11, GOLD, segs=4))
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        out.append(tube(f"Spoke{k}", [(0, -0.24, cz), (0.3 * math.cos(a), -0.25, cz + 0.3 * math.sin(a))], [0.04, 0.04], GOLD, segs=4))
        out.append(blob(f"Knob{k}", 0.065, (0.31 * math.cos(a), -0.25, cz + 0.31 * math.sin(a)), GOLD_HI, subdiv=1, jitter=0))
    out.append(box("Hinge", (0.1, 0.1, 0.44), (-0.5, -0.04, cz), STEEL_HI))
    out += gem("Top", "amethyst", 1.05, pos=(0, 0.12, 1.46))
    return out


def bars():
    """Gold bar stack 3 + 2 + 1: square frustums stretched along x."""
    out = []
    for row, (n, z) in enumerate(((3, 0.0), (2, 0.18), (1, 0.36))):
        for k in range(n):
            y = (k - (n - 1) / 2) * 0.3
            b = cylinder(f"Bar{row}{k}", 0.2, 0.18, (0, 0, 0), None, segs=4, r_top=0.15, rot=(0, 0, 45))
            gradient(b, GOLD, GOLD_HI)
            frame_obj(b, Matrix.Translation((0, y, z)) @ Matrix.Diagonal((1.9, 1.0, 1.0, 1.0)))
            out.append(b)
    return out


put(vault(), 3.3, 90)
put(pile(0, 0.46, 0.4, 5) + gem("Ruby", "ruby", 1.6, tilt=-12, pos=(0, 0.05, 0.24)), 3.3, 50)
put(pile(1, 0.6, 0.8, 10), 3.3, 130)
put(bars(), 3.3, 166, yaw=130)
put(pile(2, 0.46, 0.42, 5) + gem("Emerald", "emerald", 1.25, tilt=14, pos=(0.05, 0.0, 0.24)), 3.3, 12)
put(gem("Sapphire", "sapphire", 1.0, tilt=-18, toward=30, pos=(0, 0, 0)), 3.35, -30)
put(gem("Amethyst", "amethyst", 0.85, tilt=16, toward=-20, pos=(0, 0, 0)), 3.35, 204)
for i, (deg, rr) in enumerate(((-62, 3.3), (-80, 3.55), (-100, 3.5), (-118, 3.3), (30, 3.6), (150, 3.6), (186, 3.55))):
    put(coin(f"L{i}", (0, 0, 0.035), tilt=0, r=0.22), rr, deg + R.uniform(-3, 3))

o = overlay_finish("habitat_theme_vault", parts)
if not PREVIEW:
    front = [v for v in o.data.vertices if v.co.z > 0.3 and v.co.y < 0 and abs(math.degrees(math.atan2(v.co.x, -v.co.y))) < 45]
    print(f"FRONT verts_over_0.3={len(front)}")
