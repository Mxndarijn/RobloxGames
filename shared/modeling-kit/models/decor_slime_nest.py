# decor_slime_nest: ground decoration between the plots (no collision). A low, cozy straw
# nest (~3.3 across, rim ~0.9 high) holding three pastel slime eggs (pink, lilac, goo),
# one tipped against the rim. Eggs are the hero: smooth shells with lighter round speckles
# (decals hugging the analytic egg); straw = closed lathe bowl + two twisted coils + a few
# loose straws laid along the rim.
import math
import bmesh
from mathutils import Vector, Matrix
from lib import *
from lib.shapes import obj_from_bm

BUTTER = PALETTE["ranch_butter"]
WOOD = PALETTE["ranch_wood"]
WOOD_D = PALETTE["ranch_wood_dark"]
CREAM = PALETTE["ranch_cream"]
STRAW = mix(BUTTER, WOOD, 0.08)
STRAW_D = mix(BUTTER, WOOD, 0.38)
STRAW_HI = mix(BUTTER, CREAM, 0.45)
PINK, LILAC, GOO = PALETTE["ranch_pink"], PALETTE["ranch_lilac"], PALETTE["ranch_goo"]
GOO_HI = PALETTE["ranch_goo_hi"]

DIP_Z = 0.28
parts = []


def set_col(bm, faces_cols, smooth):
    bm.faces.index_update()
    idx = [(f.index, c) for f, c in faces_cols]  # new layers invalidate face refs
    col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    sm = bm.faces.layers.int.get("keep_smooth") or bm.faces.layers.int.new("keep_smooth")
    bm.faces.ensure_lookup_table()
    for fi, c in idx:
        f = bm.faces[fi]
        for lp in f.loops:
            lp[col] = (*c[:3], 1.0)
        f[sm] = int(smooth)


# ---------------------------------------------------------------- nest bowl (lathe)
OUTER = [(0.0, 0.0), (1.25, 0.0), (1.55, 0.12), (1.66, 0.36), (1.6, 0.6), (1.42, 0.78)]
INNER = [(1.18, 0.8), (1.0, 0.66), (0.72, 0.46), (0.4, 0.33), (0.0, DIP_Z)]
PROFILE = OUTER + INNER
N_OUT = len(OUTER)


def lathe(profile, segs, color_fn, seed=1, jit=0.03):
    r = rng(seed)
    bm = bmesh.new()
    rings = []
    for i, (rad, z) in enumerate(profile):
        if rad <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        ring = []
        for k in range(segs):
            a = k * math.tau / segs
            rr = rad * (1 + (r.random() * 2 - 1) * jit) if 0 < i < len(profile) - 1 else rad
            zz = z + ((r.random() * 2 - 1) * 0.025 if 1 < i < len(profile) - 2 else 0)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), zz)))
        rings.append(ring)
    info = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segs):
            k1 = (k + 1) % segs
            if len(a) == 1:
                vs = (a[0], b[k1], b[k])
            elif len(b) == 1:
                vs = (a[k], a[k1], b[0])
            else:
                vs = (a[k], a[k1], b[k1], b[k])
            info.append((i, k, bm.faces.new(vs)))
    set_col(bm, [(f, color_fn(i, k, f.calc_center_median())) for i, k, f in info], False)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm("Bowl", bm)


def bowl_col(i, k, c):
    stripe = [STRAW, STRAW_HI, mix(STRAW, STRAW_D, 0.5)][k % 3]
    if i >= N_OUT:  # inside the dip: plain, darker toward the bottom (hollow)
        t = min(1.0, max(0.0, (c.z - DIP_Z) / 0.5))
        return mix(mix(WOOD, STRAW_D, 0.35), STRAW, 0.15 + 0.6 * t)
    t = min(1.0, c.z / 0.8)
    return mix(mix(STRAW_D, WOOD, 0.3), stripe, 0.45 + 0.55 * t)


parts.append(lathe(PROFILE, 14, bowl_col))


def coil(name, pts_fn, n, tube_r, segs=6, twist=2):
    """Closed straw rope along a loop; diagonal colour bands give the twisted look."""
    bm = bmesh.new()
    pts = [Vector(pts_fn(j / n)) for j in range(n)]
    rings = []
    for j, p in enumerate(pts):
        d = (pts[(j + 1) % n] - pts[j - 1]).normalized()
        side = d.cross(Vector((0, 0, 1))).normalized()
        up = side.cross(d).normalized()
        rings.append([bm.verts.new(p + (side * math.cos(k * math.tau / segs) * 1.1 +
                                        up * math.sin(k * math.tau / segs) * 0.85) * tube_r)
                      for k in range(segs)])
    info = []
    for j in range(n):
        a, b = rings[j], rings[(j + 1) % n]
        for k in range(segs):
            k1 = (k + 1) % segs
            info.append((j, k, bm.faces.new((a[k], a[k1], b[k1], b[k]))))
    bm.normal_update()
    fc = []
    for j, k, f in info:
        base = [STRAW_HI, STRAW, STRAW_D, STRAW][(j * twist + k) % 4]
        lit = max(0.0, f.normal.z) * 0.5 + 0.5
        fc.append((f, mix(mix(base, WOOD, 0.3), base, lit)))
    set_col(bm, fc, False)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def wob(u, a, f, ph):
    return a * math.sin(f * u * math.tau + ph)


parts.append(coil("CoilTop", lambda u: ((1.38 + wob(u, 0.05, 5, 0.7)) * math.cos(u * math.tau),
                                        (1.38 + wob(u, 0.05, 5, 0.7)) * math.sin(u * math.tau),
                                        0.76 + wob(u, 0.05, 3, 0)), 18, 0.17, segs=5))
parts.append(coil("CoilMid", lambda u: ((1.6 + wob(u, 0.03, 4, 1)) * math.cos(u * math.tau + 0.4),
                                        (1.6 + wob(u, 0.03, 4, 1)) * math.sin(u * math.tau + 0.4),
                                        0.42 + wob(u, 0.04, 2, 2)), 14, 0.15, segs=5, twist=3))

# loose straws laid along the rim, tips crossing outward and lifting a little
r = rng(5)
for i in range(5):
    a = i * math.tau / 5 + r.uniform(-0.25, 0.25)
    d = 1 if i % 2 else -1
    span = 0.6 + r.uniform(0, 0.2)
    z0 = 0.84 + r.uniform(-0.04, 0.04)
    pts, rads = [], []
    for u in (0.0, 0.5, 1.0):
        rr = 1.36 + 0.36 * u ** 1.6
        aa = a + d * span * u
        pts.append((rr * math.cos(aa), rr * math.sin(aa), z0 + 0.12 * u ** 2))
        rads.append(0.075 - 0.025 * u)
    t = tube("Straw%d" % i, pts, rads, segs=4)
    parts.append(gradient(t, STRAW_D, STRAW_HI))

# ---------------------------------------------------------------- eggs
EK = 0.14  # >0 = fatter bottom, pointier top
_RMAX = max(math.sin(i * math.pi / 1000) * (1 + EK * math.cos(i * math.pi / 1000)) for i in range(1001))


def egg_surf(t, th, H, R):
    rr = R * math.sin(t) * (1 + EK * math.cos(t)) / _RMAX
    return Vector((rr * math.cos(th), rr * math.sin(th), H / 2 * (1 - math.cos(t))))


def egg_normal(t, th, H, R):
    t = min(max(t, 1e-3), math.pi - 1e-3)
    e = 1e-4
    n = (egg_surf(t, th + e, H, R) - egg_surf(t, th - e, H, R)).cross(
        egg_surf(t + e, th, H, R) - egg_surf(t - e, th, H, R)).normalized()
    c = egg_surf(t, th, H, R)
    if n.dot(Vector((c.x, c.y, c.z - H / 2))) < 0:
        n = -n
    return n


def egg(name, H, R, base, mat, spots, segs=12, rows=8):
    """Smooth egg shell (per-vertex gradient) + flat round speckle decals.
    spots = [(t, th, radius)]; mat = placement matrix (egg bottom pole at local origin)."""
    lo = shade(base, 0.94)
    hi = mix(base, CREAM, 0.32)
    spot_c = mix(base, CREAM, 0.78)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    sm = bm.faces.layers.int.new("keep_smooth")
    rings = []
    for i in range(rows + 1):
        t = math.pi * i / rows
        if i in (0, rows):
            rings.append([bm.verts.new(egg_surf(t, 0, H, R))])
        else:
            rings.append([bm.verts.new(egg_surf(t, (k + 0.5 * (i % 2)) * math.tau / segs, H, R))
                          for k in range(segs)])
    shell = []
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            k1 = (k + 1) % segs
            if len(a) == 1:
                shell.append(bm.faces.new((a[0], b[k1], b[k])))
            elif len(b) == 1:
                shell.append(bm.faces.new((a[k], a[k1], b[0])))
            else:
                shell.append(bm.faces.new((a[k], a[k1], b[k1], b[k])))
    for f in shell:
        for lp in f.loops:
            s = lp.vert.co.z / H
            c = mix(lo, hi, min(1.0, s ** 0.8 * 1.15))
            c = mix(c, spot_c, 0.85 * math.exp(-((s - 0.69) / 0.06) ** 2))  # soft light band
            lp[col] = (*c[:3], 1.0)
        f[sm] = 1
    # speckles: 6-sided slab hugging the shell
    for t, th, sr in spots:
        c0 = egg_surf(t, th, H, R)
        n = egg_normal(t, th, H, R)
        u = n.cross(Vector((0, 0, 1))).normalized()
        v = n.cross(u).normalized()
        top, bot = [], []
        for k in range(5):
            a = k * math.tau / 5
            p = c0 + (u * math.cos(a) + v * math.sin(a)) * sr
            # back onto the shell at that height/azimuth
            tt = math.acos(max(-1, min(1, 1 - 2 * p.z / H)))
            pp = egg_surf(tt, math.atan2(p.y, p.x), H, R)
            nn = egg_normal(tt, math.atan2(p.y, p.x), H, R)
            top.append(bm.verts.new(pp + nn * 0.012))
            bot.append(bm.verts.new(pp - nn * 0.04))
        ct = bm.verts.new(c0 + n * 0.018)
        cb = bm.verts.new(c0 - n * 0.04)
        new = []
        for k in range(5):
            k1 = (k + 1) % 5
            new.append(bm.faces.new((ct, top[k], top[k1])))
            new.append(bm.faces.new((cb, bot[k1], bot[k])))
            new.append(bm.faces.new((top[k], bot[k], bot[k1], top[k1])))
        for f in new:
            for lp in f.loops:
                lp[col] = (*spot_c[:3], 1.0)
            f[sm] = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=mat, verts=bm.verts)
    return obj_from_bm(name, bm)


def place(x, y, z, tilt_deg=0.0, tilt_dir=0.0, spin=0.0):
    rz = Matrix.Rotation(spin, 4, "Z")
    axis = Vector((math.cos(tilt_dir + math.pi / 2), math.sin(tilt_dir + math.pi / 2), 0))
    rt = Matrix.Rotation(math.radians(tilt_deg), 4, axis)
    return Matrix.Translation((x, y, z)) @ rt @ rz


def spots_for(seed, n=5):
    rr = rng(seed)
    out = []
    for i in range(n):
        big = i % 2 == 0
        t = math.pi * ((0.42 + 0.06 * rr.random()) if big else (0.74 + 0.06 * rr.random()))
        th = i * math.tau / n + rr.uniform(-0.3, 0.3) + seed
        out.append((t, th, 0.16 if big else 0.1))
    return out


# hero egg (goo green) at the back, standing; pink front-left; lilac tipped against the right rim
parts.append(egg("EggGoo", 1.35, 0.52, GOO, place(0.12, 0.38, DIP_Z + 0.02, 6, math.radians(110)), spots_for(3, 5)))
parts.append(egg("EggPink", 1.2, 0.47, PINK, place(-0.5, -0.32, DIP_Z + 0.06, 10, math.radians(220)), spots_for(7, 3)))
parts.append(egg("EggLilac", 1.15, 0.46, LILAC, place(0.55, -0.42, DIP_Z + 0.12, 38, math.radians(-30)), spots_for(11, 3)))

o = finish("decor_slime_nest", parts)
a = o.data.attributes.get("keep_smooth")
if a:
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
o["smooth_normals"] = 1
