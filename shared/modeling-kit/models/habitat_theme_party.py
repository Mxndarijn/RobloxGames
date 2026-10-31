# habitat_theme_party: Party Stage theme props on the rim (Disco, Doodle, Gl1tch). No frame ring (the frame mesh
# supplies it). Back: a balloon bunch tied to a gift box between two spotlights on tripod stands; sides: two
# speaker boxes with pink / cyan woofers; front-sides: little floor up-lights; confetti strips all round (flat at the
# front, keeping the bbox centred and the front arc clear). Bright purple / pink / cyan.
import math, random
from mathutils import Matrix
from lib import *
from models._habitat import frame_obj
from models._habitat_overlay import *

PURPLE_LO, PURPLE_HI = rgb(122, 74, 214), rgb(172, 124, 252)
PINK, CYAN, YELLOW, LIME = rgb(255, 84, 190), rgb(60, 220, 255), rgb(255, 222, 60), rgb(130, 240, 90)
CONE = rgb(96, 74, 150)  # woofer cone (lifted dark purple)
METAL_LO, METAL_HI = rgb(150, 150, 176), rgb(214, 216, 232)
WHITE = rgb(255, 250, 255)
CONFETTI = [PINK, CYAN, YELLOW, LIME, rgb(190, 120, 255)]
R = random.Random(5)
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


def spotlight(n, col):
    """Tripod stand + pole + yoke + a can light tilted up toward the slime, glowing lens on -Y."""
    out = []
    for k in range(3):
        a = math.radians(90 + k * 120)
        out.append(tube(f"Leg{n}{k}", [(0, 0, 0.75), (0.42 * math.cos(a), 0.42 * math.sin(a), 0.0)], [0.045, 0.045], METAL_LO, segs=4))
    pole = cylinder(f"Pole{n}", 0.05, 1.25, (0, 0, 0.6), None, segs=5)
    gradient(pole, METAL_LO, METAL_HI)
    out.append(pole)
    out.append(box(f"Yoke{n}", (0.5, 0.06, 0.06), (0, 0, 1.85), METAL_HI))
    for s in (-1, 1):
        out.append(box(f"YokeArm{n}{s}", (0.05, 0.06, 0.3), (s * 0.25, 0, 2.0), METAL_HI))
    tilt = Matrix.Translation((0, 0, 2.05)) @ Matrix.Rotation(math.radians(55), 4, "X")  # can axis: toward -Y, 35 deg up
    can = frame_obj(cylinder(f"Can{n}", 0.26, 0.56, (0, 0, -0.24), None, segs=8, r_top=0.3), tilt)
    gradient(can, PURPLE_LO, PURPLE_HI)
    out.append(can)
    out.append(frame_obj(cylinder(f"Lens{n}", 0.25, 0.05, (0, 0, 0.32), col, segs=8), tilt))
    out.append(frame_obj(cylinder(f"LensHi{n}", 0.13, 0.06, (0, 0, 0.33), WHITE, segs=6), tilt))
    out.append(frame_obj(cylinder(f"Rim{n}", 0.32, 0.07, (0, 0, 0.28), METAL_HI, segs=8), tilt))
    return out


def balloons():
    """Three balloons on strings tied to a small gift box."""
    out = [box("Gift", (0.42, 0.42, 0.36), (0, 0, 0.18), CYAN)]
    out.append(box("RibbonX", (0.44, 0.1, 0.38), (0, 0, 0.18), PINK))
    out.append(box("RibbonY", (0.1, 0.44, 0.38), (0, 0, 0.18), PINK))
    out.append(blob("Bow", 0.11, (0, 0, 0.4), PINK, subdiv=1, jitter=0, squash=(1.6, 0.8, 0.8)))
    for k, (x, y, z, col) in enumerate(((-0.3, 0.05, 2.02, PINK), (0.3, 0.08, 1.9, YELLOW), (0.0, -0.04, 2.36, rgb(190, 120, 255)))):
        b = blob(f"Balloon{k}", 0.31, (x, y, z), None, seed=k, subdiv=2, squash=(1, 1, 1.18), jitter=0)
        gradient(b, shade(col, 0.88), mix(col, WHITE, 0.3))
        out.append(b)
        out.append(cone(f"Knot{k}", 0.06, 0.1, (x, y, z - 0.44), col, segs=4))
        out.append(tube(f"String{k}", [(0, 0, 0.42), (x * 0.5, y * 0.5, (z - 0.36) * 0.5), (x, y, z - 0.36)], [0.02] * 3, WHITE, segs=3))
    return out


def speaker(n, woofer):
    """Speaker box with a big woofer and a tweeter on -Y."""
    out = []
    b = box(f"Spk{n}", (0.78, 0.6, 1.2), (0, 0, 0.6))
    gradient(b, PURPLE_LO, PURPLE_HI)
    out.append(b)
    out.append(box(f"SpkTop{n}", (0.82, 0.64, 0.06), (0, 0, 1.23), METAL_HI))
    for (z, r, col) in ((0.42, 0.28, woofer), (0.95, 0.14, YELLOW)):
        out.append(cylinder(f"Wr{n}{z}", r, 0.06, (0, -0.3, z), col, segs=10, rot=(90, 0, 0)))
        out.append(cylinder(f"Wc{n}{z}", r * 0.7, 0.07, (0, -0.31, z), CONE, segs=10, rot=(90, 0, 0)))
        out.append(cylinder(f"Wd{n}{z}", r * 0.28, 0.1, (0, -0.32, z), WHITE, segs=6, rot=(90, 0, 0)))
    for s in (-1, 1):
        out.append(box(f"Foot{n}{s}", (0.14, 0.5, 0.06), (s * 0.28, 0, 0.03), METAL_LO))
    return out


def uplight(n, col):
    out = [cylinder(f"Up{n}", 0.2, 0.3, (0, 0, 0), None, segs=8)]
    gradient(out[0], PURPLE_LO, PURPLE_HI)
    out.append(cylinder(f"UpLens{n}", 0.16, 0.06, (0, 0, 0.29), col, segs=8))
    return out


def confetti(n, flat=False):
    """Small confetti strip; flat ones lie on the deck."""
    col = CONFETTI[n % len(CONFETTI)]
    tilt = (0, 0, 0) if flat else (R.uniform(-30, 30), R.uniform(-30, 30), 0)
    return [box(f"Conf{n}", (0.3, 0.13, 0.03), (0, 0, 0.03 if flat else 0.08), col, rot=(tilt[0], tilt[1], R.uniform(0, 180)))]


put(spotlight(0, PINK), 3.25, 60)
put(spotlight(1, CYAN), 3.25, 120)
put(balloons(), 3.25, 90)
put(speaker(0, PINK), 3.25, 12, yaw=24)
put(speaker(1, CYAN), 3.25, 168, yaw=-24)
put(uplight(0, YELLOW), 3.35, -30)
put(uplight(1, PINK), 3.35, 210)
CONF = [(-50, 3.5), (-66, 3.2), (-84, 3.62), (-97, 3.6), (-110, 3.6), (-126, 3.25), (-140, 3.5), (36, 3.65), (144, 3.65),
        (-12, 3.6), (192, 3.6), (75, 3.7), (105, 3.7), (-38, 3.15), (228, 3.2)]
for i, (deg, rr) in enumerate(CONF):  # confetti (flat everywhere: the front arc stays under 0.3)
    put(confetti(i, flat=True), rr, deg + R.uniform(-3, 3), yaw=R.uniform(0, 180))

o = overlay_finish("habitat_theme_party", parts)
if not PREVIEW:
    front = [v for v in o.data.vertices if v.co.z > 0.3 and v.co.y < 0 and abs(math.degrees(math.atan2(v.co.x, -v.co.y))) < 45]
    print(f"FRONT verts_over_0.3={len(front)}")
