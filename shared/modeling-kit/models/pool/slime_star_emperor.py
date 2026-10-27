# Star Emperor (Celestial tier jackpot): a regal cosmic slime. Deep-navy body with gold trim and a
# gold collar, a long flowing cape made of starry night sky (violet-blue, gold hem, stars), a crown
# of tiny planets orbiting on a tilted gold ring above its head, a gold scepter tipped with a big
# star, and a proud, confident face (half-lidded gold eyes, raised brow, smug smile).
from models._slimepool import *
import re

NAVY_D, NAVY, NAVY_L = hexc("16206a"), hexc("2438a4"), hexc("4a6ae6")
SKY_D, SKY, SKY_L = hexc("120a40"), hexc("3a1c8a"), hexc("6a4ae0")
STAR_C = hexc("fff6c8")
GD, G, GL, GW = GOLD_D, GOLD, GOLD_L, hexc("fff8d6")
IRIS = hexc("ffc93a")


def paint(a, z, p):
    c = mix(NAVY_D, NAVY, smoothstep(0.2, 1.6, z))
    c = mix(c, NAVY_L, 0.55 * smoothstep(1.8, 3.0, z))
    ad = abs(math.degrees(a))
    side = smoothstep(60, 88, ad) * smoothstep(135, 105, ad) * smoothstep(2.8, 2.0, z)
    c = mix(c, hexc("6a9aff"), 0.45 * side)  # cool rim light on the silhouette seen from the front
    # soft lighter face patch so the face reads on the dark body
    e = (ad / 58) ** 2 + ((z - 1.65) / 0.9) ** 2
    return mix(c, hexc("4a6ae0"), 0.5 * (1 - smoothstep(0.6, 1.0, e)))


BANDS = [(0.18, 0.34, G)]
b = Body([(0, 1.1), (0.14, 1.38), (0.55, 1.5), (1.25, 1.48), (1.95, 1.28), (2.5, 0.92), (2.9, 0.45), (3.1, 0)],
         paint=paint, bands=BANDS, segs=40, sub=2, gloss=0.8, shade=0.8)
parts = [b.obj]
H = b.H


def shell(name, fn, nu, nv, thick, color):
    """closed thick sheet (from slime_king.py): fn(s, t) -> point; offset along the sheet normal both ways."""
    bm = bmesh.new()
    P = [[Vector(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]

    def nrm(i, j):
        a = P[min(i + 1, nu)][j] - P[max(i - 1, 0)][j]
        b_ = P[i][min(j + 1, nv)] - P[i][max(j - 1, 0)]
        return a.cross(b_).normalized()
    outer = [[bm.verts.new(P[i][j] + nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    inner = [[bm.verts.new(P[i][j] - nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1]))
            bm.faces.new((inner[i][j + 1], inner[i + 1][j + 1], inner[i + 1][j], inner[i][j]))
    for i in range(nu):
        for j in (0, nv):
            bm.faces.new((outer[i][j], inner[i][j], inner[i + 1][j], outer[i + 1][j]))
    for j in range(nv):
        for i in (0, nu):
            bm.faces.new((outer[i][j], outer[i][j + 1], inner[i][j + 1], inner[i][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, True), P, nrm


# ---------------------------------------------------------------- night-sky cape
CZ = 2.15  # where the cape hangs from (collar height)
A0, A1 = math.radians(88), math.radians(272)


def cape_pt(s, t):
    open_ = math.radians(34) * t ** 1.2  # front edges sweep back as the cape falls: it opens like a flowing cape
    a = (A0 + open_) + ((A1 - open_) - (A0 + open_)) * s
    z = CZ - t * (CZ - 0.04)
    back = abs(math.cos(a - math.pi)) if abs(a - math.pi) < math.pi / 2 else 0.0
    flare = 0.08 + 0.55 * t ** 1.5
    wave = 0.16 * math.sin(s * math.tau * 4.0 + 0.4) * t ** 1.4
    p = b.point(a, max(z, 0.04), extra=flare + wave)
    trail = 1.35 * back * smoothstep(0.55, 1.0, t)  # the middle of the hem trails behind on the floor
    zz = z + 0.06 * smoothstep(0.8, 1.0, t) * back
    return (p.x * (1 + 0.06 * t), p.y + trail, max(zz, 0.04))


def cape_col(p, n):
    t = (CZ - p.z) / CZ
    c = mix(SKY_L, SKY, smoothstep(0.0, 0.5, t))
    c = mix(c, SKY_D, smoothstep(0.45, 1.0, t))
    # a faint milky way streak across the back
    m = math.exp(-((p.z - 0.9 - 0.35 * p.x) / 0.28) ** 2)
    c = mix(c, hexc("9a7cff"), 0.35 * m)
    if n.dot(Vector((p.x, p.y, 0)).normalized()) < -0.2:  # inner side: gold lining shows where the cape opens
        c = mix(GD, G, smoothstep(0.0, CZ, p.z))
    return c


NU, NV = 20, 8
cape, CP, cnrm = shell("Cape", cape_pt, NU, NV, 0.08, cape_col)
parts.append(cape)

# stars on the cape (outer side): little 4- and 5-point star slabs riding the surface
rng_pts = [(0.12, 0.25), (0.3, 0.5), (0.5, 0.3), (0.68, 0.55), (0.86, 0.3), (0.2, 0.75), (0.42, 0.85), (0.6, 0.72), (0.8, 0.82),
           (0.38, 0.14), (0.62, 0.12), (0.5, 0.62), (0.94, 0.62), (0.06, 0.55), (0.28, 0.95), (0.72, 0.95)]
for k, (s, t) in enumerate(rng_pts):
    i, j = round(s * NU), round(t * NV)
    p = CP[i][j]
    nn = cnrm(i, j)
    if nn.dot(Vector((p.x, p.y, 0))) < 0:
        nn = -nn
    up = Vector((0, 0, 1))
    xa = up.cross(nn).normalized()
    ya = nn.cross(xa).normalized()
    sz = 0.22 if k % 3 == 0 else 0.13
    parts.append(slab(f"CapeStar{k}", star(0, 0, sz, sz * (0.42 if k % 2 else 0.3), n=5 if k % 2 else 4), 0.03,
                      p + nn * 0.06, xa, ya, STAR_C))
# gold hem and front edges
hem = [Vector(cape_pt(i / 24, 1.0)) + Vector((0, 0, 0.05)) for i in range(25)]
parts.append(horn("CapeHem", [tuple(q) for q in hem], [0.07] * 25, G, GL, segs=6))
for sd, s in ((1, 0.0), (-1, 1.0)):
    edge = [tuple(Vector(cape_pt(s, t / 8))) for t in range(9)]
    parts.append(horn(f"CapeEdge{sd}", edge, [0.065] * 9, GL, G, segs=6))

# gold collar along the cape top (back half only, the face stays clear)
col_pts = [tuple(b.point(math.radians(a), CZ, 0.1)) for a in range(84, 280, 14)]
parts.append(horn("Collar", col_pts, [0.11] * len(col_pts), G, GL, segs=8))


# tall stand-up collar flaring out behind the head (night sky inside, gold rim)
def high_pt(s, t):
    a = math.radians(112 + 136 * s)
    mid = math.sin(s * math.pi)
    z = CZ - 0.05 + t * (0.45 + 0.5 * mid)  # low at the ends, tall in the middle: a fan, not a box
    r = b.radius(CZ) + 0.12 + 0.75 * t ** 1.2
    return (math.sin(a) * r * b.sx, -math.cos(a) * r * b.sy, z)


hc, HP, hn = shell("HighCollar", high_pt, 14, 4, 0.07, lambda p, n: mix(SKY, SKY_L, smoothstep(CZ, CZ + 1.1, p.z)))
parts.append(hc)
rim = [high_pt(i / 14, 1.0) for i in range(15)]
parts.append(horn("HighCollarRim", rim, [0.07] * 15, G, GL, segs=6))
for k, (s_, t_) in enumerate([(0.2, 0.55), (0.5, 0.7), (0.8, 0.55), (0.35, 0.3), (0.65, 0.3)]):
    i, j = round(s_ * 14), round(t_ * 4)
    p = HP[i][j]
    nn = hn(i, j)
    if nn.dot(Vector((p.x, p.y, 0))) > 0:
        nn = -nn  # inner side, facing the viewer in front
    xa = Vector((0, 0, 1)).cross(nn).normalized()
    parts.append(slab(f"CollarStar{k}", star(0, 0, 0.11, 0.04, n=4), 0.03, p + nn * 0.05, xa, nn.cross(xa).normalized(), STAR_C))
for sd in (-1, 1):
    p = b.point(math.radians(sd * 88), CZ, 0.16)
    d = Vector((p.x, p.y, 0)).normalized()
    parts.append(lathe(f"Clasp{sd}", [(0, 0.17), (0.06, 0.17), (0.1, 0)], GL, pos=tuple(p), axis=tuple(d), segs=12))

# ---------------------------------------------------------------- crown: tiny planets orbiting on a tilted gold ring
RC = Vector((0, 0.1, H + 0.72))
RN = Vector((0, -0.35, 1)).normalized()  # tilted toward the face so it reads from the front
RR = 1.12
parts.append(torus("CrownRing", RR, 0.06, RC, RN, lambda p, n: mix(G, GL, 0.5 + 0.5 * n.z), segs=40, rsegs=5))
q = RN.to_track_quat("Z", "Y")
PLANETS = [(0, 0.2, hexc("ff7a3a"), hexc("ffd09a")), (72, 0.16, hexc("4ad0ff"), hexc("d0f6ff")), (144, 0.22, hexc("b06bff"), hexc("e8d0ff")),
           (216, 0.15, hexc("3ae09a"), hexc("c8ffe0")), (288, 0.19, hexc("ff4a8a"), hexc("ffc8dc"))]
key = Vector((-0.4, -0.6, 0.7)).normalized()
for k, (deg, r, c0, c1) in enumerate(PLANETS):
    a = math.radians(deg - 90)
    p = RC + q @ Vector((math.cos(a) * RR, math.sin(a) * RR, 0))
    parts.append(ball(f"Planet{k}", r * 1.2, p, lambda pp, n, c0=c0, c1=c1: mix(c0, c1, 0.7 * max(0.0, n.dot(key)) ** 0.8), subdiv=2))
    if k == 2:
        parts.append(torus("PlanetRing", r * 1.75, 0.03, p, (0.35, -0.3, 1), hexc("ffe9a0"), segs=18, rsegs=4))
# a small gold star sun at the centre top, on a short spire
parts.append(lathe("Spire", [(0, 0.12), (0.5, 0.04), (0.65, 0)], GL, pos=(0, 0.05, H - 0.1), segs=8))
parts.append(puffy_slab("CrownStar", star(0, 0, 0.36, 0.17), 0.14, (0, 0.05, H + 0.85), (1, 0, 0), (0, 0, 1),
                        lambda p, n: mix(G, GW, 0.3 + 0.6 * smoothstep(H + 0.5, H + 1.2, p.z)), rows=2))

# ---------------------------------------------------------------- scepter on the right (+X), tipped with a big star
s0 = Vector((1.55, -0.55, 0.15))
s1 = Vector((1.95, -0.45, 3.0))
d = (s1 - s0).normalized()
parts.append(lathe("ScepterRod", [(0, 0.07), (2.6, 0.085), (2.75, 0.13), (2.9, 0.0)], along(GD, GL, s0, s1),
                   pos=tuple(s0), axis=tuple(d), segs=10))
for k, t in enumerate((0.3, 0.62)):
    parts.append(torus(f"ScepterBand{k}", 0.1, 0.035, s0 + d * (2.9 * t), d, GL, segs=12, rsegs=4))
parts.append(ball("ScepterOrb", 0.17, s0 + d * 2.95, GL, subdiv=2))
tip = s0 + d * 3.45
parts.append(puffy_slab("ScepterStar", star(0, 0, 0.66, 0.3), 0.22, tip, (1, 0, 0.0), (0, 0, 1),
                        lambda p, n: mix(G, GW, 0.25 + 0.65 * smoothstep(tip.z - 0.4, tip.z + 0.5, p.z)), rows=3))
# tiny hand nub holding it (a goo bump from the body)
parts.append(ball("Hand", 0.26, b.point(math.radians(78), 1.0, 0.05) + Vector((0.12, -0.1, 0)), lambda p, n: mix(NAVY, NAVY_L, 0.6), squash=(1, 0.9, 0.9)))

# ---------------------------------------------------------------- stars on the body (back and top only)
for k, (yaw, z, s) in enumerate([(130, 1.3, 0.09), (-140, 1.6, 0.08), (160, 2.3, 0.07), (-120, 2.5, 0.06), (60, 2.55, 0.06), (-55, 2.6, 0.07)]):
    parts.append(decal(f"BodyStar{k}", star(0, 0, s, s * 0.35, n=4), STAR_C, frame_at(yaw, z), off=0.012, th=0.012, on=["Body"]))

# floating twinkles round the emperor
for k, (x, y, z, sz) in enumerate([(-1.75, -0.5, 3.2, 0.2), (-2.1, 0.3, 1.9, 0.15), (2.35, 0.2, 2.1, 0.14), (1.0, -0.9, 4.0, 0.13)]):
    parts.append(slab(f"Twinkle{k}", star(0, 0, sz, sz * 0.3, n=4), 0.05, (x, y, z), (0.9, 0.45 * (1 if x > 0 else -1), 0), (0, 0, 1), STAR_C))

# ---------------------------------------------------------------- proud face
f = Face(b, eye_u=0.54, eye_v=1.8, mouth_v=1.2, s=1.22)
f.eyes("sly", w=0.5, h=0.68, iris=IRIS)
f.d("BrowL", rect(-0.56, 2.36, 0.44, 0.095, math.radians(-8)), INK)
f.d("BrowR", arc(0.56, 2.2, 0.25, 45, 135, 0.095, n=8), INK)
f.mouth("smirk", w=1.0, v=1.1)
f.cheeks(color=hexc("6a7aff"), w=0.26, h=0.11)
parts += f.parts

if os.environ.get("TRI_DBG"):
    import collections
    cnt = collections.Counter()
    for o in parts:
        cnt[re.sub(r"[-0-9]+$", "", o.name)] += sum(len(pl.vertices) - 2 for pl in o.data.polygons)
    print("TRIS", sorted(cnt.items(), key=lambda x: -x[1]))
ship("slime_star_emperor", parts)
