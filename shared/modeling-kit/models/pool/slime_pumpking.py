# Pumpking (Boss, Mythic): giant jack-o'-lantern slime. A wide, squat, deeply ribbed orange pumpkin
# (8 lobes, dark grooves, light lobes), a thick curly dark-green stem with two big leaves and a curly
# vine tendril, a small gold crown sitting tilted round the stem, and a carved face (triangle eyes,
# triangle nose, jagged toothy grin) that glows candle-yellow from inside.
from models._slimepool import *


def offset_poly(poly, d):
    """outward miter offset of a simple polygon by d (any winding)."""
    n = len(poly)
    area = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))
    s = 1 if area > 0 else -1  # ccw: outward normal of edge (dx, dy) is (dy, -dx)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(poly[i - 1]), Vector(poly[i]), Vector(poly[(i + 1) % n])
        e0, e1 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n0, n1 = Vector((e0.y, -e0.x)) * s, Vector((e1.y, -e1.x)) * s
        m = (n0 + n1)
        m = m.normalized() if m.length > 1e-6 else n0
        k = min(2.5, 1.0 / max(0.2, m.dot(n0)))
        out.append(tuple(p1 + m * d * k))
    return out


def seg_dist(p, a, b):
    ab = b - a
    t = min(1, max(0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def glow_fn(poly, depth):
    """candle glow: orange at the cut edge -> pale yellow core (distance to the outline in x/z)."""
    P = [Vector(q) for q in poly]

    def fn(p, n):
        q = Vector((p.x, p.z))
        d = min(seg_dist(q, P[i], P[(i + 1) % len(P)]) for i in range(len(P)))
        t = smoothstep(0.0, depth, d)
        c = mix(GLOW_E, GLOW, smoothstep(0.0, 0.45, t))
        return mix(c, GLOW_C, smoothstep(0.45, 1.0, t))
    return fn


# ---- palette
OR, OR_L, OR_D, OR_G = hexc("f7801c"), hexc("ffaa44"), hexc("f07a1a"), hexc("d4640f")
STEM_D, STEM, STEM_L = hexc("3a6620"), hexc("54822c"), hexc("78a63e")
LEAF_D, LEAF, LEAF_L = hexc("3a8a2a"), hexc("46a032"), hexc("7cc84a")
CUT = hexc("4a1604")
GLOW_E, GLOW, GLOW_C = hexc("ff9a10"), hexc("ffd23a"), hexc("fff8b8")
RUBY = hexc("ff2a4a")

LOBES = 8


def groove(a):
    """0 on a lobe crest, 1 in a groove (sharp groove, round lobe)."""
    return 1.0 - abs(math.cos(LOBES * a / 2)) ** 0.45


def bump(a, z):
    amp = 0.11 * smoothstep(0.05, 0.6, z)
    return -amp * groove(a)


def paint(a, z, p):
    c = mix(OR_D, OR, smoothstep(0.1, 1.1, z))
    c = mix(c, OR_L, 0.55 * smoothstep(1.3, 2.5, z))
    return mix(c, OR_G, 0.75 * groove(a) ** 0.8)


PROF = [(0, 1.25), (0.35, 1.62), (0.95, 1.77), (1.6, 1.69), (2.15, 1.36), (2.5, 0.88), (2.68, 0.38), (2.72, 0)]
b = Body(PROF, paint=paint, bump=bump, segs=48, sub=2, dome=0.0, gloss=0.2, shade=0.8)

# dip the top round the stem (a pumpkin's crown sinks in), then re-register the surface
DIP, DIP_R = 0.26, 0.95
for v in b.obj.data.vertices:
    r = math.hypot(v.co.x, v.co.y)
    if r < DIP_R and v.co.z > 1.5:  # the top only, not the rounded underside
        v.co.z -= DIP * (1 - (r / DIP_R) ** 2) ** 1.5
b.obj.data.update()
register(b.obj, "Body")
TOPZ = b.H - DIP
parts = [b.obj]

# ---- stem: thick faceted dark-green stalk curling over at the tip, flared foot
stem_pts = [(0, 0, TOPZ - 0.15), (0.0, 0.0, TOPZ + 0.35), (-0.04, 0.03, TOPZ + 0.8), (0.04, 0.06, TOPZ + 1.18),
            (0.3, 0.07, TOPZ + 1.42), (0.62, 0.05, TOPZ + 1.4), (0.82, 0.02, TOPZ + 1.18), (0.8, 0.0, TOPZ + 0.94),
            (0.64, -0.02, TOPZ + 0.84)]
stem_r = [0.4, 0.33, 0.29, 0.26, 0.23, 0.2, 0.17, 0.14, 0.1]
parts.append(horn("Stem", stem_pts, stem_r, STEM_D, STEM_L, segs=6, smooth=False))
parts.append(lathe("StemFoot", [(0, 0.52), (0.12, 0.42), (0.3, 0.33), (0.36, 0)], zgrad(STEM_D, STEM, TOPZ - 0.1, TOPZ + 0.3),
                   pos=(0, 0, TOPZ - 0.12), segs=6, smooth=False))

# ---- leaves: two big lobed pumpkin leaves lying on the shoulders
def leaf_poly(L=1.25, W=0.95):
    pts = []
    n = 25
    for k in range(n):
        t = -math.pi * 0.92 + k * (math.pi * 1.84) / (n - 1)
        lobe = 0.74 + 0.26 * abs(math.cos(2.5 * t)) ** 0.6
        pts.append((L * 0.5 + math.cos(t) * L * 0.5 * lobe, math.sin(t) * W * 0.5 * lobe))
    return [(0.0, 0.0)] + pts


def place_leaf(name, yaw, L, W, curl=0.28, lift=0.05):
    """lobed leaf built flat, then draped over the body: every vertex drops onto the surface below
    it (+ its own thickness offset), and the tip curls up a little so the edge reads."""
    a = math.radians(yaw)
    d = Vector((math.sin(a), -math.cos(a), 0))
    side = Vector((math.cos(a), math.sin(a), 0))
    O = d * 0.22
    o = puffy_slab(name, leaf_poly(L, W), 0.11, (O.x, O.y, 0), d, side, along(LEAF_D, LEAF_L, O, O + d * L), rows=2)
    for v in o.data.vertices:
        hit = cast(Vector((v.co.x, v.co.y, 10)), Vector((0, 0, -1)), ["Body"])
        s = max(0.0, (v.co - O).dot(d)) / L
        v.co.z = hit[0].z + lift + v.co.z + curl * s ** 2
    o.data.update()
    return o


parts.append(place_leaf("Leaf0", -55, 1.35, 1.05))
parts.append(place_leaf("Leaf1", 150, 1.15, 0.9))

# ---- curly vine tendril: a spring that coils out over the right shoulder
vine = []
a0 = math.radians(80)
dv = Vector((math.sin(a0), -math.cos(a0), 0))
sv = Vector((math.cos(a0), math.sin(a0), 0))
for k in range(19):
    t = k / 18
    base = Vector((0, 0, TOPZ + 0.25)) + dv * (0.3 + 1.05 * t) + Vector((0, 0, 0.35 * math.sin(t * math.pi) - 0.25 * t))
    ang = t * math.tau * 2.0
    rr = 0.18 * (1 - 0.4 * t)
    vine.append(tuple(base + sv * math.cos(ang) * rr + Vector((0, 0, math.sin(ang) * rr))))
parts.append(horn("Vine", vine, [0.075 - 0.03 * k / 18 for k in range(19)], STEM, LEAF_L, segs=6))

# ---- crown: small gold crown, tilted, round the stem
def ring_band(name, r_in, r_out, h, color, segs=20):
    """open crown band: closed square-section annulus (no cap disc over the hole)."""
    bm = bmesh.new()
    sec = [(r_in, 0.0), (r_out, 0.0), (r_out * 1.03, h), (r_in * 1.03, h)]
    rings = [[bm.verts.new((math.sin(k * math.tau / segs) * r, -math.cos(k * math.tau / segs) * r, z)) for k in range(segs)] for r, z in sec]
    for i in range(4):
        A, B = rings[i], rings[(i + 1) % 4]
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((A[k], A[j], B[j], B[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, False)


def crown_parts():
    cr = 0.74
    gold = zgrad(GOLD_D, GOLD_L, 0.0, 0.7)
    out = [ring_band("CrownRing", cr * 0.9, cr * 1.03, 0.34, gold)]
    out.append(torus("CrownRim", cr * 1.05, 0.05, (0, 0, 0.02), (0, 0, 1), GOLD, segs=20, rsegs=5))
    for k in range(5):
        a = math.radians(k * 72)
        d = Vector((math.sin(a), -math.cos(a), 0))
        base = d * cr * 1.0 + Vector((0, 0, 0.28))
        tip = base + d * 0.1 + Vector((0, 0, 0.5))
        out.append(lathe(f"CrownSpike{k}", [(0, 0.19), (0.28, 0.11), (0.5, 0)], along(GOLD, GOLD_L, base, tip),
                         pos=base, axis=(tip - base), segs=6, smooth=False))
        out.append(ball(f"CrownPearl{k}", 0.07, tuple(tip + (tip - base).normalized() * 0.03), GOLD_L, subdiv=1))
    out.append(gem("CrownGem", (0, -cr * 1.06, 0.17), 0.14, RUBY, axis=(0, -1, 0), h=0.12, segs=6))
    return out


M = Matrix.Translation((0.08, -0.04, TOPZ + 0.04)) @ Matrix.Rotation(math.radians(-12), 4, "X") @ Matrix.Rotation(math.radians(16), 4, "Y")
for o in crown_parts():
    o.data.transform(M)
    parts.append(o)

# ---- carved face: dark cut rim + glowing inside
EV, NV, MV = 1.62, 1.2, 0.86


def carve(name, poly, rim=0.06, depth=0.16):
    out = [grid_decal(f"{name}Cut", offset_poly(poly, rim), CUT, off=0.006, th=0.012, on=["Body"])]
    out.append(grid_decal(name, poly, glow_fn(poly, depth), off=0.022, th=0.012, on=["Body"]))
    return out


for sd in (-1, 1):
    u = sd * 0.62
    eye = [(u - sd * 0.36, EV - 0.26), (u + sd * 0.4, EV - 0.3), (u + sd * 0.1, EV + 0.36)]
    if sd < 0:
        eye = list(reversed(eye))
    parts += carve(f"Eye{sd}", eye)
parts += carve("Nose", [(-0.17, NV - 0.12), (0.17, NV - 0.12), (0.0, NV + 0.16)], rim=0.05, depth=0.1)

# jagged grin: arched top lip with 3 fangs down, deep crescent jaw with 2 fangs up
W = 1.08
top = []
for k in range(25):
    x = -W + 2 * W * k / 24
    top.append((x, MV + 0.32 * (x / W) ** 2 + 0.06))
bot = []
for k in range(25):
    x = W - 2 * W * k / 24
    bot.append((x, MV + 0.38 * (x / W) ** 2 - 0.42 * (1 - (x / W) ** 2) ** 0.7 + 0.06))


def add_teeth(edge, centres, half, h, sign):
    out = []
    for x, y in edge:
        dy = 0.0
        for c in centres:
            if abs(x - c) < half:
                dy = max(dy, h * (1 - abs(x - c) / half))
        out.append((x, y + sign * dy))
    return out


top = add_teeth(top, (-0.45, 0.0, 0.45), 0.13, 0.26, -1)
bot = add_teeth(bot, (-0.24, 0.24), 0.13, 0.24, 1)
mouth = top + bot[1:-1]
parts += carve("Mouth", mouth, rim=0.065, depth=0.2)

ship("slime_pumpking", parts)
