# Slime pool builder (not an asset). One species = ONE fully coloured mesh: body shape, baked
# pattern, accessories and its signature face all in vertex colours, MeshPart.Color = white.
# That is what lets every species look different (the old kit shared 7 tinted meshes).
#
# Frame while modelling: studs, bottom centre at the origin, Z up, face towards -Y. A size-1
# slime is about 3 studs wide (Config.SLIME_BASE_DIAMETER); keep bodies 2.6-3.4 wide, 2.4-3.6 tall
# (accessories may stick out further). ship() turns the mesh 180 deg for Roblox (-Z front)
# unless SLIME_PREVIEW=1.
#
# Quick tour (see models/pool/slime_gummy.py for a complete species):
#   b = Body([(0, 1.0), (0.3, 1.45), (1.2, 1.5), (2.4, 0.9), (3.0, 0)], color=hexc("6ee05a"))
#   parts = [b.obj]
#   parts += spots(b, [(yaw, z, r), ...], color)           # decals projected onto the body
#   parts += Face(b).eyes("round").mouth("grin").cheeks().parts
#   parts += [ball("Nose", 0.1, (0, -1.5, 1.4), PINK)]     # any accessory primitive
#   ship("slime_gummy", parts)
import json, math, os
import bmesh, bpy
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree
from lib import *

# ---------------------------------------------------------------- shared colours
INK = rgb(30, 22, 40)
WHITE = rgb(255, 255, 255)
MOUTH = rgb(92, 24, 48)
TONGUE = rgb(255, 110, 140)
CHEEK = rgb(255, 140, 170)
GOLD_D, GOLD, GOLD_L = rgb(206, 128, 24), rgb(255, 194, 50), rgb(255, 240, 150)


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def keep(o, smooth=True):
    """flag faces smooth (goo) or flat (crisp parts); a face attribute, so it survives join()."""
    for p in o.data.polygons:
        p.use_smooth = smooth
    a = o.data.attributes.get("keep_smooth") or o.data.attributes.new("keep_smooth", "INT", "FACE")
    a.data.foreach_set("value", [int(smooth)] * len(o.data.polygons))
    return o


def paint_fn(o, fn):
    """repaint every corner of o with fn(world_pos, normal) -> rgba (o has no object transform)."""
    bm = bmesh.new(); bm.from_mesh(o.data)
    col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    bm.normal_update()
    for f in bm.faces:
        for lp in f.loops:
            lp[col] = fn(lp.vert.co.copy(), lp.vert.normal.copy())
    bm.to_mesh(o.data); bm.free()
    return o


def along(c0, c1, a, b, power=1.0):
    """colour fn: c0 at point a -> c1 at point b (projection on the a-b axis)."""
    a, b = Vector(a), Vector(b)
    ab = b - a
    L2 = max(ab.length_squared, 1e-9)

    def fn(p, n=None):
        t = min(1.0, max(0.0, (p - a).dot(ab) / L2))
        return mix(c0, c1, t ** power)
    return fn


def zgrad(c0, c1, z0, z1):
    return along(c0, c1, (0, 0, z0), (0, 0, z1))


# ---------------------------------------------------------------- projection surfaces
SURFACES = {}  # name -> BVHTree, every Body registers itself; register(obj) adds more (caps, hats)


def register(o, name=None):
    bm = bmesh.new(); bm.from_mesh(o.data)
    bm.transform(o.matrix_world)
    SURFACES[name or o.name] = BVHTree.FromBMesh(bm)
    bm.free()
    return o


def cast(origin, d, on=None):
    best = None
    for k, bvh in SURFACES.items():
        if on and k not in on:
            continue
        loc, n, _, dist = bvh.ray_cast(origin, d)
        if loc is not None and (best is None or dist < best[2]):
            best = (loc, n, dist)
    return best


def catmull(pts, n):
    """Catmull-Rom through (z, r) points, n samples per segment: smooth profiles from few points."""
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(tuple(0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in range(2)))
    out.append(tuple(pts[-1]))
    return out


# ---------------------------------------------------------------- body
TUCK = 0.8  # studs: rounded underside of every species body (Body(tuck=...))
DOME = 0.75  # share of the way the upper body bends to a full dome (Body(dome=...)); no gumdrop point


def round_bottom(prof, h, n=6):
    """profile with its flat bottom disc replaced by a quarter ellipse: from one vertex at z0 out to
    the profile's own radius at z0 + h, meeting it with a vertical tangent."""
    z0 = prof[0][0]
    zh = z0 + h
    rh = Body.radius_of(prof, zh)
    out = []
    for k in range(1, n + 1):
        t = k / n * math.pi / 2
        out.append((z0 + h * (1 - math.cos(t)), rh * math.sin(t)))
    out[-1] = (zh, rh)
    return [(z0, 0.0)] + out + [p for p in prof if p[0] > zh + 0.012]


def round_top(prof, amount, p=2.3, n=12):
    """profile whose upper body bends towards a full dome, so no species ends in a gumdrop point:
    from the widest ring up to the top, the radius moves `amount` (0..1) of the way to a
    superellipse cap (exponent p; 2 = ellipse, higher = fuller) that reaches the top flat. The
    height, the widest ring and everything below it are unchanged, so faces and the parts that
    sit on top stay where they were."""
    H = prof[-1][0]
    rmax = max(r for _, r in prof)
    zmax = max(z for z, r in prof if r >= 0.97 * rmax)
    if H - zmax < 0.05:
        return prof
    out = [q for q in prof if q[0] <= zmax]
    for k in range(1, n + 1):
        u = k / n
        z = zmax + (H - zmax) * u
        cap = rmax * max(0.0, 1 - u ** p) ** (1 / p)
        r = Body.radius_of(prof, z)
        out.append((z, r + (cap - r) * amount))
    out[-1] = (H, 0.0)
    return out


class Body:
    """Surface of revolution (smooth shaded) with optional oval cross-section, lean, bumps and a
    painted pattern. Yaw a: 0 = front (-Y), +90 = the slime's left / viewer's right (+X).

    profile: [(z, r), ...] bottom to top. First r > 0 -> flat bottom; last r == 0 -> tip vertex.
    tuck: height (studs) of a rounded underside that replaces the flat bottom: the profile below
      z0 + tuck becomes a quarter ellipse down to a single bottom vertex, so the slime rests on a
      curved belly instead of a disc. Default TUCK for the main "Body", 0 (flat) for other names.
    dome: 0..1, how far the upper body (widest ring to top) bends towards a full dome that reaches
      the top flat, for profiles that end in a point or a narrow top (round_top). Default DOME for
      the main "Body", 0 (keep the shape) for other names.
    sub: Catmull-Rom samples per profile segment (smooth from few points).
    sx, sy: cross-section scale (x wide, y deep). lean(z) -> y offset. bump(a, z) -> radius factor add.
    color: base rgba, or paint(a, z, p) -> rgba for a pattern painted per corner (soft edges).
    bands: [(z0, z1, rgba)] crisp horizontal stripes (rings are inserted at z0/z1, painted per face).
    sectors: fn(a, z) -> rgba or None, crisp per-face colour (vertical stripes, cow patches...).
    shade: 0..1 strength of the baked foot shadow / crown light / gloss highlight.
    """

    def __init__(self, profile, color=rgb(120, 220, 120), segs=40, sub=3, sx=1.0, sy=1.0, lean=None, bump=None,
                 paint=None, bands=(), sectors=None, shade=1.0, gloss=1.0, name="Body", register_surface=True,
                 tuck=None, dome=None):
        self.name = name
        self.sx, self.sy = sx, sy
        self.lean = lean or (lambda z: 0.0)
        self.bump = bump or (lambda a, z: 0.0)
        prof = catmull(profile, sub)
        self.prof = prof
        for z0, z1, _ in bands:
            for z in (z0, z1):
                prof.append((z, self.radius(z)))
        prof.sort()
        ded = [prof[0]]
        for p in prof[1:]:
            if p[0] - ded[-1][0] > 0.012:
                ded.append(p)
            else:  # keep the exact band edge
                ded[-1] = p if any(abs(p[0] - z) < 1e-6 for b in bands for z in b[:2]) else ded[-1]
        if ded[-1][0] < profile[-1][0] - 1e-6:
            ded.append(tuple(profile[-1]))
        self.prof = prof = ded
        tuck = (TUCK if name == "Body" else 0.0) if tuck is None else tuck
        if tuck > 0 and prof[0][1] > 0.2:
            self.prof = prof = round_bottom(prof, min(tuck, 0.3 * (prof[-1][0] - prof[0][0])))
        dome = (DOME if name == "Body" else 0.0) if dome is None else dome
        if dome > 0 and len(prof) > 3 and prof[-1][1] < 0.3 * max(r for _, r in prof):
            if prof[-1][1] > 1e-4:  # a narrow flat top: close it at the same height
                prof = prof + [(prof[-1][0] + 1e-3, 0.0)]
            self.prof = prof = round_top(prof, dome)
        self.H = prof[-1][0]
        self.color, self.paint, self.bands, self.sectors = color, paint, bands, sectors
        self.shade, self.gloss = shade, gloss
        self.obj = self._build(segs)
        if register_surface:
            register(self.obj, name)

    @staticmethod
    def radius_of(P, z):
        """radius of profile P at height z (piecewise linear; the end radii outside it)."""
        if z <= P[0][0]:
            return P[0][1]
        for (z0, r0), (z1, r1) in zip(P, P[1:]):
            if z0 <= z <= z1:
                return r0 + (r1 - r0) * (z - z0) / max(z1 - z0, 1e-9)
        return P[-1][1]

    def radius(self, z):
        return Body.radius_of(self.prof, z)

    def point(self, a, z, extra=0.0):
        """surface point at yaw a (radians, 0 front) and height z (+extra studs radially)."""
        r = self.radius(z) * (1 + self.bump(a, z)) + extra
        return Vector((math.sin(a) * r * self.sx, -math.cos(a) * r * self.sy + self.lean(z), z))

    def _build(self, segs):
        bm = bmesh.new()
        prof = self.prof
        tip = prof[-1][1] < 1e-4
        ring_prof = prof[:-1] if tip else prof
        if ring_prof[0][1] < 1e-4:  # rounded bottom: the pole vertex below closes it
            ring_prof = ring_prof[1:]
        rings = []
        for z, r in ring_prof:
            rings.append([bm.verts.new(self.point(i * math.tau / segs, z)) for i in range(segs)])
        for a, b in zip(rings, rings[1:]):
            for i in range(segs):
                j = (i + 1) % segs
                bm.faces.new((a[i], a[j], b[j], b[i]))
        top = bm.verts.new((0, self.lean(self.H), self.H))
        bot = bm.verts.new((0, self.lean(prof[0][0]), prof[0][0]))
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((rings[-1][i], rings[-1][j], top))
            bm.faces.new((rings[0][j], rings[0][i], bot))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        self._paint(bm)
        return keep(obj_from_bm(self.name, bm), True)

    def base(self, a, z, p):
        return self.paint(a, z, p) if self.paint else self.color

    def lit(self, c, p):
        """bake soft volume: darker foot, lighter crown, a glossy highlight blob upper-front-left."""
        if self.shade <= 0:
            return c
        H = self.H
        k = 1.0 - self.shade * 0.22 * (1 - smoothstep(0.0, 0.32 * H, p.z))
        c = shade(c, k)
        c = mix(c, WHITE, self.shade * 0.10 * smoothstep(0.45 * H, H, p.z))
        d = (p - Vector((0, 0, 0.45 * H))).normalized()
        key = Vector((-0.5, -0.62, 0.62)).normalized()
        h = max(0.0, d.dot(key))
        c = mix(c, WHITE, self.gloss * 0.75 * smoothstep(0.91, 0.975, h))
        return c

    def _paint(self, bm):
        col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
        for f in bm.faces:
            cz = f.calc_center_median()
            ca = math.atan2(cz.x / self.sx, -(cz.y - self.lean(cz.z)) / self.sy)
            face_c = None
            for z0, z1, c in self.bands:
                if z0 <= cz.z <= z1:
                    face_c = c
            if self.sectors:
                s = self.sectors(ca, cz.z)
                if s is not None:
                    face_c = s
            for lp in f.loops:
                p = lp.vert.co
                a = math.atan2(p.x / self.sx, -(p.y - self.lean(p.z)) / self.sy) if (abs(p.x) + abs(p.y)) > 1e-6 else ca
                c = face_c if face_c is not None else self.base(a, p.z, p)
                lp[col] = self.lit(c, p)


# ---------------------------------------------------------------- decals (projected, crisp)
class Frame:
    """projection frame: (u, v) -> O + u*U + v*V, rays travel along -D (towards the body)."""

    def __init__(self, O, U, V, D):
        self.O, self.U, self.V, self.D = Vector(O), Vector(U).normalized(), Vector(V).normalized(), Vector(D).normalized()


def frame_at(yaw=0.0, z=0.0, tilt=0.0, cx=0.0, cy=0.0):
    """frame looking at the body from yaw (deg, 0 = front) tilted up by tilt (deg); (0, 0) aims at
    the axis point (cx, cy, z). frame_at() with z=0 is the FRONT frame: (u, v) = (x, z) in studs."""
    a, t = math.radians(yaw), math.radians(tilt)
    d = Vector((math.sin(a), -math.cos(a), 0))
    U = Vector((math.cos(a), math.sin(a), 0))
    d = (d * math.cos(t) + Vector((0, 0, 1)) * math.sin(t)).normalized()
    V = d.cross(U)
    return Frame((cx, cy, z), U, V, d)


FRONT = frame_at()
TOP = Frame((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1))  # from above: (u, v) = (x, y)


def densify(poly, step=0.1):
    out = []
    n = len(poly)
    for i in range(n):
        a, b = Vector(poly[i]), Vector(poly[(i + 1) % n])
        k = max(1, int((b - a).length / step))
        for j in range(k):
            out.append(tuple(a + (b - a) * (j / k)))
    return out


# flat_decals(k): every later decal() follows the curve (conform_decal) and sits k times as far off the
# surface. Big meshes (bosses at 3x) need it: a flat slab's edges lift off a curved body and its
# thickness reads as a raised sticker.
DECALS = {"scale": 1.0, "conform": False}


def flat_decals(scale=0.5):
    DECALS["scale"], DECALS["conform"] = scale, True


def _inside(pt, poly):
    x, y = pt
    c = False
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            c = not c
    return c


def conform_decal(name, poly, color, frame=FRONT, off=0.008, th=0.012, on=None, step=0.08, cell=0.12):
    """decal() with inner grid points, so the whole slab follows the curve instead of its rim only."""
    from mathutils.geometry import delaunay_2d_cdt
    poly = densify(poly, step)
    n = len(poly)
    us, vs = [p[0] for p in poly], [p[1] for p in poly]
    inner = []
    u = min(us) + cell / 2
    while u < max(us):
        v = min(vs) + cell / 2
        while v < max(vs):
            if _inside((u, v), poly) and min((u - a) ** 2 + (v - b) ** 2 for a, b in poly) > (cell * 0.45) ** 2:
                inner.append((u, v))
            v += cell
        u += cell
    pts = [Vector(p) for p in poly + inner]
    V2, _, F, *_ = delaunay_2d_cdt(pts, [(i, (i + 1) % n) for i in range(n)], [list(range(n))], 1, 1e-6)
    F = [f for f in F if _inside(tuple(sum((V2[i] for i in f), Vector((0, 0))) / len(f)), poly)]
    bm = bmesh.new()
    top, bot = {}, {}
    for f in F:
        for i in f:
            if i in top:
                continue
            uu, vv = V2[i]
            hit = cast(frame.O + frame.U * uu + frame.V * vv + frame.D * 12, -frame.D, on)
            if hit is None:
                raise ValueError(f"conform_decal {name}: ({uu:.2f}, {vv:.2f}) misses every surface")
            loc, nn, _ = hit
            if nn.dot(frame.D) < 0:
                nn = -nn
            nn = (nn * 0.6 + frame.D * 0.4).normalized()
            bot[i] = bm.verts.new(loc + nn * off)
            top[i] = bm.verts.new(loc + nn * (off + th))
    ecount = {}
    for f in F:
        bm.faces.new([top[i] for i in f])
        bm.faces.new([bot[i] for i in reversed(f)])
        for a, b in zip(f, f[1:] + f[:1]):
            ecount[(a, b)] = ecount.get((a, b), 0) + 1
    for (a, b) in ecount:
        if (b, a) not in ecount:
            bm.faces.new((bot[a], bot[b], top[b], top[a]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, False)


def grid_decal(name, poly, color, frame=FRONT, off=0.008, th=0.012, on=None, step=0.08, cell=0.12):
    """conform_decal for big face parts (mouths, carvings), scaled by flat_decals() like decal()."""
    k = DECALS["scale"]
    return conform_decal(name, poly, color, frame, off=off * k, th=th * k, on=on, step=step, cell=cell)


def decal(name, poly, color, frame=FRONT, off=0.02, th=0.025, on=None, step=0.12):
    """thin closed slab hugging the surface: 2D polygon (u, v) projected along the frame, `off` above
    the surface, `th` thick. Layer details with a bigger off (pupil 0.03, catchlight 0.05).
    color may be a fn(p, n) for gradients. After flat_decals() it follows the curve, closer in."""
    if DECALS["conform"]:
        k = DECALS["scale"]
        return conform_decal(name, poly, color, frame, off=off * k, th=th * k, on=on, step=min(step or 0.08, 0.08))
    poly = densify(poly, step) if step else poly
    bm = bmesh.new()
    back, front = [], []
    for u, v in poly:
        o = frame.O + frame.U * u + frame.V * v + frame.D * 12
        hit = cast(o, -frame.D, on)
        if hit is None:
            raise ValueError(f"decal {name}: ({u:.2f}, {v:.2f}) misses every surface")
        loc, n, _ = hit
        if n.dot(frame.D) < 0:
            n = -n
        n = (n * 0.6 + frame.D * 0.4).normalized()  # steady offset over facets
        back.append(bm.verts.new(loc + n * off))
        front.append(bm.verts.new(loc + n * (off + th)))
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    k = len(poly)
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((back[i], back[j], front[j], front[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, False)


# 2D shapes (u, v) for decals and slabs
def oval(cu, cv, w, h, n=16, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    return [(cu + math.cos(k * math.tau / n) * w / 2 * c - math.sin(k * math.tau / n) * h / 2 * s,
             cv + math.cos(k * math.tau / n) * w / 2 * s + math.sin(k * math.tau / n) * h / 2 * c) for k in range(n)]


def arc(cu, cv, rad, a0, a1, width, n=10, squash=1.0):
    """thick stroke along a circular arc (degrees, 0 = +u, 90 = up), one closed polygon."""
    outer, inner = [], []
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        outer.append((cu + math.cos(a) * (rad + width / 2), cv + math.sin(a) * (rad + width / 2) * squash))
        inner.append((cu + math.cos(a) * (rad - width / 2), cv + math.sin(a) * (rad - width / 2) * squash))
    return outer + list(reversed(inner))


def half_oval(cu, cv, w, h, n=12, up=False):
    """D shape: flat top edge at cv, round bottom (open mouth). up=True: flat bottom, round top."""
    pts = []
    for k in range(n + 1):
        a = math.pi + math.pi * k / n
        y = math.sin(a) * h
        pts.append((cu + math.cos(a) * w / 2, cv + (-y if up else y)))
    return pts


def star(cu, cv, r_out, r_in=None, n=5, rot=90.0):
    r_in = r_in or r_out * 0.45
    return [(cu + math.cos(math.radians(rot + k * 180 / n)) * (r_out if k % 2 == 0 else r_in),
             cv + math.sin(math.radians(rot + k * 180 / n)) * (r_out if k % 2 == 0 else r_in)) for k in range(2 * n)]


def heart(cu, cv, s, n=24):
    pts = []
    for k in range(n):
        t = math.tau * k / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cu + x * s / 32, cv + y * s / 32))
    return pts


def rect(cu, cv, w, h, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    return [(cu + x * c - y * s, cv + x * s + y * c) for x, y in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2))]


def zigzag(u0, u1, cv, amp, n, width):
    """zig-zag stroke from u0 to u1 (lightning mouth, stitches)."""
    top, bot = [], []
    for k in range(n + 1):
        u = u0 + (u1 - u0) * k / n
        v = cv + (amp if k % 2 else -amp)
        top.append((u, v + width / 2)); bot.append((u, v - width / 2))
    return top + list(reversed(bot))


def spots(body, specs, color, n=14, on=None, off=0.012, th=0.02):
    """round spots on any side: specs [(yaw_deg, z, w, h?, rot?)]; the spot is aimed at the body axis."""
    out = []
    for k, s in enumerate(specs):
        yaw, z, w = s[0], s[1], s[2]
        h = s[3] if len(s) > 3 else w
        rot = s[4] if len(s) > 4 else 0.0
        tilt = s[5] if len(s) > 5 else 0.0
        out.append(decal(f"Spot{k}", oval(0, 0, w, h, n=n, rot=math.radians(rot)), color,
                         frame_at(yaw, z, tilt), off=off, th=th, on=on or [body.name]))
    return out


def blotch(seed, w, h, n=14, wobble=0.28):
    """irregular round patch (cow spots, moss): oval with smooth noise on the radius."""
    pts = []
    for k in range(n):
        a = k * math.tau / n
        r = 1 + wobble * noise.noise(Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, seed * 3.7)))
        pts.append((math.cos(a) * w / 2 * r, math.sin(a) * h / 2 * r))
    return pts


# ---------------------------------------------------------------- face kit
class Face:
    """Signature faces. All coords on the FRONT frame (u = x, v = z, studs).
    Face(body, eye_u=0.5, eye_v=None, mouth_v=None, s=1.0): eye_v defaults to 0.55 * body height.
    Chain: Face(b).eyes("round").mouth("grin").brows("angry").cheeks().parts
    """

    def __init__(self, body, eye_u=0.5, eye_v=None, mouth_v=None, s=1.0, ink=INK, mouth_col=MOUTH, on=None):
        self.b = body
        self.on = on or [body.name]  # surfaces the face sits on; add a skin patch (register it) to sit on top of it
        global FACE_ON
        FACE_ON = self.on  # the rig's blink lids land on the same surfaces
        self.eu = eye_u
        self.ev = eye_v if eye_v is not None else 0.55 * body.H
        self.mv = mouth_v if mouth_v is not None else self.ev - 0.38 * s
        self.s = s
        self.ink, self.mc = ink, mouth_col
        self.parts = []

    def d(self, name, poly, color, off=0.02, th=0.025):
        self.parts.append(decal(name, poly, color, FRONT, off=off, th=th, on=self.on))
        return self

    def _eye_round(self, side, w, h, u=None, v=None, lid=0.0, tilt=0.0, iris=None, look=(0, 0), hi=True):
        u = (side * self.eu if u is None else u) + look[0]
        v = (self.ev if v is None else v) + look[1]
        pts = oval(u, v, w, h, n=16)
        if lid:
            topv = v + h / 2 - lid * h
            pts = [(x, min(y, topv + (x - u) * math.tan(tilt) * side)) for x, y in pts]
        self.d(f"Eye{side}", pts, self.ink, off=0.015)
        if iris:  # coloured iris ring inside the dark eye, pupil stays dark
            ip = oval(u, v - h * 0.06, w * 0.72, h * 0.68, n=14)
            if lid:
                ip = [(x, min(y, topv - 0.02 + (x - u) * math.tan(tilt) * side)) for x, y in ip]
            self.d(f"Iris{side}", ip, iris, off=0.03, th=0.012)
            self.d(f"Pupil{side}", oval(u, v - h * 0.08, w * 0.36, h * 0.36, n=12), self.ink, off=0.04, th=0.01)
        if hi:
            hv = v + h * 0.18 - lid * h * 0.55
            self.d(f"EyeHi{side}", oval(u - w * 0.16, hv, w * 0.36, h * 0.3, n=10), WHITE, off=0.05, th=0.012)
            self.d(f"EyeHi2{side}", oval(u + w * 0.17, v - h * 0.22, w * 0.15, w * 0.15, n=8), WHITE, off=0.05, th=0.012)

    def eyes(self, kind="round", w=0.48, h=0.66, iris=None, color=None, gap=None, look=(0, 0), **kw):
        """kinds: round, big, dot, happy (^ ^), sleepy (closed), sly (half-lid), angry (slanted lid),
        sad, wide, star, heart, cyclops, googly, x, wink, shades, visor, glow, spiral, sparkle."""
        s, eu, ev = self.s, self.eu, self.ev
        w, h = w * s, h * s
        if gap is not None:
            self.eu = eu = gap
        sides = (-1, 1)
        if kind in ("round", "big", "wide"):
            k = {"round": 1.0, "big": 1.22, "wide": 1.12}[kind]
            for sd in sides:
                self._eye_round(sd, w * k, h * k, iris=iris, look=look)
        elif kind == "dot":
            for sd in sides:
                self.d(f"Eye{sd}", oval(sd * eu + look[0], ev + look[1], w * 0.42, w * 0.5, n=12), self.ink)
                self.d(f"EyeHi{sd}", oval(sd * eu - w * 0.06 + look[0], ev + w * 0.08 + look[1], w * 0.14, w * 0.14, n=8), WHITE, off=0.05, th=0.012)
        elif kind == "happy":
            for sd in sides:
                self.d(f"Eye{sd}", arc(sd * eu, ev - 0.06 * s, 0.17 * s, 18, 162, 0.085 * s), self.ink)
        elif kind == "sleepy":
            for sd in sides:
                self.d(f"Eye{sd}", arc(sd * eu, ev + 0.04 * s, 0.16 * s, 200, 340, 0.075 * s), self.ink)
                self.d(f"Lash{sd}", arc(sd * (eu + 0.17 * s), ev - 0.03 * s, 0.06 * s, 250 if sd > 0 else 200, 290 if sd > 0 else 240, 0.04 * s, n=4), self.ink)
        elif kind == "sly":
            for sd in sides:
                self._eye_round(sd, w, h * 0.95, lid=0.45, tilt=-0.12, iris=iris, look=look)
        elif kind == "angry":
            for sd in sides:
                self._eye_round(sd, w, h * 0.92, lid=0.36, tilt=0.42, iris=iris, look=look)
        elif kind == "sad":
            for sd in sides:
                self._eye_round(sd, w, h * 0.92, lid=0.3, tilt=-0.42, iris=iris, look=look)
        elif kind == "star":
            c = color or GOLD
            for sd in sides:
                self.d(f"Eye{sd}", star(sd * eu, ev, 0.34 * s, 0.17 * s), self.ink, off=0.015)
                self.d(f"EyeC{sd}", star(sd * eu, ev, 0.25 * s, 0.12 * s), c, off=0.035, th=0.012)
                self.d(f"EyeHi{sd}", oval(sd * eu - 0.05 * s, ev + 0.07 * s, 0.07 * s, 0.07 * s, n=8), WHITE, off=0.05, th=0.012)
        elif kind == "heart":
            c = color or rgb(255, 60, 110)
            for sd in sides:
                self.d(f"Eye{sd}", heart(sd * eu, ev, 0.62 * s), self.ink, off=0.015)
                self.d(f"EyeC{sd}", heart(sd * eu, ev + 0.01 * s, 0.48 * s), c, off=0.035, th=0.012)
                self.d(f"EyeHi{sd}", oval(sd * eu - 0.09 * s, ev + 0.08 * s, 0.08 * s, 0.06 * s, n=8), WHITE, off=0.05, th=0.012)
        elif kind == "cyclops":
            self._eye_round(0, w * 1.7, h * 1.5, u=0.0, iris=iris, look=look)
        elif kind == "googly":  # derpy: white balls with off-centre pupils, different sizes
            for sd, k, pl in ((-1, 1.0, (0.06, -0.05)), (1, 0.82, (-0.07, 0.06))):
                u = sd * eu
                self.d(f"Eye{sd}", oval(u, ev, w * 1.1 * k, w * 1.1 * k, n=18), self.ink, off=0.012)
                self.d(f"EyeW{sd}", oval(u, ev, w * 0.98 * k, w * 0.98 * k, n=18), WHITE, off=0.025, th=0.012)
                self.d(f"Pupil{sd}", oval(u + pl[0] * s, ev + pl[1] * s, w * 0.42 * k, w * 0.42 * k, n=12), self.ink, off=0.04, th=0.012)
                self.d(f"EyeHi{sd}", oval(u + pl[0] * s - 0.04 * s, ev + pl[1] * s + 0.05 * s, w * 0.12, w * 0.12, n=8), WHITE, off=0.055, th=0.01)
        elif kind == "x":
            for sd in sides:
                self.d(f"EyeA{sd}", rect(sd * eu, ev, 0.36 * s, 0.08 * s, math.radians(45)), self.ink)
                self.d(f"EyeB{sd}", rect(sd * eu, ev, 0.36 * s, 0.08 * s, math.radians(-45)), self.ink, off=0.03)
        elif kind == "wink":
            self._eye_round(-1, w, h, iris=iris, look=look)
            self.d("Eye1", arc(eu, ev - 0.06 * s, 0.17 * s, 18, 162, 0.085 * s), self.ink)
        elif kind == "shades":  # cool sunglasses: two rounded lenses + bridge, glint stripes
            lens = color or rgb(24, 20, 34)
            for sd in sides:
                u = sd * eu
                pts = [(u - 0.3 * s, ev + 0.16 * s), (u + 0.3 * s, ev + 0.16 * s), (u + 0.27 * s, ev - 0.08 * s),
                       (u + 0.12 * s, ev - 0.2 * s), (u - 0.14 * s, ev - 0.2 * s), (u - 0.28 * s, ev - 0.06 * s)]
                self.d(f"Lens{sd}", pts, lens, off=0.03, th=0.04)
                self.d(f"Glint{sd}", rect(u - 0.08 * s, ev + 0.02 * s, 0.07 * s, 0.26 * s, math.radians(-35)), rgb(200, 210, 255), off=0.075, th=0.01)
            self.d("Bridge", rect(0, ev + 0.11 * s, 2 * eu - 0.5 * s, 0.07 * s), lens, off=0.03, th=0.04)
        elif kind == "visor":  # robot band with glowing eye slits
            c = color or rgb(80, 240, 255)
            self.d("Visor", [(-0.92 * s, ev + 0.22 * s), (0.92 * s, ev + 0.22 * s), (0.86 * s, ev - 0.2 * s), (-0.86 * s, ev - 0.2 * s)], rgb(28, 30, 44), off=0.02, th=0.05)
            for sd in sides:
                self.d(f"Eye{sd}", oval(sd * eu, ev, 0.36 * s, 0.17 * s, n=12), c, off=0.08, th=0.012)
        elif kind == "glow":  # solid glowing eyes, no pupils (spooky / void)
            c = color or rgb(190, 120, 255)
            for sd in sides:
                pts = oval(sd * eu, ev, w * 0.9, h * 0.75, n=16)
                pts = [(x, min(y, ev + 0.12 * s + (x - sd * eu) * 0.45 * sd)) for x, y in pts]
                self.d(f"Eye{sd}", pts, c, off=0.02)
        elif kind == "spiral":
            for sd in sides:
                pts = []
                for k in range(26):
                    t = k / 25 * 2.2 * math.tau
                    r = (0.03 + 0.17 * k / 25) * s
                    pts.append((sd * eu + math.cos(t * sd) * r, ev + math.sin(t * sd) * r))
                inner = [(sd * eu + (x - sd * eu) * 0.72, ev + (y - ev) * 0.72) for x, y in pts]
                self.d(f"Eye{sd}", pts + list(reversed(inner)), self.ink, off=0.02)
        elif kind == "sparkle":  # big shiny anime eyes: dark + iris + 3 catchlights
            for sd in sides:
                self._eye_round(sd, w * 1.2, h * 1.25, iris=iris or rgb(110, 200, 255), look=look)
                self.d(f"EyeHi3{sd}", star(sd * eu + 0.1 * s, ev + 0.18 * s, 0.07 * s, 0.03 * s, n=4), WHITE, off=0.055, th=0.01)
        else:
            raise ValueError(kind)
        return self

    def brows(self, kind="angry", w=0.38, th=0.075, lift=0.0, color=None):
        """angry (inner ends down), worried (inner ends up), raised (arcs), unibrow, bushy."""
        s, eu = self.s, self.eu
        v = self.ev + 0.44 * s + lift
        c = color or self.ink
        for sd in (-1, 1):
            u = sd * eu
            if kind == "angry":
                self.d(f"Brow{sd}", rect(u, v, w * s, th * s, math.radians(-22 * sd)), c, off=0.02)
            elif kind == "worried":
                self.d(f"Brow{sd}", rect(u, v, w * s, th * s, math.radians(18 * sd)), c, off=0.02)
            elif kind == "raised":
                self.d(f"Brow{sd}", arc(u, v - 0.12 * s, 0.2 * s, 55, 125, th * s, n=6), c, off=0.02)
            elif kind == "bushy":
                self.d(f"Brow{sd}", rect(u, v, w * 1.2 * s, th * 2.0 * s, math.radians(-14 * sd)), c, off=0.02)
        if kind == "unibrow":
            pts = [(-0.75 * s, v + 0.02), (-0.1 * s, v - 0.07), (0.1 * s, v - 0.07), (0.75 * s, v + 0.02),
                   (0.75 * s, v + 0.13), (0.1 * s, v + 0.05), (-0.1 * s, v + 0.05), (-0.75 * s, v + 0.13)]
            self.d("Unibrow", pts, c, off=0.02)
        return self

    def mouth(self, kind="smile", w=1.0, u=0.0, v=None, color=None):
        """smile, grin (open D with teeth), open (D + tongue), cat (:3), fang, smirk, o, flat, frown,
        buck (buck teeth), zigzag, tongue (smile + tongue out), shark (wide teeth row), wobbly, kiss, ooh."""
        s = self.s * w
        mv = self.mv if v is None else v
        mc = color or self.mc
        if kind == "smile":
            self.d("Mouth", arc(u, mv + 0.05 * s, 0.18 * s, 200, 340, 0.07 * s), mc)
        elif kind == "grin":
            self.d("Mouth", half_oval(u, mv + 0.08 * s, 0.56 * s, 0.3 * s), mc)
            self.d("Teeth", [(u - 0.25 * s, mv + 0.075 * s), (u + 0.25 * s, mv + 0.075 * s), (u + 0.21 * s, mv - 0.02 * s), (u - 0.21 * s, mv - 0.02 * s)], WHITE, off=0.04, th=0.012)
            self.d("Tongue", oval(u, mv - 0.13 * s, 0.24 * s, 0.1 * s), TONGUE, off=0.04, th=0.012)
        elif kind == "open":
            self.d("Mouth", half_oval(u, mv + 0.08 * s, 0.42 * s, 0.26 * s), mc)
            self.d("Tongue", oval(u, mv - 0.08 * s, 0.22 * s, 0.1 * s), TONGUE, off=0.04, th=0.012)
        elif kind == "cat":
            for sd in (-1, 1):
                self.d(f"Mouth{sd}", arc(u + sd * 0.1 * s, mv + 0.06 * s, 0.1 * s, 200, 340, 0.06 * s, n=8), mc)
        elif kind == "fang":
            self.d("Mouth", arc(u, mv + 0.07 * s, 0.22 * s, 205, 335, 0.07 * s), mc)
            self.d("Fang", [(u + 0.09 * s, mv - 0.06 * s), (u + 0.2 * s, mv - 0.04 * s), (u + 0.15 * s, mv - 0.17 * s)], WHITE, off=0.04, th=0.02)
        elif kind == "fangs":
            self.d("Mouth", arc(u, mv + 0.1 * s, 0.26 * s, 210, 330, 0.07 * s), mc)
            for sd in (-1, 1):
                self.d(f"Fang{sd}", [(u + sd * 0.08 * s, mv - 0.04 * s), (u + sd * 0.19 * s, mv - 0.02 * s), (u + sd * 0.135 * s, mv - 0.16 * s)], WHITE, off=0.04, th=0.02)
        elif kind == "smirk":
            self.d("Mouth", arc(u + 0.08 * s, mv + 0.14 * s, 0.26 * s, 220, 318, 0.07 * s), mc)
        elif kind == "o":
            self.d("Mouth", oval(u, mv - 0.02 * s, 0.2 * s, 0.24 * s), mc)
            self.d("MouthIn", oval(u, mv - 0.05 * s, 0.11 * s, 0.1 * s), shade(mc, 0.55), off=0.04, th=0.012)
        elif kind == "ooh":
            self.d("Mouth", oval(u, mv - 0.02 * s, 0.13 * s, 0.13 * s), mc)
        elif kind == "flat":
            self.d("Mouth", rect(u, mv, 0.26 * s, 0.065 * s), mc)
        elif kind == "frown":
            self.d("Mouth", arc(u, mv - 0.12 * s, 0.18 * s, 30, 150, 0.07 * s), mc)
        elif kind == "buck":
            self.d("Mouth", arc(u, mv + 0.08 * s, 0.2 * s, 205, 335, 0.07 * s), mc)
            for sd in (-1, 1):
                self.d(f"Tooth{sd}", rect(u + sd * 0.055 * s, mv - 0.1 * s, 0.1 * s, 0.13 * s), WHITE, off=0.04, th=0.02)
        elif kind == "zigzag":
            self.d("Mouth", zigzag(u - 0.3 * s, u + 0.3 * s, mv, 0.05 * s, 6, 0.06 * s), mc)
        elif kind == "tongue":
            self.d("Mouth", arc(u, mv + 0.07 * s, 0.22 * s, 200, 340, 0.07 * s), mc)
            self.d("Tongue", half_oval(u + 0.07 * s, mv - 0.13 * s, 0.17 * s, 0.17 * s), TONGUE, off=0.035, th=0.015)
            self.d("TongueLine", rect(u + 0.07 * s, mv - 0.2 * s, 0.025 * s, 0.1 * s), shade(TONGUE, 0.75), off=0.055, th=0.008)
        elif kind == "shark":
            self.d("Mouth", half_oval(u, mv + 0.1 * s, 0.86 * s, 0.32 * s, n=16), mc)
            for k in range(6):
                x = u - 0.33 * s + k * 0.132 * s
                self.d(f"Tooth{k}", [(x - 0.055 * s, mv + 0.09 * s), (x + 0.055 * s, mv + 0.09 * s), (x, mv - 0.03 * s)], WHITE, off=0.04, th=0.012)
        elif kind == "wobbly":
            pts = []
            for k in range(13):
                t = k / 12
                pts.append((u - 0.28 * s + 0.56 * s * t, mv + 0.035 * s * math.sin(t * math.tau * 1.5)))
            top = [(x, y + 0.033 * s) for x, y in pts]
            bot = [(x, y - 0.033 * s) for x, y in reversed(pts)]
            self.d("Mouth", top + bot, mc)
        elif kind == "kiss":
            self.d("Mouth", heart(u, mv, 0.2 * s), rgb(230, 50, 90))
        else:
            raise ValueError(kind)
        return self

    def cheeks(self, color=CHEEK, w=0.3, h=0.15, u=None, v=None):
        u = (self.eu + 0.36 * self.s) if u is None else u
        v = (self.ev - 0.3 * self.s) if v is None else v
        for sd in (-1, 1):
            self.d(f"Cheek{sd}", oval(sd * u, v, w * self.s, h * self.s, n=12), color, off=0.012, th=0.015)
        return self

    def freckles(self, color=rgb(190, 110, 70)):
        for sd in (-1, 1):
            for k, (du, dv) in enumerate(((0, 0), (0.12, 0.05), (0.08, -0.08))):
                self.d(f"Freckle{sd}{k}", oval(sd * (self.eu + 0.25 + du) * self.s, self.ev - 0.3 * self.s + dv, 0.06, 0.06, n=6), color, off=0.012, th=0.012)
        return self

    def nose(self, color=rgb(255, 130, 160), w=0.2, h=0.13, v=None):
        v = (self.ev - 0.2 * self.s) if v is None else v
        self.d("Nose", oval(0, v, w * self.s, h * self.s, n=12), color, off=0.02, th=0.03)
        self.d("NoseHi", oval(-0.03 * self.s, v + 0.03 * self.s, w * 0.3 * self.s, h * 0.3 * self.s, n=8), WHITE, off=0.06, th=0.008)
        return self

    def whiskers(self, color=None):
        c = color or self.ink
        for sd in (-1, 1):
            for k, ang in enumerate((8, -8)):
                self.d(f"Whisker{sd}{k}", rect(sd * (self.eu + 0.45) * self.s, self.mv + 0.08 * self.s + k * -0.1 * self.s, 0.36 * self.s, 0.035 * self.s, math.radians(ang * sd)), c, off=0.02)
        return self

    def mustache(self, color=rgb(70, 40, 30)):
        v = self.mv + 0.17 * self.s
        for sd in (-1, 1):
            pts = [(0, v + 0.04 * self.s)]
            for k in range(9):
                t = k / 8
                pts.append((sd * (0.05 + 0.42 * t) * self.s, v + (0.05 - 0.12 * math.sin(t * math.pi) + 0.12 * t ** 3) * self.s))
            for k in range(8, -1, -1):
                t = k / 8
                pts.append((sd * (0.05 + 0.42 * t) * self.s, v + (0.05 - 0.12 * math.sin(t * math.pi) + 0.12 * t ** 3 - 0.11 * math.sin(t * math.pi) ** 0.6) * self.s))
            if sd < 0:
                pts = list(reversed(pts))
            self.d(f"Stache{sd}", pts, color, off=0.04, th=0.04)
        return self

    def tear(self, side=1, color=rgb(120, 200, 255)):
        u = side * (self.eu + 0.12 * self.s)
        v = self.ev - 0.32 * self.s
        pts = [(u, v + 0.12 * self.s)] + [(u + math.cos(a) * 0.07 * self.s, v + math.sin(a) * 0.07 * self.s) for a in [math.radians(x) for x in range(-20, 210, 20)]][::-1]
        self.d(f"Tear{side}", pts, color, off=0.03, th=0.02)
        return self


# ---------------------------------------------------------------- accessory primitives
def ball(name, r, pos, color, squash=(1, 1, 1), rot=(0, 0, 0), subdiv=2, smooth=True):
    """smooth sphere/ellipsoid; color may be fn(p, n)."""
    o = blob(name, r, pos, None if callable(color) else color, subdiv=subdiv, squash=squash, jitter=0, rot=rot)
    if callable(color):
        paint_fn(o, color)
    return keep(o, smooth)


def lathe(name, profile, color, pos=(0, 0, 0), axis=(0, 0, 1), segs=12, sub=0, smooth=True, sx=1.0, sy=1.0, spin=0.0):
    """surface of revolution around `axis` through `pos`: profile [(t, r)] with t along the axis
    (first/last r 0 closes with a point, else a flat cap). color may be fn(p, n)."""
    prof = catmull(profile, sub) if sub else list(profile)
    q = Vector(axis).normalized().to_track_quat("Z", "Y")
    bm = bmesh.new()
    rings, ends = [], []
    for t, r in prof:
        if r < 1e-5:
            ends.append((len(rings), bm.verts.new(Vector(pos) + q @ Vector((0, 0, t)))))
            continue
        rings.append([bm.verts.new(Vector(pos) + q @ Vector((math.cos(k * math.tau / segs + spin) * r * sx, math.sin(k * math.tau / segs + spin) * r * sy, t))) for k in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    first_tip = any(i == 0 for i, _ in ends)
    last_tip = any(i == len(rings) for i, _ in ends)
    for i, v in ends:
        ring = rings[0] if i == 0 else rings[-1]
        for k in range(segs):
            bm.faces.new((ring[k], ring[(k + 1) % segs], v))
    if not first_tip:
        bm.faces.new(list(reversed(rings[0])))
    if not last_tip:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, smooth)


def horn(name, pts, radii, c0, c1, segs=8, smooth=True):
    """curved tapered tube (horns, tails, antennae stalks), c0 at the root -> c1 at the tip."""
    o = tube(name, pts, radii, None, segs=segs)
    a, b = Vector(pts[0]), Vector(pts[-1])
    # colour by arc length along the polyline
    P = [Vector(p) for p in pts]
    L = [0.0]
    for p, q in zip(P, P[1:]):
        L.append(L[-1] + (q - p).length)

    def fn(p, n):
        best, bt = 1e9, 0.0
        for i in range(len(P) - 1):
            seg = P[i + 1] - P[i]
            t = min(1, max(0, (p - P[i]).dot(seg) / max(seg.length_squared, 1e-9)))
            d = (P[i] + seg * t - p).length
            if d < best:
                best, bt = d, (L[i] + seg.length * t) / L[-1]
        return mix(c0, c1, bt)
    paint_fn(o, fn)
    return keep(o, smooth)


def slab(name, poly, thick, origin, xaxis, yaxis, color, smooth=False, bevel_k=0.0):
    """extruded flat 2D shape (wings, fins, ears, leaves, flames, headband tails):
    poly (x, y) placed at origin with in-plane axes xaxis/yaxis. color may be fn(p, n)."""
    O, X, Y = Vector(origin), Vector(xaxis).normalized(), Vector(yaxis).normalized()
    N = X.cross(Y).normalized()
    bm = bmesh.new()
    k = len(poly)
    top = [bm.verts.new(O + X * x + Y * y + N * thick / 2 * (1 - bevel_k * 0)) for x, y in poly]
    bot = [bm.verts.new(O + X * x + Y * y - N * thick / 2) for x, y in poly]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, smooth)


def puffy_slab(name, poly, thick, origin, xaxis, yaxis, color, rows=3):
    """slab with a rounded (pillowy) cross-section: inner rings shrink towards the centroid and
    bulge out. Good for soft wings, fins, ears, leaves."""
    O, X, Y = Vector(origin), Vector(xaxis).normalized(), Vector(yaxis).normalized()
    N = X.cross(Y).normalized()
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    bm = bmesh.new()
    k = len(poly)
    layers = []
    for side in (1, -1):
        ring_list = []
        for r in range(rows):
            f = 1 - r / rows
            z = math.sin((r / rows) * math.pi / 2) * thick / 2 + thick * 0.08
            ring_list.append([bm.verts.new(O + X * (cx + (x - cx) * f) + Y * (cy + (y - cy) * f) + N * z * side) for x, y in poly])
        center = bm.verts.new(O + X * cx + Y * cy + N * (thick / 2 + thick * 0.08) * side)
        layers.append((ring_list, center))
    (top, ct), (bot, cb) = layers
    for rl, c in ((top, ct), (bot, cb)):
        for a, b in zip(rl, rl[1:]):
            for i in range(k):
                j = (i + 1) % k
                bm.faces.new((a[i], a[j], b[j], b[i]))
        for i in range(k):
            bm.faces.new((rl[-1][i], rl[-1][(i + 1) % k], c))
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((top[0][i], bot[0][i], bot[0][j], top[0][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, True)


def torus(name, R, r, center, normal, color, segs=28, rsegs=8, smooth=True):
    n = Vector(normal).normalized()
    q = n.to_track_quat("Z", "Y")
    C = Vector(center)
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = i * math.tau / segs
        ca = Vector((math.cos(a), math.sin(a), 0))
        rings.append([bm.verts.new(C + q @ (ca * (R + r * math.cos(b)) + Vector((0, 0, r * math.sin(b))))) for b in (j * math.tau / rsegs for j in range(rsegs))])
    for i in range(segs):
        a, b = rings[i], rings[(i + 1) % segs]
        for j in range(rsegs):
            k = (j + 1) % rsegs
            bm.faces.new((a[j], b[j], b[k], a[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, smooth)


def gem(name, pos, r, color, h=None, segs=6, axis=(0, 0, 1)):
    """faceted gem (crystal, jewel): double cone, flat shaded, alternating facet values."""
    h = h or r * 1.6
    o = lathe(name, [(-h * 0.45, 0), (0, r), (h * 0.55, 0)], color, pos=pos, axis=axis, segs=segs, smooth=False)
    bm = bmesh.new(); bm.from_mesh(o.data)
    col = bm.loops.layers.color["Col"]
    for i, f in enumerate(bm.faces):
        for lp in f.loops:
            lp[col] = mix(lp[col], WHITE, 0.35) if i % 2 else lp[col]
    bm.to_mesh(o.data); bm.free()
    return o


def crystal(name, base, direction, length, rad, c0, c1, segs=6):
    """hexagonal crystal prism with a pointed tip, dark root -> light tip, sparkle facets."""
    d = Vector(direction).normalized()
    o = lathe(name, [(0, rad * 0.9), (length * 0.72, rad), (length, 0)], along(c0, c1, base, Vector(base) + d * length),
              pos=base, axis=d, segs=segs, smooth=False)
    bm = bmesh.new(); bm.from_mesh(o.data)
    col = bm.loops.layers.color["Col"]
    for i, f in enumerate(bm.faces):
        for lp in f.loops:
            lp[col] = mix(lp[col], WHITE, 0.4) if i % 2 else lp[col]
    bm.to_mesh(o.data); bm.free()
    return o


def goo(name, balls, color, tris=None, resolution=0.12, smooth=True):
    """merged metaball shape (clouds, flames, drips, fused blobs). balls: [(pos, radius, (sx,sy,sz)?)].
    radius = the lone ball's surface radius (merged balls bulge a little). color may be fn(p, n)."""
    bl = []
    for b in balls:
        pos, r = b[0], b[1]
        sc = b[2] if len(b) > 2 else (1, 1, 1)
        bl.append(Ball(pos, (r * sc[0], r * sc[1], r * sc[2])))
    o = metaball_mesh(name.replace(".", "_"), bl, resolution=resolution, tris=tris)
    paint_fn(o, color if callable(color) else (lambda p, n: color))
    return keep(o, smooth)


# ---------------------------------------------------------------- shipping
def ship(name, parts):
    """finish() + keep smooth flags + turn to face Roblox -Z (unless SLIME_PREVIEW=1) and print
    where this mesh sits relative to the slime's bottom centre (Roblox axes)."""
    preview = os.environ.get("SLIME_PREVIEW") == "1"
    rig = os.environ.get("SLIME_RIG") == "1"  # skinned bones (models/_slimerig.py)
    if rig:
        from models import _slimerig
        parts = parts + _slimerig.add_lids(parts)
        _slimerig.tag_parts(parts)
    for o in parts:
        if "keep_smooth" not in o.data.attributes:
            keep(o, False)
    if not preview:
        for o in parts:
            o.rotation_euler = (0, 0, math.pi)
        bpy.context.view_layer.update()
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in parts:
        mw = o.matrix_world
        for v in o.data.vertices:
            w = mw @ v.co
            for i in range(3):
                lo[i], hi[i] = min(lo[i], w[i]), max(hi[i], w[i])
    o = finish(name, parts)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    if rig:
        _slimerig.build_rig(o)
    c = (lo + hi) / 2
    info = {"name": name, "roblox_size": [round(hi.x - lo.x, 3), round(hi.z - lo.z, 3), round(hi.y - lo.y, 3)],
            "roblox_center_from_slime_bottom": [round(c.x, 3), round(c.z, 3), round(-c.y, 3)],
            "faces_roblox": "-Z" if not preview else "+Z (preview)"}
    print("SLIME_ATTACH " + json.dumps(info))
    return o
