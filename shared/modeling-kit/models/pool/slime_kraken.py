# Kraken (hybrid, tier 5: octo + chomp + zap): deep-sea monster. Octo's tall bulb head in dark
# abyss teal with a pale shark belly, Chomp's swept dorsal fin and wide tooth grin, glowing
# bioluminescent spots, tentacles raised menacingly (two curl on the ground, four rear up round
# the head), Zap's electric bolts crackling between the raised tips.
from models._slimepool import *

TEAL_D, TEAL, TEAL_L = hexc("0a3242"), hexc("13707e"), hexc("1fa3a8")
BELLY, SUCK = hexc("9ff0dc"), hexc("c8fff0")
GLOW, GLOW_C = hexc("3dffe8"), hexc("eafffb")
BOLT, BOLT_L = hexc("ffe02a"), hexc("fff6a0")
EYE = hexc("ffe23a")


def belly_z(a):
    return 0.35 + 0.95 * max(0.0, math.cos(a * 0.9)) ** 1.4


def paint(a, z, p):
    top = mix(TEAL, TEAL_D, smoothstep(1.2, 3.3, z))
    top = mix(mix(TEAL_D, TEAL, 0.6), top, smoothstep(0.0, 0.6, z))
    f = smoothstep(belly_z(a) + 0.15, belly_z(a) - 0.15, z)
    return mix(top, BELLY, f)


b = Body([(0, 1.0), (0.2, 1.15), (0.6, 1.28), (1.3, 1.5), (2.1, 1.52), (2.8, 1.2), (3.25, 0.6), (3.42, 0)],
         paint=paint, segs=36, sub=2, gloss=0.5, lean=lambda z: 0.18 * max(0.0, (z - 2.0) / 1.4) ** 2)
parts = [b.obj]


def tent_col(p, n):
    h = smoothstep(0.2, 3.2, p.z)
    return mix(TEAL_D, TEAL_L, 0.3 + 0.7 * h)


def path(rz):
    return catmull(rz, 2)


def ptube(name, pts, radii, color_fn, segs=7):
    """tapered tube with rotation-minimising frames (lib tube() flips its ring frame where the
    path turns past the Y axis, which shows as dark twisted joints)."""
    P = [Vector(p) for p in pts]
    bm = bmesh.new()
    rings = []
    nrm = None
    for i, p in enumerate(P):
        d = (P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized()
        if nrm is None:
            nrm = d.cross(Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))).normalized()
        nrm = (nrm - d * nrm.dot(d)).normalized()
        bi = d.cross(nrm)
        rings.append([bm.verts.new(p + (nrm * math.cos(k * math.tau / segs) + bi * math.sin(k * math.tau / segs)) * radii[i])
                      for k in range(segs)])
    for a, b2 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b2[(k + 1) % segs], b2[k]))
    tip = bm.verts.new(P[-1] + (P[-1] - P[-2]).normalized() * radii[-1])
    for k in range(segs):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % segs], tip))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None)
    paint_fn(o, color_fn)
    return keep(o, True)


GROUND = path([(0.85, 0.32), (1.3, 0.26), (1.75, 0.24), (2.1, 0.35), (2.3, 0.62), (2.2, 0.85), (1.98, 0.8), (1.95, 0.62)])
RAISE_HI = path([(0.95, 0.4), (1.45, 0.42), (1.9, 0.75), (2.15, 1.35), (2.05, 2.0), (1.8, 2.6), (1.8, 3.2),
                 (2.05, 3.55), (2.35, 3.5), (2.42, 3.25), (2.25, 3.12)])
RAISE_MID = path([(0.95, 0.4), (1.45, 0.4), (1.9, 0.65), (2.2, 1.1), (2.25, 1.65), (2.1, 2.15), (2.25, 2.55),
                  (2.55, 2.6), (2.62, 2.35), (2.45, 2.25)])
tips = []
for k, (yaw, P) in enumerate(((-32, GROUND), (32, GROUND), (-78, RAISE_HI), (78, RAISE_HI), (-138, RAISE_MID), (138, RAISE_MID))):
    a = math.radians(yaw)
    pts = [(math.sin(a) * r, -math.cos(a) * r, z) for r, z in P]
    n = len(pts)
    rad = [0.36 - 0.29 * (i / (n - 1)) ** 0.9 for i in range(n)]
    parts.append(ptube(f"Tent{k}", pts, rad, tent_col, segs=6))
    tips.append(Vector(pts[-3]))
    # glowing suckers on the front / inner face of each tentacle
    for j in range(3, n - 3, 4):
        pj = Vector(pts[j])
        tang = (Vector(pts[j + 1]) - Vector(pts[j - 1])).normalized()
        radial = Vector((math.sin(a), -math.cos(a), 0))
        want = Vector((0, 0, 1)) if P is GROUND else (Vector((0, -1, 0)) - radial * 0.6)
        side = (want - tang * want.dot(tang)).normalized()
        r = rad[j]
        parts.append(lathe(f"Suck{k}{j}", [(0, r * 0.5), (r * 0.18, r * 0.42), (r * 0.24, 0)], mix(SUCK, GLOW, 0.4),
                           pos=tuple(pj + side * r * 0.78), axis=tuple(side), segs=6))

# shark dorsal fin on the back of the bulb
fin = [(-0.7, 0), (0.62, 0), (0.7, 0.34), (0.82, 0.48), (0.68, 0.62), (0.72, 0.9), (0.98, 1.5),
       (0.65, 1.44), (0.12, 1.02), (-0.34, 0.52)]
parts.append(puffy_slab("Fin", fin, 0.34, (0, 0.85, 2.7), (0, 1, 0.35), (0, -0.35, 1), zgrad(TEAL_D, TEAL, 2.6, 3.8)))

# bioluminescent spots: glowing ring with a bright core, over the head and back
specs = [(50, 2.7, 0.34), (-50, 2.7, 0.34), (88, 2.05, 0.28), (-88, 2.05, 0.28), (122, 2.75, 0.3), (-122, 2.75, 0.3),
         (158, 1.95, 0.3), (-158, 1.95, 0.3), (180, 2.95, 0.28), (24, 3.12, 0.2), (-24, 3.12, 0.2)]
specs = [(a_, z_, w_ * 1.2) for a_, z_, w_ in specs]
for k, (yaw, z, w) in enumerate(specs):
    parts.append(decal(f"Glow{k}", oval(0, 0, w, w, n=12), GLOW, frame_at(yaw, z), off=0.012, th=0.02, on=["Body"], step=0))
    parts.append(decal(f"GlowC{k}", oval(0, 0, w * 0.5, w * 0.5, n=8), GLOW_C, frame_at(yaw, z), off=0.035, th=0.012, on=["Body"], step=0))

# Zap's bolts crackling between the raised tips
def bolt_poly(s=1.0):
    pts = [(-0.05, 0.5), (0.25, 0.5), (0.08, 0.1), (0.3, 0.1), (-0.15, -0.55), (0.0, -0.08), (-0.22, -0.08)]
    return [(x * s, y * s) for x, y in pts]


for sd in (-1, 1):
    parts.append(slab(f"Bolt{sd}", bolt_poly(1.0), 0.12, (sd * 1.55, -0.85, 3.75), (sd * 0.6, -0.8, 0), (sd * 0.25, 0, 1),
                      zgrad(BOLT, BOLT_L, 3.2, 4.3)))
for k, (x, y, z, r) in enumerate([(-2.6, -0.5, 3.0, 0.12), (2.65, -0.4, 3.1, 0.12), (0.0, -1.0, 3.85, 0.1)]):
    parts.append(gem(f"Spark{k}", (x, y, z), r, BOLT, segs=4))

f = Face(b, eye_v=1.92, mouth_v=1.28, eye_u=0.52)
f.eyes("angry", w=0.5, h=0.62, iris=EYE)
f.brows("worried", w=0.38, th=0.09, lift=-0.04)  # lib swap: "worried" draws inner ends DOWN = angry
f.mouth("shark", w=1.4)
parts += f.parts
ship("slime_kraken", parts)
