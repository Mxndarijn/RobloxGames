# Shared helper for rock_a/b/c: chiselled stones = convex hull of jittered points on an
# ellipsoid (big flat facets, the stylised low-poly rock look), cut flat at the ground,
# painted per face: dark underside -> mid sides -> light top facets (+ optional moss cap).
import math, random
import bmesh
from mathutils import Vector
from lib import *


def stone(name, size, pos, seed, n=22, base=None, top=None, moss=None, moss_from=0.72, sink=0.75, lean=0.0, cuts=3):
    """size = (x, y, z) full extents; pos = centre of the footprint on the ground."""
    R = random.Random(seed)
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2]
    sink *= sz  # fraction of the height buried: widest point near the ground, not mid-air
    bm = bmesh.new()
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n):  # even spread (Fibonacci sphere) + jitter: no slivers, no spikes
        y = 1 - 2 * (i + 0.5) / n
        r = math.sqrt(1 - y * y)
        a = i * golden + R.uniform(-0.25, 0.25)
        k = R.uniform(0.86, 1.06)
        x, yy, z = math.cos(a) * r * k, math.sin(a) * r * k, y * k
        z = z * 0.5 + 0.5  # 0..1 up
        z = max(0.0, z) ** 0.85  # fuller top
        t = 1.05 - 0.2 * z  # broad foot, narrower top: sits on the ground
        bm.verts.new((x * sx * t + lean * z, yy * sy * t, z * (sz + sink) - sink))
    bmesh.ops.convex_hull(bm, input=bm.verts)
    # chisel: a few big tilted planar cuts give flat faces and crisp ridges (stylised rock)
    for c in range(cuts):
        a = R.uniform(0, math.tau)
        tilt = R.uniform(0.35, 1.0)
        nrm = Vector((math.cos(a) * tilt, math.sin(a) * tilt, R.uniform(0.3, 1.0))).normalized()
        far = max(abs(v.co.dot(nrm)) for v in bm.verts)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=nrm * far * R.uniform(0.8, 0.9),
                               plane_no=nrm, clear_outer=True)
        bmesh.ops.contextual_create(bm, geom=[e for e in bm.edges if e.is_boundary])
    # cut flat at the ground so it sits, not balances
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0),
                           plane_no=(0, 0, 1), clear_inner=True)
    bmesh.ops.contextual_create(bm, geom=[e for e in bm.edges if e.is_boundary])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.translate(bm, vec=Vector(pos), verts=bm.verts)
    layer = bm.loops.layers.color.new("Col")
    base = base or PALETTE["rock"]
    top = top or shade(base, 1.25)
    zs = [v.co.z for v in bm.verts]
    z1 = max(zs)
    for f in bm.faces:
        nz = f.normal.z
        h = f.calc_center_median().z / max(z1, 1e-6)
        c = mix(shade(base, 0.74), base, min(1, h * 1.6))  # dark foot -> base (not darker: the game sun already darkens the shadow side)
        if nz > 0.35:
            c = mix(c, top, min(1, (nz - 0.35) / 0.45))  # upward facets catch the sky
        if moss and nz > moss_from and h > 0.45:
            c = moss
        if nz < -0.5:
            c = shade(base, 0.66)
        for lp in f.loops:
            lp[layer] = c
    return obj_from_bm(name, bm)


def pebble(name, r, pos, seed, base, flat=0.55):
    return stone(name, (r * 2, r * 1.8, r * 2 * flat), pos, seed, n=14, base=base, sink=0.6, cuts=1)
