# habitat_theme_dojo: Dojo theme props on the rim (Ninja, Origami, Kitsune). No frame ring (the frame mesh supplies
# it). Back: a tall bamboo cluster and a smaller one; right: a stone lantern with a warm window and a red paper lantern
# on a post (the red accent); left: a paper shoji screen; low stepping stones, moss and pebbles round the front keep the bbox
# centred and the front arc clear for the signature prop.
import math
from mathutils import Matrix
from lib import *
from models._habitat import frame_obj
from models._habitat_overlay import *

BAMBOO_LO, BAMBOO_HI, NODE = rgb(104, 182, 78), rgb(176, 228, 112), rgb(212, 236, 140)
LEAF, LEAF_HI = rgb(78, 170, 80), rgb(130, 210, 96)
MOSS, MOSS_HI = rgb(110, 180, 92), rgb(150, 210, 110)
STONE_LO, STONE_HI = rgb(160, 160, 156), rgb(212, 210, 200)
GLOW = rgb(255, 214, 90)
RED, RED_LO = rgb(232, 60, 50), rgb(200, 48, 44)
TOP = rgb(120, 74, 70)  # lantern caps / post base (lifted dark)
WOOD_LO, WOOD = rgb(176, 118, 74), rgb(206, 148, 94)
PAPER = rgb(252, 244, 224)
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


def moss(n, r, x=0, y=0, sx=1.3, sy=1.1):
    b = blob(f"Moss{n}", r, (x, y, 0.06), None, seed=n, subdiv=1, squash=(sx, sy, 0.4), jitter=0.12)
    gradient(b, MOSS, MOSS_HI)
    on_deck([b])
    return b


def stalk(n, x, y, h, lean=(0, 0)):
    """Bamboo stalk with node rings and a leaf spray at the top."""
    out = []
    m = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(lean[0]), 4, "X") @ Matrix.Rotation(math.radians(lean[1]), 4, "Y")
    s = cylinder(f"Stalk{n}", 0.15, h, (0, 0, 0), None, segs=6, r_top=0.13)
    gradient(s, BAMBOO_LO, BAMBOO_HI)
    out.append(frame_obj(s, m))
    z = 0.42
    while z < h - 0.2:
        out.append(frame_obj(cylinder(f"Node{n}_{z:.1f}", 0.175, 0.07, (0, 0, z), NODE, segs=6), m))
        z += 0.48
    for k, (a, dz, ln) in enumerate(((20, -0.05, 0.3), (150, -0.22, 0.28), (265, 0.0, 0.28), (90, -0.4, 0.26))):
        aa = math.radians(a + n * 40)
        lf = blob(f"Leaf{n}{k}", 1.0, (0, 0, 0), None, seed=n * 5 + k, subdiv=1, squash=(ln, 0.12, 0.05), jitter=0.0,
                  rot=(0, -25, 0))
        gradient(lf, LEAF, LEAF_HI)
        lf.data.transform(Matrix.Translation((math.cos(aa) * ln * 0.55, math.sin(aa) * ln * 0.55, h + dz)) @ Matrix.Rotation(aa, 4, "Z"))
        out.append(frame_obj(lf, m))
    return out


def bamboo(n, stalks):
    out = [moss(n, 0.42)]
    for i, (x, y, h, lean) in enumerate(stalks):
        out += stalk(n * 10 + i, x, y, h, lean)
    return out


def lantern():
    """Stone toro: base, post, platform, firebox with glowing windows, pyramid roof, knob."""
    out = [cylinder("LBase", 0.34, 0.14, (0, 0, 0), None, segs=6)]
    out.append(cylinder("LPost", 0.13, 0.5, (0, 0, 0.14), None, segs=6))
    out.append(cylinder("LDeck", 0.36, 0.12, (0, 0, 0.64), None, segs=6))
    out.append(box("LBox", (0.46, 0.46, 0.42), (0, 0, 0.97)))
    for p in out:
        gradient(p, STONE_LO, STONE_HI, z0=0, z1=1.6)
    for i, (x, y, w, d) in enumerate(((0, -0.24, 0.26, 0.04), (0.24, 0, 0.04, 0.26), (-0.24, 0, 0.04, 0.26))):
        out.append(box(f"LWin{i}", (w, d, 0.24), (x, y, 0.98), GLOW))
    roof = cylinder("LRoof", 0.52, 0.32, (0, 0, 1.18), None, segs=6, r_top=0.06)
    gradient(roof, STONE_LO, STONE_HI)
    out.append(roof)
    out.append(blob("LKnob", 0.11, (0, 0, 1.55), STONE_HI, subdiv=1, jitter=0, squash=(1, 1, 1.3)))
    return out


def paper_lantern():
    """Red paper lantern (chochin) hanging from a wooden post with an arm: ribbed oval body, dark caps, gold tassel."""
    from models._habitat import lathe
    out = [box("PBase", (0.4, 0.4, 0.12), (0, 0.12, 0.06), TOP)]
    post = cylinder("PPost", 0.07, 1.75, (0, 0.12, 0.12), None, segs=6, r_top=0.06)
    gradient(post, WOOD_LO, WOOD)
    out.append(post)
    out.append(box("PArm", (0.08, 0.5, 0.08), (0, -0.1, 1.82), WOOD))
    out.append(cylinder("PCord", 0.02, 0.12, (0, -0.3, 1.68), TOP, segs=4))
    prof = [(0.0, 0.0), (0.17, 0.0), (0.27, 0.1), (0.32, 0.27), (0.32, 0.43), (0.27, 0.6), (0.17, 0.7), (0.0, 0.7)]
    body = lathe("Chochin", prof, segs=10, pos=(0, -0.3, 0.98),
                 color_fn=lambda i, k, z: TOP if i in (0, 6) else (shade(RED, 0.92) if i % 2 else RED) if i not in (3,) else rgb(255, 120, 90))
    out.append(body)
    out.append(cylinder("PCapB", 0.18, 0.06, (0, -0.3, 0.95), TOP, segs=8))
    out.append(cylinder("PCapT", 0.18, 0.06, (0, -0.3, 1.66), TOP, segs=8))
    out.append(cone("PTassel", 0.07, 0.22, (0, -0.3, 0.73), rgb(255, 214, 90), segs=5))
    return out


def shoji():
    """Paper screen on feet: wood frame, cream paper, lattice bars proud on both faces, red top rail."""
    W, H, z0 = 1.12, 1.22, 0.12
    out = []
    for s in (-1, 1):
        out.append(box(f"SFoot{s}", (0.1, 0.42, 0.1), (s * (W / 2 - 0.05), 0, 0.05), WOOD_LO))
        out.append(box(f"SPost{s}", (0.08, 0.1, H), (s * (W / 2 - 0.05), 0, z0 + H / 2), WOOD))
    out.append(box("SRail", (W, 0.12, 0.1), (0, 0, z0 + H), RED))
    out.append(box("SSill", (W, 0.1, 0.08), (0, 0, z0 + 0.04), WOOD))
    out.append(box("SPaper", (W - 0.14, 0.03, H - 0.1), (0, 0, z0 + H / 2), PAPER))
    for i in range(1, 3):
        x = -W / 2 + 0.05 + i * (W - 0.1) / 3
        out.append(box(f"SBarV{i}", (0.04, 0.07, H - 0.1), (x, 0, z0 + H / 2), WOOD))
    for i in range(1, 4):
        z = z0 + i * H / 4
        out.append(box(f"SBarH{i}", (W - 0.14, 0.07, 0.04), (0, 0, z), WOOD))
    return out


def scaled(objs, k):
    for o in objs:
        frame_obj(o, Matrix.Scale(k, 4))
    return objs


def stone(n, r, sx=1.3, sy=1.0):
    b = blob(f"Step{n}", r, (0, 0, 0.04), None, seed=40 + n, subdiv=1, squash=(sx, sy, 0.3), jitter=0.1)
    gradient(b, STONE_LO, STONE_HI)
    on_deck([b])
    return b


put(bamboo(0, [(0.02, 0.06, 2.75, (0, 1)), (-0.2, -0.08, 2.15, (-2, -3)), (0.21, -0.04, 1.75, (2, 3))]), 3.25, 92)
put(bamboo(1, [(-0.06, 0.05, 2.0, (0, -2)), (0.18, -0.08, 1.5, (3, 3))]), 3.25, 128)
put(scaled(lantern(), 1.15), 3.3, 50)
put(paper_lantern(), 3.6, 2, yaw=0)
put(shoji(), 3.25, 168, yaw=-12)
put([moss(5, 0.32, sx=1.4, sy=0.9)], 3.5, 25)
put([moss(6, 0.3, sx=1.3, sy=0.9)], 3.5, 148)
for i, (deg, r) in enumerate(((-32, 0.34), (-148, 0.32), (-74, 0.3), (-106, 0.3), (212, 0.26), (-18, 0.24))):
    put([stone(i, r)], 3.35 + 0.2 * (abs(deg + 90) < 20), deg)
cushion = box("Cushion", (0.62, 0.62, 0.14), (0, 0, 0.07))  # red zabuton on the front-left: a low red spot
gradient(cushion, RED_LO, RED)
put([cushion, box("Tassel", (0.1, 0.1, 0.06), (0, 0, 0.16), rgb(255, 214, 90))], 3.3, 196)

o = overlay_finish("habitat_theme_dojo", parts)
if not PREVIEW:
    front = [v for v in o.data.vertices if v.co.z > 0.3 and v.co.y < 0 and abs(math.degrees(math.atan2(v.co.x, -v.co.y))) < 45]
    print(f"FRONT verts_over_0.3={len(front)}")
