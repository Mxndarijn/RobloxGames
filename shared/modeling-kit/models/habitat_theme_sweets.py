# habitat_theme_sweets: candy-shop theme layer (Gummy, Mochi, Cheddar, Flan, Soda Pop, Rocky Road, Sushi). Back and
# sides of the rim only, no ring (the tier frame mesh supplies it), front arc clear for the signature prop. From
# habitat_candy_patch_overlay (swirl lollipops, sugared gumdrops, sprinkles, the same pink / lilac / goo / butter
# palette): two swirl lollipops either side of a big frosted cupcake with a cherry at the back, a sprinkled donut
# standing on its edge on the left, a wrapped candy on the right, gumdrop pairs down both sides and sprinkles.
import math, random
import bmesh
from mathutils import Matrix, Vector
from lib import *
from lib.shapes import obj_from_bm
from models._habitat import lathe, frame_obj, P, WOOD, PINK, ROOF, GOO, CREAM, BUTTER
from models._habitat_theme_rim import *

LILAC = mix(P["ranch_lilac"], CREAM, 0.2)
MINT = mix(GOO, CREAM, 0.2)
DOUGH, DOUGH_D = rgb(236, 176, 104), rgb(206, 140, 80)
CHERRY = rgb(232, 44, 64)
SPR = [PINK, BUTTER, GOO, LILAC, CREAM, ROOF, rgb(110, 170, 250)]
R = random.Random(11)
parts = []


def gumdrop(name, r, h, col, pos):
    """Squat sugared dome, flat bottom on pos."""
    prof = [(0, 0), (r, 0), (r * 0.95, h * 0.35), (r * 0.66, h * 0.78), (r * 0.28, h * 0.97), (0, h)]
    lo, hi = shade(col, 0.92), mix(col, CREAM, 0.25)
    g = lathe(name, prof, segs=8, color_fn=lambda i, k, z: shade(mix(lo, hi, min(1.0, z / h)), 1.05 if k % 3 == 0 else 1.0))
    return frame_obj(g, Matrix.Translation(Vector(pos)))


def lollipop(name, deg, col, top=2.65, rr=0.82, r=3.3):
    """Swirl disc on a cream stick, the disc face turned to the pad centre."""
    x, y = pol(r, deg)
    th = 0.32
    cz = top - rr
    stick = cylinder(name + "Stick", 0.12, cz, (x, y, 0), CREAM, segs=6)
    face = [rr * f for f in (0.18, 0.36, 0.54, 0.72, 0.88)]
    rows = [(0, -th / 2)] + [(q, -th / 2) for q in face] + [(rr, 0)] + [(q, th / 2) for q in reversed(face)] + [(0, th / 2)]

    def sw(i, k, z):
        ring = min(i, len(rows) - 2 - i)
        return col if (k + ring * 2) % 8 < 4 else mix(CREAM, col, 0.15)
    disc = lathe(name + "Disc", rows, segs=16, color_fn=sw)
    frame_obj(disc, Matrix.Translation(Vector((x, y, cz))) @ Matrix.Rotation(math.radians(deg + 90), 4, "Z")
              @ Matrix.Rotation(math.radians(90), 4, "X"))
    bow = [blob(name + f"Bow{s}", 0.17, (x + s * 0.16 * math.cos(math.radians(deg + 90)), y + s * 0.16 * math.sin(math.radians(deg + 90)),
                                         cz - rr - 0.05), col, subdiv=1, squash=(1.3, 0.6, 0.8), jitter=0, rot=(0, 0, deg + 90))
           for s in (-1, 1)]
    return [stick, disc] + bow


def torus(name, R_, r, seg_u=12, seg_v=6, col_fn=None):
    """Torus round the Y axis (standing on edge in XZ), per-face colour col_fn(normal)."""
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    rings = []
    for i in range(seg_u):
        u = i / seg_u * math.tau
        cu, su = math.cos(u), math.sin(u)
        ring = []
        for j in range(seg_v):
            v = j / seg_v * math.tau
            d = R_ + r * math.cos(v)
            ring.append(bm.verts.new((d * cu, r * math.sin(v), d * su)))
        rings.append(ring)
    for i in range(seg_u):
        a, b = rings[i], rings[(i + 1) % seg_u]
        for j in range(seg_v):
            j1 = (j + 1) % seg_v
            bm.faces.new((a[j], b[j], b[j1], a[j1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.normal_update()
        c = col_fn(f.normal, f.calc_center_median())
        for lp in f.loops:
            lp[layer] = c
    return obj_from_bm(name, bm)


# --- back: lollipops either side of a big frosted cupcake ----------------------------------------------------
parts += lollipop("LolL", 114, PINK)
parts += lollipop("LolR", 66, LILAC, top=2.35, rr=0.74)
cx, cy = pol(3.28, 90)
WR = [(0, 0), (0.46, 0), (0.6, 0.7), (0.62, 0.74), (0, 0.74)]  # pleated wrapper
parts.append(lathe("Wrapper", WR, segs=12, pos=(cx, cy, 0), phase=math.pi / 12,
                   color_fn=lambda i, k, z: (rgb(110, 170, 250) if k % 2 else shade(rgb(110, 170, 250), 1.12)) if i < 3 else CREAM))
for k, (rr, z, h) in enumerate(((0.64, 0.7, 0.42), (0.52, 1.02, 0.4), (0.33, 1.3, 0.38))):  # frosting swirl tiers
    f = blob(f"Frost{k}", rr, (cx, cy, z + h * 0.45), mix(PINK, CREAM, 0.35 + 0.12 * k), subdiv=1, squash=(1, 1, h / rr), jitter=0.02, seed=k)
    parts.append(f)
parts.append(blob("Cherry", 0.2, (cx, cy, 1.83), CHERRY, subdiv=1, jitter=0))
parts.append(tube("CherryStem", [(cx, cy, 1.98), (cx + 0.06, cy - 0.04, 2.15), (cx + 0.16, cy - 0.06, 2.25)], [0.03, 0.03, 0.025], rgb(90, 160, 70), segs=4))
for i in range(6):  # sprinkles on the frosting
    a = i * 2.4
    rr = 0.48 if i < 4 else 0.36
    z = 0.98 if i < 4 else 1.28
    parts.append(box(f"CakeSpr{i}", (0.2, 0.07, 0.06), (cx + rr * math.cos(a), cy + rr * math.sin(a), z), SPR[i % len(SPR)],
                     rot=(0, R.uniform(-30, 30), math.degrees(a) + 60)))

# --- left: a sprinkled donut standing on its edge, iced face to the slime -------------------------------------
DD = 150
dx, dy = pol(3.22, DD)
ICE = rgb(250, 140, 190)


def donut_col(n, c):
    if n.y < -0.25:  # local -Y half = the iced face
        return shade(ICE, 1.0 + 0.06 * n.z)
    return shade(DOUGH, 0.9 + 0.15 * max(0.0, n.z)) if n.y < 0.5 else DOUGH_D


don = torus("Donut", 0.5, 0.25, col_fn=donut_col)
frame_obj(don, Matrix.Translation(Vector((dx, dy, 0.76))) @ Matrix.Rotation(math.radians(DD - 90), 4, "Z"))
parts.append(don)
ox, oy = math.cos(math.radians(DD + 180)), math.sin(math.radians(DD + 180))  # toward the slime
for i in range(6):
    a = i * math.tau / 6 + 0.3
    rr = 0.5 + 0.08 * ((i % 3) - 1)
    t = rr * math.cos(a)
    tx, ty = math.cos(math.radians(DD + 90)), math.sin(math.radians(DD + 90))
    parts.append(box(f"DonSpr{i}", (0.2, 0.07, 0.07), (dx + tx * t + ox * 0.22, dy + ty * t + oy * 0.22, 0.76 + rr * math.sin(a)),
                     SPR[(i + 2) % len(SPR)], rot=(R.uniform(0, 180), 0, DD + 90)))

# --- right: a wrapped candy (twisted ends) lying on the band --------------------------------------------------
WD = 28
wx, wy = pol(3.22, WD)
tx, ty = math.cos(math.radians(WD + 90)), math.sin(math.radians(WD + 90))
parts.append(blob("Candy", 0.36, (wx, wy, 0.42), BUTTER, subdiv=1, squash=(1.35, 1, 1), jitter=0, rot=(0, 0, WD + 90)))
for k in range(3):  # stripes round the candy
    t = -0.22 + 0.22 * k
    rr = 0.36 * math.sqrt(max(0.0, 1 - (t / 0.49) ** 2)) + 0.02
    parts.append(cylinder(f"CandyBand{k}", rr, 0.06, (wx + tx * t, wy + ty * t, 0.42), ROOF, segs=8, rot=(0, 90, WD + 90)))
for s in (-1, 1):
    end = cone(f"Twist{s}", 0.3, 0.45, (0, 0, 0), mix(BUTTER, CREAM, 0.3), segs=6)
    end.data.transform(Matrix.Translation((wx + tx * s * 0.82, wy + ty * s * 0.82, 0.42))
                       @ Matrix.Rotation(math.radians(WD + 90), 4, "Z") @ Matrix.Rotation(math.radians(-90 * s), 4, "Y"))
    parts.append(end)

# --- gumdrop pairs down both sides (tallest near the back, low toward the front) ------------------------------
GUM = [(178, 0.42, 0.62, ROOF), (191, 0.3, 0.42, BUTTER), (205, 0.27, 0.36, LILAC),
       (2, 0.42, 0.62, PINK), (-11, 0.3, 0.42, GOO), (-25, 0.27, 0.36, BUTTER), (52, 0.3, 0.44, PINK)]
for i, (deg, r, h, col) in enumerate(GUM):
    parts.append(gumdrop(f"Gum{i}", r * 1.12, h * 1.35, col, (*pol(3.18 + 0.18 * (i % 2), deg), 0)))

# --- sprinkles on the frame top --------------------------------------------------------------------------------
for i in range(5):
    deg = R.choice((R.uniform(-30, 70), R.uniform(110, 210)))
    x, y = pol(R.uniform(2.85, 3.55), deg)
    parts.append(box(f"Spr{i}", (0.38, 0.12, 0.1), (x, y, 0.32), SPR[i % len(SPR)], rot=(0, 0, R.uniform(0, 180))))
theme_finish("habitat_theme_sweets", parts)
