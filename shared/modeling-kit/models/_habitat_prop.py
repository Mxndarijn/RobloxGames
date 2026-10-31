# Signature-prop helpers (not an asset). One small prop per slime species stands on the FRONT of the habitat
# rim band (HABITAT brief): width (x) <= 1.9, depth (y) <= 1.15, height (z) 0.5..1.4, standing on z = 0,
# centred on x/y, front = -Y. ship() finishes the mesh and prints a PROP line against that contract.
import math
from mathutils import Euler, Matrix, Vector
from lib import *
from models._habitat import frame_obj, lathe, place, P

MAX_W, MAX_D, MIN_H, MAX_H = 1.9, 1.15, 0.5, 1.4
CREAM = P["ranch_cream"]


def vgrad(lo, hi, z0, z1, k_fn=None):
    """lathe color_fn: vertical gradient lo -> hi between z0 and z1 (face centre z); k_fn(i, k) = extra shade."""
    def fn(i, k, z):
        t = min(1.0, max(0.0, (z - z0) / max(z1 - z0, 1e-6)))
        c = mix(lo, hi, t)
        return shade(c, k_fn(i, k)) if k_fn else c
    return fn


def xf(o, pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Bake scale, then XYZ rotation (degrees), then translation into a part built at the origin."""
    m = (Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
         @ Matrix.Diagonal(Vector((*scale, 1.0))))
    return frame_obj(o, m)


def regrad(o, lo, hi, z0=None, z1=None):
    """Repaint a (baked, identity-matrix) part with a vertical gradient in its mesh z."""
    return gradient(o, lo, hi, z0, z1)


def ship(name, parts):
    o = finish(name, parts)
    vs = o.data.vertices
    ext = [max(v.co[i] for v in vs) - min(v.co[i] for v in vs) for i in range(3)]
    ok = ext[0] <= MAX_W + 1e-3 and ext[1] <= MAX_D + 1e-3 and MIN_H - 1e-3 <= ext[2] <= MAX_H + 1e-3
    print(f"PROP {name}: W {ext[0]:.2f} (<= {MAX_W}) D {ext[1]:.2f} (<= {MAX_D}) H {ext[2]:.2f} ({MIN_H}-{MAX_H}) "
          f"-> {'OK' if ok else 'OUT OF CONTRACT'}")
    return o
