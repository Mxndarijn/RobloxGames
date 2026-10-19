# The pet_mount_* builders (not an asset): each returns a list of painted, smooth-flagged parts in the
# pet_cloud frame (3.3 x 2.4 studs after ship() fits it, origin bottom centre, front -Y, seat on top).
import math
from models._pet_mount import *

# ---------------------------------------------------------------- shared cloud colouring


def cloud_painter(stops, under=0.82, lift=0.0, top=1.25):
    def f(co, n):
        t = clamp((co.z - lift) / (top - lift))
        c = mixn(stops, t)
        k = 1.0 - (1 - under) * clamp(-n.z * 1.2 + 0.1)  # darker belly
        return shade(c, k)
    return f


# ---------------------------------------------------------------- storm cloud
def storm_cloud():
    (body,) = cloud_parts(name="Storm", tris=1650, colour=cloud_painter([(0, rgb(46, 50, 68)), (0.5, rgb(78, 84, 108)), (1, rgb(128, 134, 158))], under=0.8))
    pts = [(-0.1, 1.0), (0.42, 1.0), (0.2, 0.58), (0.5, 0.58), (-0.22, 0.0), (-0.02, 0.4), (-0.38, 0.4)]
    bolt = extrude_poly("Bolt", pts, 0.3, pos=(0.55, -1.05, 0.0), bevel_w=0.06)
    bpy.context.view_layer.update()
    paint(bolt, lambda co, n: mix(rgb(255, 200, 40), rgb(255, 244, 120), clamp(n.y * -0.8 + 0.3)))
    return [body, bolt]


# ---------------------------------------------------------------- rainbow cloud
RAINBOW = [rgb(240, 80, 90), rgb(255, 160, 70), rgb(255, 224, 80), rgb(110, 210, 110), rgb(90, 170, 245), rgb(160, 110, 230)]


def rainbow_cloud():
    (body,) = cloud_parts(name="RainbowCloud", tris=1150, colour=cloud_painter([(0, rgb(206, 226, 252)), (0.45, rgb(246, 250, 255)), (1, rgb(255, 255, 255))], under=0.88))
    parts = [body]
    tilt = math.radians(14)  # the arch leans back over the rim, behind the pet
    for i, c in enumerate(RAINBOW):
        R = 1.15 - i * 0.12
        pts, radii = [], []
        steps = 10
        for s_ in range(steps + 1):
            a = math.pi * s_ / steps
            x, h = R * math.cos(a), R * math.sin(a)
            pts.append((x, 0.98 + h * math.sin(tilt), 0.55 + h * math.cos(tilt)))
            radii.append(0.075 * (0.55 + 0.45 * math.sin(a * 0.9 + 0.2)))
        t = soft_tube("Band%d" % i, pts, radii, segs=5)
        paint(t, lambda co, nn, c=c: shade(c, 0.86 + 0.14 * clamp(nn.z + 0.3)))
        parts.append(t)
    return parts


# ---------------------------------------------------------------- sunset cloud
def sunset_cloud():
    stops = [(0, rgb(255, 120, 84)), (0.4, rgb(255, 146, 148)), (0.75, rgb(255, 188, 160)), (1, rgb(255, 226, 176))]

    def f(co, n):
        t = clamp(co.z / 1.22 + 0.05 * math.sin(co.x * 2.2) + 0.08 * clamp(-co.y * 0.4))
        k = 1.0 - 0.16 * clamp(-n.z * 1.2 + 0.1)
        return shade(mixn(stops, t), k)
    return cloud_parts(name="SunsetCloud", colour=f)


# ---------------------------------------------------------------- ice cloud
def ice_cloud():
    (body,) = cloud_parts(name="IceCloud", tris=1250, colour=cloud_painter([(0, rgb(104, 164, 230)), (0.5, rgb(156, 208, 248)), (1, rgb(214, 240, 255))], under=0.82))
    parts = [body]
    # three crystal clusters on the rim: a tall shard with two leaning companions
    spec = [((-1.15, -0.45, 0.62), (-0.55, -0.25, 1.0), 1.0, 0.17), ((-1.0, -0.2, 0.55), (-1.0, -0.1, 0.55), 0.62, 0.12),
            ((1.05, 0.35, 0.6), (0.5, 0.25, 1.0), 0.95, 0.16), ((1.2, 0.1, 0.55), (1.0, -0.05, 0.6), 0.6, 0.12),
            ((0.8, 0.65, 0.55), (0.25, 0.6, 0.9), 0.55, 0.11),
            ((0.3, -0.95, 0.5), (0.25, -0.45, 1.0), 0.7, 0.13), ((0.6, -0.8, 0.5), (0.9, -0.5, 0.8), 0.5, 0.1)]
    for k, (b, d, ln, r) in enumerate(spec):
        ln, r = ln * 1.35, r * 1.3
        c = crystal("Shard%d" % k, b, d, ln, r)
        paint(c, lambda co, n: mix(rgb(96, 170, 236), rgb(214, 248, 255), clamp((co.z - 0.5) / 1.0) * 0.7 + clamp(n.z) * 0.3), smooth=False)
        parts.append(c)
    return parts


# ---------------------------------------------------------------- flame cloud
def flame_cloud():
    # soft tufts round the rim: a chain of shrinking puffs leaning outward and swirling (extra puffs of the shared cloud)
    extra = []
    n = 9
    for i in range(n):
        a = i * math.tau / n + 0.2
        rx, ry = 1.12, 0.84
        for r, up, out, sw in [(0.3, 0.58, 0.0, 0), (0.23, 0.82, 0.05, 0.1), (0.15, 1.02, 0.09, 0.24), (0.09, 1.18, 0.12, 0.4)]:
            ca, sa = math.cos(a), math.sin(a)
            x = (rx + out) * ca - sw * sa * 0.55
            y = (ry + out) * sa + sw * ca * 0.4
            hs = 1.0 + 0.12 * math.sin(i * 1.7)
            extra.append((x, y, 0.1 + up * hs, (r, r, r * 1.25)))
    stops = [(0, rgb(190, 40, 28)), (0.35, rgb(240, 96, 36)), (0.65, rgb(255, 160, 52)), (0.9, rgb(255, 226, 96))]

    def f(co, n):
        rn = math.hypot(co.x / 1.5, co.y / 1.08)
        h = clamp((co.z - 0.1) / 1.25)
        t = h * 0.62 + clamp((rn - 0.72) / 0.35) * h * 0.55
        return shade(mixn(stops, t), 1.0 - 0.18 * clamp(-n.z * 1.2 + 0.1))
    return cloud_parts(name="FlameCloud", res=0.08, extra=extra, colour=f, flat_r=0.62)


# ---------------------------------------------------------------- leaf
NH = 9  # leaf blade columns each side of the midrib
VEIN_ROWS = [0.65 - 0.26 * k for k in range(5)]  # u where the six side veins leave the midrib
SWEEP = 0.26  # how far (in u) a vein curves toward the tip by the time it is out at v = 0.68


def _vein_shift(ur, av):
    """u offset of a row that starts at ur on the midrib, at |v| = av: the mesh rows ARE the vein curves."""
    f = 1 - sstep(0.55, 1.0, abs(ur))
    return SWEEP * min(1.0, (av / 0.68) ** 1.1) * f


def leaf_rows():
    """row positions ur along the blade: a vein row every 0.28 with two rows between, coarser at the tip and the back."""
    mid = [VEIN_ROWS[0] - k * 0.065 for k in range(21)]  # 0.65 .. -0.65
    return [-1.0, -0.96, -0.91, -0.85, -0.78, -0.72] + mid[::-1] + [0.72, 0.84, 0.9, 0.95, 0.98, 1.0]


def leaf_blade(name, L, width, c, zp, bend, rows, Nh, nr, nb, e):
    """The leaf blade: like slab(), but the top is a grid (rows along the vein curves, columns across the blade) instead
    of a polar fan, so painted vein lines get evenly spaced vertices to sit on. Returns (object, {(x, y): (ur, j)})."""
    bm = bmesh.new()
    info = {}
    Nu = len(rows) - 1

    def P(x, y, z):
        return bm.verts.new(bend(Vector((x, y, z + zp))))
    grid = {}
    for i in range(1, Nu):
        for j in range(-Nh, Nh + 1):
            u = rows[i] - _vein_shift(rows[i], abs(j) / Nh)
            x, y = L * u, width(u) * j / Nh
            grid[i, j] = P(x, y, c)
            info[(round(x, 4), round(y, 4))] = (rows[i], j)
    tip, back = P(-L, 0, c), P(L, 0, c)
    info[(round(-L, 4), 0.0)] = (-1.0, 0)
    info[(round(L, 4), 0.0)] = (1.0, 0)
    for j in range(-Nh, Nh + 1):
        grid[0, j], grid[Nu, j] = tip, back

    def quad(*vs):
        u = []
        for v in vs:
            if v not in u:
                u.append(v)
        if len(u) >= 3:
            bm.faces.new(u)
    for i in range(Nu):
        for j in range(-Nh, Nh):
            quad(grid[i, j], grid[i + 1, j], grid[i + 1, j + 1], grid[i, j + 1])
    us = [rows[i] - _vein_shift(rows[i], 1.0) for i in range(Nu + 1)]
    B = [(-L, 0.0)] + [(L * us[i], width(us[i])) for i in range(1, Nu)] + [(L, 0.0)] + [(L * us[i], -width(us[i])) for i in range(Nu - 1, 0, -1)]
    M = len(B)
    rings = [[tip] + [grid[i, Nh] for i in range(1, Nu)] + [back] + [grid[i, -Nh] for i in range(Nu - 1, 0, -1)]]
    for j in range(1, nr):
        ph = math.pi * j / nr
        k = 1 + e * math.sin(ph)
        rings.append([P(bx * k, by * k, c * math.cos(ph)) for bx, by in B])
    for i in range(nb, 0, -1):
        s = i / nb
        rings.append([P(bx * s, by * s, -c) for bx, by in B])
    bot = bm.verts.new(bend(Vector((0, 0, -c + zp))))
    for k in range(M):
        j = (k + 1) % M
        bm.faces.new((bot, rings[-1][k], rings[-1][j]))
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(M):
            j = (k + 1) % M
            bm.faces.new((r0[k], r0[j], r1[j], r1[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm), info


def leaf():
    """A leaf raft, long axis x: pointed tip at -x (the front of the leaf), cupped blade with edges and tip curling
    up, midrib + side veins painted into the vertex colours (no raised geometry), a short curled stem out of the back."""
    L, W, ZP, C = 1.62, 1.18, 0.42, 0.085

    def width(u):  # half width of the blade at u = x / L (tip -1, back +1)
        s = math.sqrt(max(0.0, 1 - u * u))
        return W * s ** (1.55 - 0.7 * u) * (1 + 0.1 * u)

    def bend(p):
        u = p.x / L
        v = p.y / max(width(max(-1.0, min(1.0, u))), 0.08)
        z = p.z + 0.15 * min(v * v, 1.3) + 0.38 * max(0.0, -u) ** 2.6 + 0.07 * max(0.0, u) ** 2
        z += 0.025 * math.sin(u * 6.5 + 0.5) * min(v * v, 1.0)  # slightly wavy edge
        return Vector((p.x, p.y, z))
    body, info = leaf_blade("Leaf", L, width, C, ZP, bend, leaf_rows(), NH, nr=4, nb=2, e=0.07)
    VEIN = rgb(226, 250, 146)
    dur = 0.065

    def vein_w(co):  # painted vein weight 0..1 from the blade grid position of the vertex
        ij = info.get((round(co.x, 4), round(co.y, 4)))
        if ij is None:
            return 0.0
        ur, j = ij
        av = abs(j) / NH
        d = min(abs(ur - r) for r in VEIN_ROWS) / dur  # rows away from the nearest side vein
        side = (1 - sstep(0.2, 1.4, d)) * (1 - sstep(0.62, 0.8, av)) * sstep(-0.7, -0.5, ur) * (1 - sstep(0.7, 0.8, ur))
        mid = (1 - sstep(0.3, 1.25, abs(j))) * sstep(-0.95, -0.7, ur) * (1 - sstep(0.88, 1.0, ur))
        return max(side * 0.95, mid)

    def f(co, n):
        u, v = co.x / L, co.y / max(width(max(-1.0, min(1.0, co.x / L))), 0.1)
        c = mix(rgb(52, 140, 52), rgb(100, 182, 66), clamp(0.5 + 0.35 * n.z + 0.2 * (1 - abs(v))))
        c = mix(c, rgb(46, 120, 48), sstep(0.7, 1.0, abs(v)) * 0.5)  # darker rim
        c = shade(mix(c, rgb(120, 170, 60), clamp(-n.z) * 0.5), 1 - 0.22 * clamp(-n.z))
        return mix(c, VEIN, vein_w(co) * clamp(n.z * 3.0 + 0.2))
    paint(body, f)
    parts = [body]

    def top(x, y):  # a point on the blade's upper surface
        return bend(Vector((x, y, ZP + C)))

    # short stem out of the back end, curling upward (never reaches the ground)
    z0 = top(L * 0.95, 0)[2]
    stem = soft_tube("Stem", [(L * 0.9, 0.0, z0 - 0.02), (L * 1.0 + 0.2, 0.0, z0 - 0.04), (L * 1.0 + 0.36, 0.0, z0 + 0.06), (L * 1.0 + 0.4, 0.0, z0 + 0.22)], [0.1, 0.085, 0.07, 0.045], segs=6)
    paint(stem, lambda co, n: mix(rgb(86, 150, 52), rgb(140, 196, 72), clamp(n.z + 0.3)))
    parts.append(stem)
    return parts


# ---------------------------------------------------------------- bubble
def bubble():
    body = pillow("Bubble", 1.6, 1.15, 0.55, pos=(0, 0, 0.65), nx=14, ny=10, nz=6, pxy=1.0, pz=0.8)
    PALE = rgb(228, 238, 250)
    hues = [rgb(240, 176, 218), rgb(188, 172, 240), rgb(150, 226, 242), rgb(172, 238, 210), rgb(240, 176, 218)]
    L1, L2 = Vector((-0.5, -0.55, 0.65)).normalized(), Vector((0.6, 0.45, 0.3)).normalized()

    def f(co, n):
        tilt = math.acos(clamp(n.z, -1, 1)) / (math.pi / 2)  # 0 on the flat top, 1 on the side
        ph = (2.4 * tilt + 0.5 * math.atan2(n.y, n.x) / math.pi + 0.2 * co.x) % 1.0 * (len(hues) - 1)
        i = min(int(ph), len(hues) - 2)
        c = mix(hues[i], hues[i + 1], ph - i)
        c = mix(PALE, c, 0.3 + 0.6 * sstep(0.15, 0.85, tilt))  # clear, pale middle; colour gathers at the rim
        c = mix(c, rgb(246, 252, 255), sstep(0.8, 0.95, tilt) * 0.5)  # thin bright edge
        c = mix(c, rgb(255, 255, 255), sstep(0.8, 0.92, clamp(n.dot(L1))))  # strong highlight
        c = mix(c, rgb(238, 252, 255), sstep(0.88, 0.97, clamp(n.dot(L2))) * 0.8)  # small bounce light
        return c
    paint(body, f)
    parts = [body]
    for k, (x, y, z, r, sd) in enumerate([(-1.25, 0.65, 0.34, 0.36, 3), (1.3, 0.5, 0.28, 0.27, 3), (1.05, -0.85, 0.22, 0.17, 2)]):
        sp = sphere("Mini%d" % k, r, (x, y, z), subdiv=sd)
        paint(sp, f)
        parts.append(sp)
    return parts


# ---------------------------------------------------------------- magic carpet
def magic_carpet():
    """Persian carpet: crimson field, purple border band with a dash motif between gold lines, a smooth gold-rimmed
    diamond medallion, gold trim edge. The pattern edges are real rings of the mesh (ring_slab), not painted smears."""
    a, b, n, M = 1.52, 1.08, 4.5, 56
    GOLD, GOLD_D, CREAM = rgb(255, 208, 72), rgb(236, 172, 52), rgb(252, 232, 176)
    CRIM, PUR, PUR_M = rgb(190, 34, 66), rgb(86, 46, 152), rgb(112, 58, 176)
    # rim samples at equal arc length (the pattern cells stay the same size on the long and the short sides)
    sq = squircle(a, b, n)
    fine = [sq(i * math.tau / 4000) for i in range(4000)]
    cum = [0.0]
    for p0, p1 in zip(fine, fine[1:] + fine[:1]):
        cum.append(cum[-1] + math.hypot(p1[0] - p0[0], p1[1] - p0[1]))
    SQ, j = [], 0
    for k in range(M):
        while cum[j + 1] < cum[-1] * k / M:
            j += 1
        SQ.append(fine[j])
    TH = [math.atan2(y, x) for x, y in SQ]

    def dia(t, Da=0.9, Db=0.66, p=1.25):  # diamond with softened tips (between a rhombus and an oval)
        c, s = math.cos(t), math.sin(t)
        r = (abs(c / Da) ** p + abs(s / Db) ** p) ** (-1 / p)
        return (r * c, r * s)

    def dring(s):
        return [(dia(t)[0] * s, dia(t)[1] * s) for t in TH]

    def sring(s):
        return [(x * s, y * s) for x, y in SQ]

    def morph(s0, s1, w):
        return [(dia(t)[0] * s0 * (1 - w) + q[0] * s1 * w, dia(t)[1] * s0 * (1 - w) + q[1] * s1 * w) for t, q in zip(TH, SQ)]
    top_rings = [dring(0.28), dring(0.8), dring(1.0), morph(1.0, 0.74, 0.5), sring(0.74), sring(0.785),
                 sring(0.9), sring(0.945), sring(1.0)]

    def bend(p):
        u, v = p.x / a, p.y / b
        z = p.z + 0.065 * math.sin(p.x * 2.1 + 0.3) * (1 - 0.3 * v * v) + 0.05 * u * u
        z += 0.3 * sstep(0.4, 1.0, u) * sstep(0.25, 0.95, abs(v))  # the front (+x) corners curl up
        return Vector((p.x, p.y, z))

    def colour(zone, i, k, cen):
        if zone == "rim":
            return mix(GOLD_D, GOLD, 0.5 + 0.5 * math.sin(k * 0.7))
        if zone == "bot":
            return shade(CRIM, 0.62)
        d = clamp(math.hypot(cen.x / a, cen.y / b))
        if i == 0:
            return GOLD
        if i == 1:  # four cream points make the medallion a star in a diamond
            return CREAM if k % (M // 4) in (0, M // 4 - 1) else PUR_M
        if i == 2:
            return GOLD
        if i in (3, 4):
            if i == 4 and abs(cen.x / a) > 0.5 and abs(cen.y / b) > 0.5:  # a small gold spandrel in each corner
                return GOLD
            return shade(CRIM, 1 - 0.1 * d)
        if i in (5, 7):
            return GOLD
        if i == 6:
            return CREAM if k % 2 == 0 else PUR  # repeating dash motif
        return shade(CRIM, 0.9)
    body = ring_slab("Carpet", top_rings, 0.09, colour, nr=3, e=0.05, bottom=(0.78, 0.4), bend=bend)
    parts = [body]
    # chunky tassels on the two short ends only, hanging just 0.28 below the edge
    for sx in (-1, 1):
        for k in range(5):
            y = (k - 2) * 0.36
            x0 = sx * a * (1 - (abs(y) / b) ** n) ** (1 / n) * 0.98
            z0 = bend(Vector((x0, y, 0.0)))[2]
            t = soft_tube("Tas%d_%d" % (sx, k), [(x0, y, z0 + 0.02), (x0 + sx * 0.04, y, z0 - 0.08), (x0 + sx * 0.06, y, z0 - 0.2)], [0.08, 0.1, 0.075], segs=6)
            paint(t, lambda co, nn, z0=z0: mix(GOLD_D, GOLD, clamp((co.z - z0 + 0.3) * 3)))
            parts.append(t)
    return parts


# ---------------------------------------------------------------- ufo
def ufo():
    a, b = 1.65, 1.2
    hull = pillow("Hull", a, b, 0.5, pos=(0, 0, 0.5), nx=14, ny=10, nz=4, pxy=1.0, pz=0.85)
    HULL, HULL_D, BAND = rgb(176, 188, 214), rgb(96, 108, 146), rgb(70, 82, 120)

    def f(co, n):
        u, v = co.x / a, co.y / b
        r = math.hypot(u, v)
        c = mix(HULL_D, HULL, clamp(0.5 + 0.55 * n.z))
        c = mix(c, BAND, (1 - sstep(0.2, 0.32, abs(co.z - 0.5))) * 0.9)  # dark belt round the rim
        c = mix(c, rgb(226, 236, 250), sstep(0.55, 0.7, n.z) * (1 - sstep(0.5, 0.62, r)) * 0.8)  # soft top sheen
        return c
    paint(hull, f)
    parts = [hull]
    for k in range(6):
        ang = k * math.tau / 6 + 0.2
        x, y = 1.62 * math.cos(ang), 1.17 * math.sin(ang)
        lamp = sphere("Lamp%d" % k, 0.17, (x, y, 0.5), subdiv=2)
        col = rgb(255, 214, 64) if k % 2 == 0 else rgb(255, 120, 120)
        paint(lamp, lambda co, n, c=col: c)
        parts.append(lamp)
    dome = sphere("Dome", 0.42, (0.0, 0.62, 0.98), squash=(1.0, 1.0, 0.85), subdiv=3)
    paint(dome, lambda co, n: mix(rgb(120, 214, 224), rgb(220, 252, 255), clamp(n.z * 0.8 + 0.25)))
    parts.append(dome)
    beam = pillow("Beam", 0.55, 0.45, 0.1, pos=(0, 0, 0.1), nx=5, ny=5, nz=2, pxy=0.9, pz=0.8)
    paint(beam, lambda co, n: rgb(150, 244, 255))
    parts.append(beam)
    return parts


# ---------------------------------------------------------------- lily pad
def lily_pad():
    pa, pb = 1.5, 1.08
    pond = pillow("Pond", 1.65, 1.2, 0.4, pos=(0, 0, 0.4), nx=8, ny=6, nz=3, pxy=1.0, pz=0.7)
    paint(pond, lambda co, n: mix(rgb(70, 160, 214), rgb(150, 224, 246), clamp(n.z * 0.6 + 0.45)))

    def outline(t):
        k = 1 - 0.88 * math.exp(-(((t - math.pi / 2) / 0.12)) ** 2)  # the notch every pad has
        return (pa * math.cos(t) * k, pb * math.sin(t) * k)

    def bend(p):
        r2 = (p.x / pa) ** 2 + (p.y / pb) ** 2
        return Vector((p.x, p.y, p.z + 0.22 * r2 ** 1.5))
    pad = slab("Pad", outline, 0.13, pos=(0, 0, 0.86), M=40, nt=7, nr=4, nb=2, e=0.06, bend=bend)

    def f(co, n):
        u, v = co.x / pa, co.y / pb
        ang = math.atan2(v, u)
        r = math.hypot(u, v)
        c = mix(rgb(52, 150, 70), rgb(120, 206, 92), clamp(0.5 + 0.4 * n.z + 0.25 * r))
        vein = (1 - sstep(0.06, 0.16, abs(math.sin(ang * 7.0) * r * 2.0))) * sstep(0.12, 0.3, r) * (1 - sstep(0.8, 0.95, r))
        c = mix(c, rgb(176, 228, 120), vein * 0.7 * clamp(n.z + 0.3))
        notch = 1 - sstep(0.0, 0.2, abs(ang - math.pi / 2))
        c = mix(c, rgb(40, 110, 70), notch * 0.6 * sstep(0.1, 0.3, r) * clamp(n.z + 0.5))
        return shade(c, 1 - 0.3 * clamp(-n.z))
    paint(pad, f)
    parts = [pond, pad]
    # a pink lotus bud on the back rim
    fx, fy, fz = -0.95, 0.5, 1.04
    for k in range(5):
        ang = k * math.tau / 5
        pet = blob("Petal%d" % k, 0.22, (0, 0, 0), seed=0, subdiv=2, squash=(0.5, 0.8, 1.35), jitter=0.0)
        pet.data.transform(Matrix.Translation((0.0, 0.17, 0.0)))  # petal sits off the centre, then fans round it
        pet.data.transform(Matrix.Rotation(ang, 4, "Z"))
        pet.data.transform(Matrix.Translation((fx, fy, fz + 0.22)))
        paint(pet, lambda co, n: mix(rgb(250, 140, 190), rgb(255, 214, 232), clamp((co.z - fz) / 0.5)))
        parts.append(pet)
    mid = sphere("Core", 0.11, (fx, fy, fz + 0.2), subdiv=2)
    paint(mid, lambda co, n: rgb(255, 214, 70))
    parts.append(mid)
    return parts


MOUNTS = {
    "storm_cloud": storm_cloud,
    "rainbow_cloud": rainbow_cloud,
    "sunset_cloud": sunset_cloud,
    "ice_cloud": ice_cloud,
    "flame_cloud": flame_cloud,
    "leaf": leaf,
    "bubble": bubble,
    "magic_carpet": magic_carpet,
    "ufo": ufo,
    "lily_pad": lily_pad,
}
