# Signature-prop helpers (not an asset) for habitat_prop_<species> (third batch: king ... yeti).
# A signature prop sits on the FRONT of the habitat rim: width (x) <= 1.9, depth (y) <= 1.15, height 0.5..1.4,
# standing on z = 0, front = -Y. ship() checks that contract and prints a PROP line before finish().
import math
import bmesh
from mathutils import Euler, Matrix, Vector
from lib import *
from lib.shapes import obj_from_bm, _place
from models._phoenix_pad import lathe
from models._habitat import prism_crystal, place

MAX_W, MAX_D, MIN_H, MAX_H = 1.9, 1.15, 0.5, 1.4

GOLD, GOLD_LO = rgb(255, 204, 64), rgb(246, 176, 46)  # keep lows close to the base: dark gold browns out
WOOD, WOOD_LO = rgb(206, 142, 84), rgb(160, 104, 62)
ROCK, ROCK_LO = rgb(168, 156, 146), rgb(124, 114, 108)
SNOW, SNOW_LO = rgb(250, 252, 255), rgb(206, 224, 244)
ICE, ICE_LO = rgb(150, 222, 255), rgb(96, 176, 236)


def xf(o, pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Bake scale -> rotation (XYZ degrees) -> translation into a part built at the origin."""
    m = (Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
         @ Matrix.Diagonal((*scale, 1)))
    o.data.transform(m)
    o.data.update()
    return o


def grad(o, lo, hi, z0=None, z1=None):
    """Vertical per-face gradient over the part's own z range (or z0..z1)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    gradient_bm(bm, lo, hi, z0, z1)
    bm.to_mesh(o.data)
    bm.free()
    return o


def paint_faces(o, fn):
    """fn(face_center, face_normal) -> RGBA per face."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        c = fn(f.calc_center_median(), f.normal)
        for lp in f.loops:
            lp[layer] = (*c[:3], 1.0)
    bm.to_mesh(o.data)
    bm.free()
    return o


def floor(o, z=0.0):
    """Clamp verts below z up to z (keeps the export standing on the deck)."""
    for v in o.data.vertices:
        v.co.z = max(v.co.z, z)
    o.data.update()
    return o


def prism(name, pts, z0, z1, color, top=None):
    """Extruded 2D outline (x, z pairs) between y = z0 and y = z1 (a flat cut-out shape, e.g. a flame, a blade)."""
    bm = bmesh.new()
    a = [bm.verts.new((x, z0, z)) for x, z in pts]
    b = [bm.verts.new((x, z1, z)) for x, z in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(pts)
    for k in range(n):
        k1 = (k + 1) % n
        bm.faces.new((a[k], a[k1], b[k1], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, color)


def ship(name, parts, merge=0.0):
    o = finish(name, parts, merge)
    vs = o.data.vertices
    ext = [max(v.co[i] for v in vs) - min(v.co[i] for v in vs) for i in range(3)]
    ok = ext[0] <= MAX_W + 1e-3 and ext[1] <= MAX_D + 1e-3 and MIN_H - 1e-3 <= ext[2] <= MAX_H + 1e-3
    print(f"PROP {name} W {ext[0]:.2f} x D {ext[1]:.2f} x H {ext[2]:.2f} contract={'OK' if ok else 'BROKEN'}")
    return o
