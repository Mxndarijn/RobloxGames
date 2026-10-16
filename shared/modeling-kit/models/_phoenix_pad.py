# Phoenix pad helpers (not an asset). Pads swap into one slot: footprint <= 7.96 (8x8 grid), flat top 2.4-3.0.
import math
import bmesh
from lib import *
from lib.shapes import obj_from_bm, _place
from models._phoenix_ranch import *

FOOT = 7.8  # target footprint (existing pads 7.8-7.96)


def lathe(name, profile, segs=16, color_fn=None, pos=(0, 0, 0), phase=0.0):
    """Closed surface of revolution. profile = [(r, z), ...] from the bottom axis point to the top one;
    r == 0 rows collapse to one pole vertex. color_fn(row_index, seg_index, z) -> RGBA per face."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(phase + k * math.tau / segs), r * math.sin(phase + k * math.tau / segs), z))
                          for k in range(segs)])
    faces = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segs):
            k1 = (k + 1) % segs
            if len(a) == 1:
                vs = (a[0], b[k1], b[k])
            elif len(b) == 1:
                vs = (a[k], a[k1], b[0])
            else:
                vs = (a[k], a[k1], b[k1], b[k])
            f = bm.faces.new(vs)
            faces.append((f, i, k))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if color_fn:
        layer = bm.loops.layers.color.new("Col")
        for f, i, k in faces:
            c = color_fn(i, k, f.calc_center_median().z)
            for lp in f.loops:
                lp[layer] = (*c[:3], 1.0)
    _place(bm, pos)
    return obj_from_bm(name, bm, None if color_fn else WOOD)
