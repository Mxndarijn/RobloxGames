# Supernova (Celestial): a bursting white-hot star slime. The body glows white-yellow at the front
# core and runs hot through orange to pink-magenta at its rim and foot, a flat blast-wave shock ring
# rips round it (white at the inner edge, pink ripples at the outer edge), crystal flare rays shoot
# out of it in every direction with a gap (they float, the star is bursting), a few hot sparks drift
# round it, and the face is a thrilled "BOOM": magenta star eyes and a wide open shout.
from models._slimepool import *
import random

CORE, HOT, YEL = hexc("fffdf2"), hexc("fff4a8"), hexc("ffd468")
ORA, PINK, MAG = hexc("ffb04a"), hexc("ff7ab4"), hexc("ff5aa2")
RING_W, RING_Y, RING_P = hexc("fffbe6"), hexc("ffd84a"), hexc("ff5aa8")
RAY_W, RAY_Y, RAY_O, RAY_P = hexc("ffffff"), hexc("fff2b0"), hexc("ffa43a"), hexc("ff6ab0")
INKS = hexc("6a1240")
EYE_C = hexc("ff3e8e")

C = Vector((0, 0.0, 1.45))  # star centre (rays radiate from here)
HOTSPOT = Vector((0, -1.15, 1.6))  # white-hot core seen through the front
HOTBACK = Vector((0, 1.3, 1.7))  # a second, smaller hot spot so the back glows too


def paint(a, z, p):
    d = min((p - HOTSPOT).length, (p - HOTBACK).length + 0.8)
    c = mix(CORE, HOT, smoothstep(0.35, 1.0, d))
    c = mix(c, YEL, smoothstep(0.8, 1.35, d))
    c = mix(c, ORA, smoothstep(1.35, 1.95, d))
    c = mix(c, PINK, smoothstep(1.9, 2.5, d))
    c = mix(c, MAG, 0.6 * smoothstep(2.7, 3.2, d))
    # hot plasma swirls
    n = noise.noise(Vector((p.x * 1.6, p.y * 1.6, p.z * 1.3 + 11.0)))
    c = mix(c, HOT, 0.3 * smoothstep(0.2, 0.55, n) * smoothstep(1.2, 2.6, d))
    # glowing foot rim
    c = mix(c, PINK, 0.35 * smoothstep(0.4, 0.0, z))
    return c


b = Body([(0, 1.05), (0.14, 1.38), (0.55, 1.56), (1.2, 1.56), (1.85, 1.34), (2.4, 0.96), (2.8, 0.48), (3.0, 0)],
         paint=paint, segs=36, sub=2, gloss=0.6, shade=0.35)
parts = [b.obj]
H = b.H


# ---------------------------------------------------------------- shock ring (flat blast wave)
def shock_ring(name, r_in, r_out, th, center, normal, segs=72, csegs=8, ripples=9, amp=0.12):
    """flat annulus with a lens cross-section, the outer edge rippled like a blast wave; colour by
    radius (white inner edge -> gold -> pink outer edge)."""
    n = Vector(normal).normalized()
    q = n.to_track_quat("Z", "Y")
    O = Vector(center)
    bm = bmesh.new()
    rings, ts = [], []
    for i in range(segs):
        a = i * math.tau / segs
        ro = r_out + amp * (0.5 + 0.5 * math.sin(a * ripples)) - amp * 0.5
        rm, hw = (r_in + ro) / 2, (ro - r_in) / 2
        ca = Vector((math.cos(a), math.sin(a), 0))
        ring = []
        for j in range(csegs):
            t = j * math.tau / csegs
            rad = rm + math.cos(t) * hw
            h = math.sin(t) * th / 2 * (0.35 + 0.65 * (1 - abs(math.cos(t))))
            ring.append(bm.verts.new(O + q @ (ca * rad + Vector((0, 0, h)))))
        rings.append(ring)
    for i in range(segs):
        A, B = rings[i], rings[(i + 1) % segs]
        for j in range(csegs):
            k = (j + 1) % csegs
            bm.faces.new((A[j], B[j], B[k], A[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm)

    def col(p, nn):
        d = q.inverted() @ (p - O)
        r = math.hypot(d.x, d.y)
        t = (r - r_in) / max(r_out - r_in, 1e-6)
        c = mix(RING_W, RING_Y, smoothstep(0.05, 0.45, t))
        return mix(c, RING_P, smoothstep(0.45, 0.95, t))
    paint_fn(o, col)
    return keep(o, True)


RN = Vector((0, -0.42, 1)).normalized()
RC = Vector((0, 0.05, 1.2))
parts.append(shock_ring("ShockRing", 1.85, 2.6, 0.12, RC, RN))

# ---------------------------------------------------------------- flare rays (floating crystal shards)
def shard(name, base, d, L, w):
    """4-sided bipyramid shard along d: white root -> gold -> orange -> pink tip, flat shaded."""
    d = Vector(d).normalized()
    fn = lambda p, n: (lambda t: mix(mix(RAY_W, RAY_Y, smoothstep(0.0, 0.35, t)), RAY_P, smoothstep(0.45, 0.95, t)))(
        min(1.0, max(0.0, (p - Vector(base)).dot(d) / L)))
    return lathe(name, [(0, 0), (L * 0.22, w), (L, 0)], fn, pos=tuple(base), axis=tuple(d), segs=5, smooth=False)


rng = random.Random(3)
dirs = []
N = 32
for i in range(N):  # fibonacci sphere, keep the ones off the face and above the floor
    y = 1 - 2 * (i + 0.5) / N
    r = math.sqrt(1 - y * y)
    th = i * math.pi * (3 - math.sqrt(5))
    v = Vector((math.cos(th) * r, math.sin(th) * r, y))  # z = y
    v = Vector((v.x, v.y, v.z))
    if v.z < -0.15:
        continue
    if v.dot(Vector((0, -1, 0.15)).normalized()) > 0.62:  # leave the face clear
        continue
    dirs.append(v)
for k, d in enumerate(dirs):
    long = k % 2 == 0
    L = (1.3 if long else 0.8) * rng.uniform(0.9, 1.1)
    w = 0.27 if long else 0.2
    start = C + Vector((d.x * 1.62, d.y * 1.62, d.z * 1.6)) + d * 0.18
    parts.append(shard(f"Ray{k}", start, d, L, w))

# ---------------------------------------------------------------- sparks drifting round it
for j, (pos, r) in enumerate((((-2.3, -0.4, 3.0), 0.16), ((2.35, -0.3, 3.15), 0.13), ((-2.55, 0.2, 1.9), 0.11),
                              ((2.6, 0.3, 2.0), 0.12), ((0.0, -0.4, 3.9), 0.14))):
    parts.append(slab(f"Spark{j}", star(0, 0, r * 1.6, r * 0.45, n=4), 0.06, pos, (1, 0, 0), (0, 0.25, 1), RAY_Y))

# ---------------------------------------------------------------- thrilled face: magenta star eyes, wide shout
f = Face(b, eye_u=0.55, eye_v=1.7, mouth_v=1.15, s=1.1, ink=INKS, mouth_col=hexc("a01848"))
f.eyes("star", color=EYE_C)
f.mouth("open", w=1.25)
f.cheeks(color=hexc("ff7ab0"), w=0.32, h=0.15)
parts += f.parts

ship("slime_supernova", parts)
