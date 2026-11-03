# obby_padlock_c (option C): a goo-slime padlock for the Key Run gates (steal-a-slime obby).
# The body is a little gumdrop slime squeezed through the gate: domed shoulders, a saggy bottom with three goo drips,
# two big eyes and the keyhole as its mouth on each face; a fat gummy U shackle per face with
# goo collars where it goes in. Open = the shackle pops up and its short leg comes out (like option A).
# Old size 2.2 x 3.0 x 1.7. See models/_obby_padlock_parts.py for the pieces / preview switch.
import math
import bmesh
from lib import *
from lib.shapes import obj_from_bm
from models._obby_padlock_parts import *

H = 1.85  # body top
RC, BAR = 0.62, 0.2
ZC = H + 0.2  # arch centre, shut (the dome is lower at the legs)
SY = 0.63  # each face's shackle plane: a 0.2 bar stays inside the body face (0.85), its inner edge in the gate
LIFT = 0.6
DRIPS = ((-0.62, 0.22, 0.26), (0.08, 0.3, 0.32), (0.66, 0.18, 0.22))  # (x, half width, depth below the hem)
HEM = 0.3  # the hem height between drips
LEG_IN = 1.66  # the dome's height over the legs (x = +-RC)


def outline(n=56):
    """Front silhouette (x, z), counter-clockwise: a gumdrop that sags wider at the bottom, drips on the hem."""
    pts = []
    # bottom hem with drips, right to left
    for k in range(25):
        x = 1.12 - k * 2.24 / 24
        z = HEM
        for dx, hw, d in DRIPS:
            t = (x - dx) / hw
            if abs(t) < 1:
                z = min(z, HEM - d * (1 - t * t) ** 0.6)
        pts.append((x, z))
    # left side up and over the dome, back down the right
    for k in range(1, n):
        a = math.pi * k / n  # 0..pi
        # sides: x from -1.12 (bottom) narrowing to the dome; superellipse dome
        u = math.cos(math.pi - a)  # -1..1 across
        v = math.sin(a)
        x = 1.06 * (abs(u) ** 0.8) * (1 if u >= 0 else -1)
        z = HEM + (H - HEM) * v ** 0.7
        x *= 1.0 + 0.06 * (1 - v)  # sag: wider low down
        pts.append((x, z))
    return pts  # goes right->left on the hem, then left->right over the top


def body_shell(tb):
    pts = outline()
    # make it CCW seen from -Y (front): the hem runs right->left at the bottom, then up the left... that is CW seen
    # from the front; recalc_face_normals fixes the winding anyway.
    bm = bmesh.new()
    hy = DEPTH / 2
    front = [bm.verts.new((x, -hy, z)) for x, z in pts]
    back = [bm.verts.new((x, hy, z)) for x, z in pts]
    n = len(pts)
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for k in range(n):
        bm.faces.new((front[k], front[(k + 1) % n], back[(k + 1) % n], back[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    caps = [f for f in bm.faces if len(f.verts) > 4]
    bmesh.ops.triangulate(bm, faces=caps, quad_method="BEAUTY", ngon_method="EAR_CLIP")
    o = obj_from_bm("Body", bm, tc(0.8, tb))
    bevel(o, 0.22, segments=2, angle=30)
    gradient(o, tc(0.62, tb), tc(0.9, tb), 0.0, H)
    return o


def build(tb, ts):
    parts = [body_shell(tb)]
    hy = DEPTH / 2
    for s in (-1, 1):
        y = s * hy
        for x in (-0.42, 0.42):
            parts.append(blob(f"Eye{s}{x}", 0.24, (x, y, 1.12), tc(0.14, tb), subdiv=2, squash=(0.8, 0.28, 1.0),
                              jitter=0))
            parts.append(blob(f"Glint{s}{x}", 0.075, (x + 0.07, y + s * 0.07, 1.22), tc(1.0, tb), subdiv=1,
                              squash=(1, 0.5, 1), jitter=0))
        parts += keyhole(f"Key{s}", y, 0.68, 0.2, 0.2, 0.3, tc(0.14, tb))
        for x in (-RC, RC):  # goo collars round each leg where it goes into the dome
            parts.append(blob(f"Collar{s}{x}", 0.3, (x, s * SY, LEG_IN), tc(1.0, tb), subdiv=2,
                              squash=(1.0, 0.85, 0.45), jitter=0))
    sh = [shackle_u(f"Shackle{s}", RC, BAR, ZC, s * SY, 1.0, 0.55, tc(0.78, ts), tc(1.0, ts)) for s in (-1, 1)]
    return parts, sh


def open_pose(sh):
    place(sh, dz=LIFT)


assemble("obby_padlock_c", build, open_pose)
