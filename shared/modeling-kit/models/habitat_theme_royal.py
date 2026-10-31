# habitat_theme_royal: throne-room theme layer (King Goo, Sir Goo, Dragon King). Back and sides of the rim only, no
# ring (the tier frame mesh supplies it), front arc clear for the signature prop. From habitat_show_stool_overlay
# (gold stanchion posts, crimson velvet ropes with gold tassels, royal blue velvet, the same gold / blue / crimson):
# two gold banner poles at the back with royal blue banners (gold trim, gold crown emblem, swallowtail), a gold crown
# on a blue velvet cushion between them, red carpet runners with gold edging down both sides, and gold stanchions
# with sagging crimson velvet ropes along the carpets.
import math, random
import bmesh
from mathutils import Matrix, Vector
from lib import *
from lib.shapes import obj_from_bm
from models._phoenix_pad import lathe
from models._habitat_theme_rim import *

BLUE, BLUE_D, BLUE_HI = rgb(84, 124, 218), rgb(70, 106, 200), rgb(122, 160, 240)
GOLD, GOLD_D = rgb(255, 214, 90), rgb(222, 164, 52)
ROPE, ROPE_D = rgb(226, 62, 78), rgb(198, 50, 66)
CARPET, CARPET_D = rgb(222, 52, 64), rgb(190, 40, 56)
GEM_R, GEM_B = rgb(240, 60, 90), rgb(90, 200, 250)
parts = []


def tdir(deg):
    a = math.radians(deg + 90)
    return math.cos(a), math.sin(a)


def runner(name, a0, a1, r0=2.82, r1=3.62, z0=0.28, z1=0.44, n=8):
    """Carpet strip lying on the band from angle a0 to a1, gold edging on both long sides."""
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    bands = [(r0, GOLD), (r0 + 0.12, CARPET), (r1 - 0.12, GOLD), (r1, None)]
    rs = [b[0] for b in bands]
    grid_t, grid_b = [], []
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        grid_t.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z1)) for r in rs])
        grid_b.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z0)) for r in rs])

    def face(vs, c):
        f = bm.faces.new(vs)
        for lp in f.loops:
            lp[layer] = c
    for k in range(n):
        for j in range(len(rs) - 1):
            c = bands[j][1]
            if c is CARPET and k % 2:
                c = shade(CARPET, 0.94)
            face((grid_t[k][j], grid_t[k][j + 1], grid_t[k + 1][j + 1], grid_t[k + 1][j]), c)
            face((grid_b[k][j], grid_b[k + 1][j], grid_b[k + 1][j + 1], grid_b[k][j + 1]), CARPET_D)
        face((grid_t[k][0], grid_t[k + 1][0], grid_b[k + 1][0], grid_b[k][0]), GOLD_D)
        face((grid_t[k][-1], grid_b[k][-1], grid_b[k + 1][-1], grid_t[k + 1][-1]), GOLD_D)
    for g, rev in ((0, False), (n, True)):
        vs = grid_t[g] + list(reversed(grid_b[g]))
        face(list(reversed(vs)) if rev else vs, CARPET_D)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


POST = [(0, 0.0), (0.3, 0.0), (0.3, 0.08), (0.1, 0.24), (0.08, 0.95), (0.13, 1.0), (0.08, 1.06), (0, 1.06)]


def stanchion(name, deg, r=3.22, z0=0.42):
    x, y = pol(r, deg)
    out = [lathe(name, POST, segs=6, pos=(x, y, z0), color_fn=lambda i, k, z: mix(GOLD_D, GOLD, min(1.0, 0.3 + (z - z0) / 1.1)))]
    out.append(blob(name + "Ball", 0.16, (x, y, z0 + 1.18), GOLD, subdiv=1, jitter=0))
    return out


def velvet(name, d0, d1, r=3.22, top=1.3, sag=0.3, n=7):
    pts = []
    for j in range(n):
        u = j / (n - 1)
        x, y = pol(r, d0 + (d1 - d0) * u)
        pts.append((x, y, top - sag * 4 * u * (1 - u)))
    o = tube(name, pts, [0.085] * n, ROPE, segs=4)
    gradient(o, ROPE_D, ROPE)
    return o


# --- red carpet runners down both sides, gold stanchions and velvet ropes along them -----------------------------
for side, (a0, a1) in (("L", (138, 212)), ("R", (42, -32))):
    parts.append(runner(f"Carpet{side}", a0, a1))
    degs = [a0 + (a1 - a0) * t for t in (0.08, 0.5, 0.92)]
    for k, d in enumerate(degs):
        parts += stanchion(f"Stan{side}{k}", d)
    for k in range(2):
        parts.append(velvet(f"Velvet{side}{k}", degs[k], degs[k + 1]))
        mx, my = pol(3.22, (degs[k] + degs[k + 1]) / 2)
        parts.append(blob(f"TasKnot{side}{k}", 0.08, (mx, my, 0.94), GOLD, subdiv=1, jitter=0))
        parts.append(cylinder(f"Tas{side}{k}", 0.1, 0.24, (mx, my, 0.68), GOLD_D, segs=6, r_top=0.04))

# --- banner poles at the back: gold pole + finial, blue swallowtail banner with gold trim and crown --------------
for i, deg in enumerate((113, 67)):
    x, y = pol(3.4, deg)
    ox, oy = math.cos(math.radians(deg)), math.sin(math.radians(deg))  # outward
    tx, ty = tdir(deg)
    pole = cylinder(f"Pole{i}", 0.08, 2.45, (x, y, 0), GOLD, segs=6)
    gradient(pole, GOLD_D, GOLD)
    parts.append(pole)
    parts.append(cylinder(f"PoleFoot{i}", 0.24, 0.3, (x, y, 0), GOLD_D, segs=6, r_top=0.14))
    parts.append(cone(f"Finial{i}", 0.13, 0.3, (x, y, 2.45), GOLD, segs=6))
    parts.append(blob(f"FinialBall{i}", 0.1, (x, y, 2.47), GOLD, subdiv=1, jitter=0))
    # cross bar + banner hanging in front of the pole (toward the slime), facing it
    bx, by = x - ox * 0.12, y - oy * 0.12
    parts.append(cylinder(f"Bar{i}", 0.05, 1.14, (bx, by, 2.25), GOLD, segs=5, rot=(0, 90, deg + 90)))
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    W, TOP, BOT, NOTCH = 0.5, 2.22, 0.85, 0.32
    outline = [(-W, TOP), (W, TOP), (W, BOT), (0, BOT + NOTCH), (-W, BOT)]
    m = Matrix.Translation((bx, by, 0)) @ Matrix.Rotation(math.radians(deg + 90), 4, "Z")
    front = [bm.verts.new(m @ Vector((u, -0.03, v))) for u, v in outline]
    back = [bm.verts.new(m @ Vector((u, 0.03, v))) for u, v in outline]
    fs = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    for k in range(5):
        k1 = (k + 1) % 5
        fs.append(bm.faces.new((front[k], back[k], back[k1], front[k1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in fs:
        for lp in f.loops:
            lp[layer] = mix(BLUE_D, BLUE, max(0.0, min(1.0, (lp.vert.co.z - BOT) / (TOP - BOT))))
    parts.append(obj_from_bm(f"Banner{i}", bm))
    # gold trim stripes and crown emblem on both faces
    for f_, s in (("F", -1), ("B", 1)):
        off = s * 0.05
        cx, cy = bx + ox * off, by + oy * off
        parts.append(box(f"Trim{i}{f_}", (2 * W, 0.03, 0.08), (cx, cy, TOP - 0.1), GOLD, rot=(0, 0, deg + 90)))
        parts.append(box(f"Trim2{i}{f_}", (2 * W, 0.03, 0.06), (cx, cy, BOT + 0.42), GOLD, rot=(0, 0, deg + 90)))
        ez = 1.68
        parts.append(box(f"CrownB{i}{f_}", (0.5, 0.03, 0.14), (cx, cy, ez - 0.14), GOLD, rot=(0, 0, deg + 90)))
        for k, u in enumerate((-0.19, 0.0, 0.19)):
            pz = ez + (0.06 if k == 1 else 0.0)
            parts.append(box(f"CrownP{i}{f_}{k}", (0.12, 0.03, 0.26), (cx + tx * u, cy + ty * u, pz), GOLD, rot=(0, 0, deg + 90)))

# --- gold crown on a blue velvet cushion at the back middle ------------------------------------------------------
cx, cy = pol(3.25, 90)
cush = blob("Cushion", 0.5, (cx, cy, 0.62), None, subdiv=2, squash=(1.25, 1.05, 0.5), jitter=0)
gradient(cush, BLUE_D, BLUE_HI)
parts.append(cush)
parts.append(cylinder("Stand", 0.42, 0.42, (cx, cy, 0), GOLD_D, segs=8, r_top=0.3))
CROWN = [(0, 0.0), (0.34, 0.0), (0.36, 0.1), (0.38, 0.3), (0.0, 0.3)]
parts.append(lathe("CrownBand", CROWN, segs=10, pos=(cx, cy, 0.82), color_fn=lambda i, k, z: GOLD if i != 1 else GOLD_D))
for k in range(5):  # crown points with ball tips
    a = k * math.tau / 5 + math.pi / 2
    px, py = cx + 0.32 * math.cos(a), cy + 0.32 * math.sin(a)
    parts.append(cone(f"CrownPt{k}", 0.12, 0.34, (px, py, 1.1), GOLD, segs=4))
    parts.append(blob(f"CrownTip{k}", 0.06, (px, py, 1.45), GOLD, subdiv=1, jitter=0))
for k, (a, col) in enumerate(((-90, GEM_R), (-30, GEM_B), (-150, GEM_B))):  # gems on the front of the band
    ar = math.radians(a)
    parts.append(blob(f"Gem{k}", 0.075, (cx + 0.37 * math.cos(ar), cy + 0.37 * math.sin(ar), 0.97), col, subdiv=1, squash=(1, 0.6, 1), jitter=0,
                      rot=(0, 0, a + 90)))
theme_finish("habitat_theme_royal", parts)
