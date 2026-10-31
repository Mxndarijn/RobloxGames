# Signature-prop helpers (not an asset) for habitat_prop_<species>: a lathe with per-face paint, a world-matrix
# mover, a floor clamp and a size check against the front-rim slot (w <= 1.9, d <= 1.15, h 0.5..1.4).
import math
import bmesh, bpy
from mathutils import Euler, Matrix, Vector
from lib import *

SLOT_W, SLOT_D, SLOT_H = 1.9, 1.15, 1.4

# bright prop palette (lifted values: the Roblox look darkens shadows a lot)
WHITE = rgb(250, 248, 240)
BLACK = rgb(52, 48, 58)  # "black" lifted; true black goes to a hole in game
LEAF = rgb(110, 196, 84)
LEAF_D = rgb(70, 150, 70)
PINK = rgb(250, 140, 180)
PINK_D = rgb(226, 96, 146)
RED = rgb(234, 62, 60)
YELLOW = rgb(255, 210, 60)
GOLD = rgb(250, 186, 50)
HONEY = rgb(255, 172, 30)
WOOD = rgb(196, 138, 86)
WOOD_D = rgb(150, 100, 62)
TERRA = rgb(222, 112, 70)
STONE = rgb(170, 164, 156)
CYAN = rgb(110, 214, 250)


def lathe(name, prof, pos=(0, 0, 0), segs=12, col=WHITE, phase=0.0, sx=1.0, sy=1.0, smooth=False):
    """Surface of revolution round Z. prof = [(r, z), ...] bottom to top; r = 0 at an end closes it to a point,
    otherwise the end is capped with an n-gon. col = colour or fn(face_centre_local, ring_index, seg_index)."""
    bm = bmesh.new()
    rings = []
    for (r, z) in prof:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((math.cos(phase + k * math.tau / segs) * r * sx,
                                        math.sin(phase + k * math.tau / segs) * r * sy, z)) for k in range(segs)])
    meta = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segs):
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                f = bm.faces.new((a[0], b[k], b[(k + 1) % segs]))
            elif len(b) == 1:
                f = bm.faces.new((a[k], a[(k + 1) % segs], b[0]))
            else:
                f = bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
            meta.append((f, i, k))
    if len(rings[0]) > 1:
        f = bm.faces.new(list(reversed(rings[0])))
        meta.append((f, -1, 0))
    if len(rings[-1]) > 1:
        f = bm.faces.new(rings[-1])
        meta.append((f, len(rings) - 1, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    for f, i, k in meta:
        c = col(f.calc_center_median(), i, k) if callable(col) else col
        for lp in f.loops:
            lp[layer] = c
    bmesh.ops.translate(bm, vec=Vector(pos), verts=bm.verts)
    o = obj_from_bm(name, bm)
    for p in o.data.polygons:
        p.use_smooth = smooth
    return o


def move(o, pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Bake scale, then rotation (degrees XYZ), then translation into the mesh."""
    m = Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4() \
        @ Matrix.Diagonal(Vector(scale)).to_4x4()
    o.data.transform(m)
    o.data.update()
    return o


def floor(o, z=0.0):
    for v in o.data.vertices:
        v.co.z = max(v.co.z, z)
    o.data.update()
    return o


def paint(o, fn):
    """Repaint per face: fn(face_centre, face_normal) -> colour (same "Col" layer type the lib builders use)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        c = fn(f.calc_center_median(), f.normal)
        for lp in f.loops:
            lp[layer] = c
    bm.to_mesh(o.data)
    bm.free()
    return o


def flower(name, r, pos, col, centre=YELLOW, petals=5, rot=(90, 0, 0), thick=0.05, inner=0.5):
    """Flat scalloped flower disc (petals = alternating radii), facing +Z before rot; rot (90,0,0) faces it -Y.
    Plus a centre bead. ~4*petals + 20 tris."""
    bm = bmesh.new()
    n = petals * 3
    top, bot = [], []
    for k in range(n):
        a = (k - 0.5) * math.tau / n
        rr = r * (1.0, 1.0, inner)[k % 3]  # blunt petal tips, notch between petals
        top.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, thick / 2)))
        bot.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, -thick / 2)))
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    for k in range(n):
        bm.faces.new((bot[k], bot[(k + 1) % n], top[(k + 1) % n], top[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = move(obj_from_bm(name, bm, col), pos, rot)
    c = move(cylinder(name + "C", r * 0.36, thick * 0.9, (0, 0, thick / 2), centre, segs=6, r_top=r * 0.26), pos, rot)
    return [o, c]


def smooth(o):
    """Mark a part smooth shaded (survives join; ship() re-applies it after finish() forces everything flat)."""
    a = o.data.attributes.get("keep_smooth") or o.data.attributes.new("keep_smooth", "INT", "FACE")
    for d in a.data:
        d.value = 1
    return o


def ship(name, parts):
    """finish() plus smooth faces restored (keep_smooth) and the slot check line."""
    o = finish(name, parts)
    a = o.data.attributes.get("keep_smooth")
    if a is not None:
        flags = [d.value for d in a.data]
        for p, f in zip(o.data.polygons, flags):
            p.use_smooth = bool(f)
        o.data.attributes.remove(a)
        if any(flags):
            o["smooth_normals"] = 1
    vs = o.data.vertices
    ext = [max(v.co[i] for v in vs) - min(v.co[i] for v in vs) for i in range(3)]
    ok = ext[0] <= SLOT_W + 1e-3 and ext[1] <= SLOT_D + 1e-3 and 0.5 <= ext[2] <= SLOT_H + 1e-3
    print(f"SLOT {'OK' if ok else 'OVER'} w={ext[0]:.2f} d={ext[1]:.2f} h={ext[2]:.2f} (max {SLOT_W} x {SLOT_D} x {SLOT_H})")
    return o
