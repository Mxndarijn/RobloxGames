# Not an asset: shared helpers for the lock stopper styles (models/lock_stopper_candy.py, _carousel.py, _sleepy.py),
# paid looks for jar 1's round door (models/_goo_jar.py jar_stopper). Fairness: every style is fitted to the classic
# stopper's exact bounding box (the game puts it in the same slot; the collider is a separate invisible part), keeps
# a full round plug over the doorway and the hinge knuckles the parked door swings on, and carries a red lock element.
# Built in the jar builder's axes (door disc centred at x 0, z R, inner face y = 0, outer face toward -Y), then shipped
# with _goo_jar.ship (mirrored in X like every jar piece).
import math

import bmesh
import bpy
from mathutils import Vector

from lib import *
from models._goo_jar import D, jar_stopper, ship, loop, teardrop  # noqa: F401  (re-exported for the styles)

R = 4.6  # the classic door disc's radius; the plug's centre is (0, -, R)
CZ = R
HX, HY = D["doorSwing"]["hinge"][0], D["doorSwing"]["hinge"][1]
RED = rgb(240, 70, 60)  # the lock button's red (models/_goo_jar.py RED): the locked signal
RED_HI = mix(RED, rgb(255, 210, 200), 0.35)
GOLD = rgb(236, 190, 92)
GOLD_D = rgb(196, 148, 70)


def bbox(objs):
    lo, hi = [1e9] * 3, [-1e9] * 3
    bpy.context.view_layer.update()
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i], hi[i] = min(lo[i], w[i]), max(hi[i], w[i])
    return lo, hi


def classic_box():
    parts = jar_stopper()
    b = bbox(parts)
    for o in parts:
        bpy.data.objects.remove(o, do_unlink=True)
    return b


def fit_to_classic(parts):
    """Stretch the parts per axis so their bbox is exactly the classic stopper's (prints the scale used: keep it
    near 1, or the look is being squashed, not designed)."""
    (lo0, hi0), (lo, hi) = classic_box(), bbox(parts)
    k = [(hi0[i] - lo0[i]) / (hi[i] - lo[i]) for i in range(3)]
    print("FIT scale x %.3f y %.3f z %.3f" % tuple(k))
    for o in parts:
        mw = o.matrix_world.copy()
        for v in o.data.vertices:
            w = mw @ v.co
            v.co = Vector([lo0[i] + (w[i] - lo[i]) * k[i] for i in range(3)])
        o.matrix_world = o.matrix_world.Identity(4)
        o.data.update()
    return parts


def set_col(bm, f, col):
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for lp in f.loops:
        lp[layer] = col


def plug(name, rings, segs, depth, color_fn, twist=None, rim=None, back_y=0.0, cz=CZ, back_col=None):
    """The plug body: a closed slab over the doorway. rings: radii (ascending, last = rim). depth(r): how far the
    front stands out toward -Y at radius r. color_fn(r_mid, a_mid, i, j) -> colour per front face (ring i, column
    j). twist(r): angle offset (radians) per ring, so columns follow a swirl. rim(a): outer radius scale at angle a
    (scallops). The back is flat at y = back_y, the side wall is painted like the outermost ring."""
    bm = bmesh.new()
    tw = twist or (lambda r: 0.0)
    rs = rim or (lambda a: 1.0)

    def pt(r, a, y):
        k = rs(a) if r >= rings[-1] - 1e-6 else 1.0
        return (r * k * math.cos(a), y, cz + r * k * math.sin(a))

    centre = bm.verts.new((0.0, back_y - depth(0.0), cz))
    grid = []
    for r in rings:
        grid.append([bm.verts.new(pt(r, j / segs * math.tau + tw(r), back_y - depth(r))) for j in range(segs)])
    back = [bm.verts.new(pt(rings[-1], j / segs * math.tau + tw(rings[-1]), back_y)) for j in range(segs)]
    for j in range(segs):  # centre fan
        a = (j + 0.5) / segs * math.tau + tw(rings[0] * 0.5)
        f = bm.faces.new((centre, grid[0][(j + 1) % segs], grid[0][j]))
        set_col(bm, f, color_fn(rings[0] * 0.5, a, -1, j))
    for i in range(len(rings) - 1):
        rm = (rings[i] + rings[i + 1]) / 2
        for j in range(segs):
            a = (j + 0.5) / segs * math.tau + tw(rm)
            f = bm.faces.new((grid[i][j], grid[i][(j + 1) % segs], grid[i + 1][(j + 1) % segs], grid[i + 1][j]))
            set_col(bm, f, color_fn(rm, a, i, j))
    last = len(rings) - 1
    for j in range(segs):  # side wall
        a = (j + 0.5) / segs * math.tau + tw(rings[-1])
        f = bm.faces.new((grid[-1][j], grid[-1][(j + 1) % segs], back[(j + 1) % segs], back[j]))
        set_col(bm, f, shade(color_fn(rings[-1], a, last, j), 0.85))
    f = bm.faces.new(list(reversed(back)))
    set_col(bm, f, back_col or shade(color_fn(rings[-1], 0.0, last, 0), 0.8))  # the back shows on the parked door
    bmesh.ops.triangulate(bm, faces=[f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def torus(name, R_, r_, center, col, segs=24, sides=8, axis="y", arc=(0.0, 360.0), col_fn=None, squash=1.0):
    """A closed torus (full) round `center` in the plane normal to `axis`, or a tube along an arc (capped). col_fn(u)
    -> colour per segment (u = segment angle in radians) for striped rope."""
    bm = bmesh.new()
    full = abs(arc[1] - arc[0]) >= 359.999
    n = segs if full else segs + 1
    cx, cy, cz = center
    rings = []
    for k in range(n):
        u = math.radians(arc[0] + (arc[1] - arc[0]) * k / segs)
        ring = []
        for s in range(sides):
            v = s / sides * math.tau
            rr = R_ + r_ * math.cos(v)
            off = r_ * math.sin(v) * squash
            a, b = rr * math.cos(u), rr * math.sin(u)
            p = {"y": (cx + a, cy + off, cz + b), "z": (cx + a, cy + b, cz + off), "x": (cx + off, cy + a, cz + b)}[axis]
            ring.append(bm.verts.new(p))
        rings.append(ring)
    segN = segs if full else segs
    for k in range(segN):
        A, B = rings[k], rings[(k + 1) % n]
        u = math.radians(arc[0] + (arc[1] - arc[0]) * (k + 0.5) / segs)
        c = col_fn(u) if col_fn else col
        for s in range(sides):
            f = bm.faces.new((A[s], B[s], B[(s + 1) % sides], A[(s + 1) % sides]))
            set_col(bm, f, c)
    if not full:
        for ring, c in ((rings[0], col_fn(math.radians(arc[0])) if col_fn else col),
                        (rings[-1], col_fn(math.radians(arc[1])) if col_fn else col)):
            f = bm.faces.new(ring)
            set_col(bm, f, c)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def hinges(col, strap_col=None, t=1.0, reach=0.9):
    """The classic stopper's hinge hardware (straps across the front to the knuckles on the hinge pin): the parked
    door hangs on these, so every style keeps them at the same place."""
    out = []
    for k, dz in enumerate((-2.8, 2.8)):
        z = R + dz
        out.append(box(f"Strap{k}", (abs(HX) - reach, 0.16, 0.6), ((HX - reach) / 2, -t - 0.08, z), strap_col or col))
        out.append(painted(cylinder(f"Knuckle{k}", 0.36, 0.9, (HX, HY, z - 0.45), col, segs=12), shade(col, 0.8), col))
    return out


def painted(o, lo=None, hi=None):
    if lo is not None:
        gradient(o, lo, hi)
    return o


def padlock(name, x, y, z, s=1.0, body=RED, shackle=GOLD, d=0.36):
    """A small chunky padlock seal (red body, gold shackle, dark keyhole) facing -Y, its back at y: the red lock
    signal. d = body depth."""
    yc = y - d / 2
    return [painted(box(name + "Body", (1.5 * s, d, 1.2 * s), (x, yc, z), body), shade(body, 0.8), RED_HI),
            torus(name + "Shackle", 0.5 * s, 0.16 * s, (x, yc, z + 0.6 * s), shackle, segs=12, sides=6, arc=(0.0, 180.0)),
            cylinder(name + "Key", 0.17 * s, 0.06, (x, y - d + 0.02, z + 0.1 * s), rgb(80, 52, 46), segs=8, rot=(90, 0, 0))]
