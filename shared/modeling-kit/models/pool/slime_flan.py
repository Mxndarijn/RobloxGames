# Flan (Uncommon): caramel pudding slime. Wide stepped custard body with a flat top, glossy dark
# caramel sauce running down in drips, a cream dollop with a cherry, wink + happy smile.
from models._slimepool import *

CUSTARD, CUSTARD_D, CUSTARD_L = hexc("ffcf4a"), hexc("f0a030"), hexc("fff09a")
CAR, CAR_D, CAR_L = hexc("c85a16"), hexc("7a2c0c"), hexc("ffb060")
CHERRY, CHERRY_D = hexc("ff2a44"), hexc("a8102a")
CREAM, CREAM_D = hexc("fffaf2"), hexc("f2dcc8")


def paint(a, z, p):
    c = mix(CUSTARD_D, CUSTARD, smoothstep(0.0, 0.9, z))
    return mix(c, CUSTARD_L, 0.3 * smoothstep(0.9, 0.2, abs(a)) * smoothstep(1.4, 0.5, z))


PROFILE = [(0, 1.58), (0.05, 1.64), (0.14, 1.67), (0.5, 1.65), (0.58, 1.61), (0.64, 1.55), (0.72, 1.5), (1.0, 1.48),
           (1.4, 1.43), (1.9, 1.33), (2.08, 1.27), (2.2, 1.17), (2.27, 0.98), (2.31, 0.6), (2.33, 0)]
b = Body(PROFILE, paint=paint, segs=36, sub=1, gloss=0.55)
parts = [b.obj]

# ---- caramel sauce: a closed shell hugging the top, its lower edge snapped per column to drips
DRIPS = [(math.radians(d), depth, w) for d, depth, w in
         ((44, 0.7, 0.15), (-47, 0.55, 0.14), (82, 0.95, 0.15), (-88, 0.85, 0.17), (128, 0.6, 0.15),
          (-135, 1.0, 0.16), (170, 0.8, 0.15), (-175, 0.5, 0.13), (0, 0.12, 0.12))]


def adiff(a, b):
    return math.atan2(math.sin(a - b), math.cos(a - b))


def drip(a):
    """how far (studs, downwards) the sauce runs below the base edge at yaw a, and drip weight."""
    d, wt = 0.0, 0.0
    for c, depth, w in DRIPS:
        x = adiff(a, c) / w
        k = math.exp(-x * x * 1.6) if abs(x) < 3 else 0.0
        # rounded tip: a flat-ish column with a soft round end
        d = max(d, depth * k ** 0.35 if k > 0.02 else 0.0)
        wt = max(wt, k)
    return d, wt


# arclength table along the profile from the top centre downwards
prof = list(reversed(b.prof))  # (z, r) top -> bottom
L = [0.0]
for (z0, r0), (z1, r1) in zip(prof, prof[1:]):
    L.append(L[-1] + math.hypot(z1 - z0, r1 - r0))


def at_len(l):
    for i in range(len(prof) - 1):
        if L[i + 1] >= l or i == len(prof) - 2:
            t = (l - L[i]) / max(L[i + 1] - L[i], 1e-9)
            t = min(1, max(0, t))
            (z0, r0), (z1, r1) = prof[i], prof[i + 1]
            z, r = z0 + (z1 - z0) * t, r0 + (r1 - r0) * t
            dz, dr = z1 - z0, r1 - r0
            n = math.hypot(dz, dr) or 1
            return z, r, (-dz / n, dr / n)  # outward normal (nr, nz)
    return prof[-1][0], prof[-1][1], (1, 0)


def len_at_z(zt):
    """arclength from the top where the side reaches height zt."""
    for i in range(len(prof) - 1):
        (z0, _), (z1, _) = prof[i], prof[i + 1]
        if z1 <= zt <= z0 and z0 > z1:
            return L[i] + (L[i + 1] - L[i]) * (z0 - zt) / (z0 - z1)
    return L[-1]


L_SIDE = len_at_z(2.05)


def caramel(cols=48, rows=4, base_z=1.86):
    bm = bmesh.new()
    outer, inner_bot, inner_top = [], [], []
    for i in range(cols):
        a = i * math.tau / cols
        dd, wt = drip(a)
        wob = 0.04 * math.sin(a * 5 + 0.7)
        lend = len_at_z(base_z + wob - dd)
        col = []
        top_rows = [l for l in L if 0 < l < L_SIDE - 0.02]
        n_side = rows
        ls = top_rows + [L_SIDE + (lend - L_SIDE) * (j / n_side) for j in range(n_side + 1)]
        for jj, l in enumerate(ls):
            s = max(0.0, (l - L_SIDE) / max(lend - L_SIDE, 1e-6))
            z, r, (nr, nz) = at_len(l)
            e = 0.055 + 0.05 * wt * smoothstep(0.6, 1.0, s) * (1 if dd > 0.2 else 0)
            p = Vector((math.sin(a) * (r + nr * e) * b.sx, -math.cos(a) * (r + nr * e) * b.sy, z + nz * e))
            col.append(bm.verts.new(p))
        outer.append(col)
        z, r, _ = at_len(lend)
        inner_bot.append(bm.verts.new((math.sin(a) * (r - 0.03), -math.cos(a) * (r - 0.03), z)))
        inner_top.append(bm.verts.new((math.sin(a) * 0.95, -math.cos(a) * 0.95, b.H - 0.12)))
    ctop = bm.verts.new((0, 0, b.H + 0.045))
    cin = bm.verts.new((0, 0, b.H - 0.12))
    for i in range(cols):
        j = (i + 1) % cols
        bm.faces.new((ctop, outer[i][0], outer[j][0]))
        for k in range(len(outer[i]) - 1):
            bm.faces.new((outer[i][k], outer[i][k + 1], outer[j][k + 1], outer[j][k]))
        bm.faces.new((outer[i][-1], inner_bot[i], inner_bot[j], outer[j][-1]))
        bm.faces.new((inner_bot[i], inner_top[i], inner_top[j], inner_bot[j]))
        bm.faces.new((inner_top[i], cin, inner_top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm("Caramel", bm)

    def col(p, n):
        c = mix(CAR_D, CAR, smoothstep(1.0, b.H, p.z))
        d = (p - Vector((0, 0, 1.2))).normalized()
        h = max(0.0, d.dot(Vector((-0.45, -0.6, 0.66)).normalized()))
        return mix(c, CAR_L, 0.7 * smoothstep(0.9, 0.98, h))
    paint_fn(o, col)
    return keep(o, True)


parts.append(caramel())

# ---- cream dollop + cherry on top
TOPZ = b.H + 0.04
parts.append(goo("Cream", [((0, 0.05, TOPZ + 0.08), 0.5, (1, 1, 0.45)), ((0, 0.05, TOPZ + 0.3), 0.36, (1, 1, 0.55)),
                           ((0, 0.05, TOPZ + 0.48), 0.2)],
                 zgrad(CREAM_D, CREAM, TOPZ, TOPZ + 0.6), tris=160, resolution=0.08))
CH = Vector((0.02, 0.05, TOPZ + 0.86))
parts.append(ball("Cherry", 0.34, tuple(CH), along(CHERRY_D, CHERRY, CH + Vector((0.2, 0.2, -0.25)), CH + Vector((-0.15, -0.2, 0.2)))))
parts.append(ball("CherryHi", 0.07, tuple(CH + Vector((-0.13, -0.23, 0.14))), WHITE, subdiv=1))
parts.append(horn("Stem", [tuple(CH + Vector((0, 0, 0.26))), tuple(CH + Vector((0.08, 0.05, 0.54))), tuple(CH + Vector((0.25, 0.12, 0.72)))],
                  [0.04, 0.035, 0.03], hexc("4a8a2a"), hexc("6ab838"), segs=5))

f = Face(b, eye_v=1.28, mouth_v=0.86, s=1.1)
f.eyes("wink").mouth("open", w=1.05).cheeks(color=hexc("ff8a7a"))
parts += f.parts
ship("slime_flan", parts)
