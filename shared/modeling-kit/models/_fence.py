# Shared builders for the plot fence/gate kit (fence_straight, fence_corner, gate_frame, gate_bar,
# wall_low, sign_board). Not an asset. 1 BU = 1 stud, Z up, front (picket face) faces -Y.
# Grid: SEGMENT = 7 studs (8 per 56-stud plot side); posts sit on the joints.
import math
import bmesh
from mathutils import Vector
from lib import *

SEGMENT = 7.0
GATE_CLEAR = 8.0
FENCE_H = 3.5

# Wood, lifted ~10-20% over PALETTE wood/bark (the Roblox look turns shadow sides ~2x darker).
POST = rgb(156, 104, 66)      # bark +30%: first Roblox look turned shadow sides near-black
POST_LO = rgb(138, 92, 58)
PLANK = rgb(180, 122, 72)     # wood +20%
PLANK_LO = rgb(154, 104, 62)
PLANK_ALT = rgb(168, 112, 66)
RAIL = rgb(162, 110, 68)
CAP = rgb(190, 136, 84)
LIGHT_FACE = rgb(214, 176, 120)  # sign face: light warm plank, near path_sand
STONE = rgb(166, 152, 132)       # stone_warm +10%
STONE_ALT = rgb(152, 140, 124)
STONE_LO = rgb(138, 126, 110)
LATCH = rgb(236, 92, 36)          # saturated mid orange/red: gameplay lock signal


def prism(name, profile, y0, y1, color=None):
    """Closed prism: a convex XZ polygon (counter-clockwise seen from -Y) extruded from y0 to y1."""
    bm = bmesh.new()
    a = [bm.verts.new((x, y0, z)) for x, z in profile]
    b = [bm.verts.new((x, y1, z)) for x, z in profile]
    n = len(profile)
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], b[i], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, color)


def prism_x(name, profile_yz, x0, x1, color=None):
    """Closed prism: a convex YZ polygon extruded along X (roof caps, wedge braces)."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for y, z in profile_yz]
    b = [bm.verts.new((x1, y, z)) for y, z in profile_yz]
    n = len(profile_yz)
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], b[i], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, color)


def picket(name, x, w, h, y0, y1, z0=0.0, tip=0.3, lean=0.0, color=PLANK, lo=PLANK_LO):
    """Pointed plank (dog-ear tip). lean = small sideways tilt of the top (studs) for a hand-made feel."""
    p = [(x - w / 2, z0), (x + w / 2, z0), (x + w / 2 + lean, z0 + h - tip), (x + lean, z0 + h), (x - w / 2 + lean, z0 + h - tip)]
    o = prism(name, p, y0, y1, color)
    gradient(o, lo, color)
    return o


def post(name, x, y, w, h, cap_h=0.3, color=POST, lo=POST_LO, cap=CAP, collar=0.0):
    """Square post standing on z=0 with a cap slab + low pyramid. Returns parts."""
    body = box(name, (w, w, h), (x, y, h / 2), color)
    gradient(body, lo, color)
    out = [body]
    cw = w + 0.14
    slab = box(name + "Cap", (cw, cw, 0.16), (x, y, h + 0.08), cap)
    out.append(slab)
    out.append(cone(name + "Tip", cw / 2 * 1.414, cap_h, (x, y, h + 0.16), cap, segs=4, rot=(0, 0, 45)))
    if collar:
        c = box(name + "Foot", (w + collar, w + collar, 0.35), (x, y, 0.175), lo)
        out.append(c)
    return out


def beam(name, x0, x1, y, z, d, t, color=RAIL, lo=None):
    """Horizontal beam along X from x0 to x1, centred at (y, z), depth d, thickness t."""
    o = box(name, (x1 - x0, d, t), ((x0 + x1) / 2, y, z), color)
    if lo:
        gradient(o, lo, color)
    return o


def strut(name, a, b, d, t, color=RAIL):
    """Plank from point a to b (XZ plane, at y = a[1]); d = depth (Y), t = thickness."""
    a, b = Vector(a), Vector(b)
    v = b - a
    ang = math.degrees(math.atan2(v.z, v.x))
    mid = (a + b) / 2
    return box(name, (v.length, d, t), tuple(mid), color, rot=(0, -ang, 0))
