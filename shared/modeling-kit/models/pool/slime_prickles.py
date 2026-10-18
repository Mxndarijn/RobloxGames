# Prickles (Uncommon): tough little cactus. Tall ribbed green body with two saguaro arms, rows of
# pale spines on the ribs, a pink flower on the head, a squint and a smirk.
from models._slimepool import *

G, G_D, G_L = hexc("3fc45a"), hexc("1f8a44"), hexc("8ef06a")
SPINE, SPINE_T = hexc("fff6c8"), hexc("ffffff")
PETAL, PETAL_D, PETAL_C = hexc("ff6fb2"), hexc("e0307e"), hexc("ffd23a")
RIBS = 8


def rib(a):
    return math.cos(RIBS * a)


def paint(a, z, p):
    c = mix(G_D, G, smoothstep(-0.9, 0.7, rib(a)))
    return mix(c, G_L, 0.35 * smoothstep(0.75, 1.0, rib(a)) * smoothstep(0.4, 2.6, z))


b = Body([(0, 1.05), (0.12, 1.28), (0.5, 1.36), (1.4, 1.32), (2.3, 1.18), (2.9, 0.86), (3.25, 0.4), (3.38, 0)],
         paint=paint, segs=48, sub=2, sx=0.95, sy=0.92, gloss=0.55,
         bump=lambda a, z: 0.07 * rib(a) * smoothstep(0.0, 0.25, z))
parts = [b.obj]

# spines: little cones on the rib ridges, skipping the face area
def spine(name, pos, d, L=0.26, r=0.045):
    return lathe(name, [(0, r), (L, 0)], along(SPINE, SPINE_T, pos, Vector(pos) + Vector(d) * L), pos=pos, axis=d, segs=4, smooth=False)


# arms: saguaro elbows, ribbed look via a darker underside
def arm_col(p, n):
    return mix(G_D, G, smoothstep(-0.6, 0.6, n.z + 0.3 * n.x))


for sd, z0, up in ((-1, 1.25, 0.95), (1, 1.6, 0.7)):
    root = b.point(sd * math.pi / 2, z0, extra=-0.2)
    out = root + Vector((sd * 0.65, 0, 0))
    pts = [root, root + Vector((sd * 0.45, 0, 0.0)), out + Vector((sd * 0.12, 0, 0.18)), out + Vector((sd * 0.15, 0, 0.18 + up))]
    parts.append(horn(f"Arm{sd}", pts, [0.3, 0.28, 0.27, 0.25], G, G, segs=10))
    parts[-1] = paint_fn(parts[-1], arm_col)
    parts.append(ball(f"ArmTip{sd}", 0.25, tuple(pts[-1]), G, squash=(1, 1, 0.9)))
    tip = pts[-1]
    for j, (dz, ang) in enumerate(((-0.35, 0), (-0.1, 180), (0.12, 90 * sd), (-0.6, 90 * sd), (-0.45, 180))):
        ra = math.radians(ang)
        d = Vector((math.sin(ra) * (1 if ang != 180 else 0) + (sd * 0.0), -math.cos(ra), 0.2)).normalized()
        if ang == 90 * sd:
            d = Vector((sd, 0, 0.25)).normalized()
        parts.append(spine(f"ArmSpine{sd}{j}", tuple(tip + Vector((0, 0, dz)) + d * 0.22), tuple(d)))

k = 0
for i in range(RIBS):
    a = i * math.tau / RIBS + math.tau / RIBS / 2 * 0  # ridge yaw (cos max)
    for z in (0.55, 1.05, 1.55, 2.05, 2.55, 2.95):
        if abs(math.atan2(math.sin(a), math.cos(a))) < 0.6 and 0.7 < z < 2.3:
            continue  # keep the face clear
        if z > 2.9 and i % 2:
            continue
        zz = z + (0.25 if i % 2 else 0)
        if zz > 3.1:
            continue
        p = b.point(a, zz, extra=-0.02)
        n = Vector((math.sin(a), -math.cos(a), 0.25 + 0.4 * smoothstep(2.3, 3.2, zz))).normalized()
        parts.append(spine(f"Spine{k}", tuple(p), tuple(n)))
        k += 1

# flower on top: 5 puffy petals + yellow centre
top = Vector((0, 0, b.H - 0.06))
for i in range(5):
    ang = i * math.tau / 5 + 0.3
    d = Vector((math.cos(ang), math.sin(ang), 0))
    X = (d + Vector((0, 0, 0.5))).normalized()
    Yv = Vector((-math.sin(ang), math.cos(ang), 0))
    petal = [(0, 0), (0.35, -0.33), (0.85, -0.3), (1.05, 0), (0.85, 0.3), (0.35, 0.33)]
    parts.append(puffy_slab(f"Petal{i}", petal, 0.13, top, X, Yv, along(PETAL_D, PETAL, top, top + X * 1.0), rows=2))
parts.append(ball("FlowerC", 0.24, tuple(top + Vector((0, 0, 0.16))), along(hexc("ff9a1a"), PETAL_C, top, top + Vector((0, 0, 0.4))), squash=(1, 1, 0.7)))

f = Face(b, eye_v=1.72, mouth_v=1.2, s=1.15)
f.eyes("angry", w=0.42, h=0.5).mouth("smirk", w=1.0)
for sd in (-1, 1):  # tough brows: inner ends down (local: the kit's "angry" brows tilt the other way)
    f.d(f"Brow{sd}", rect(sd * f.eu, f.ev + 0.36, 0.42, 0.09, math.radians(20 * sd)), INK)
parts += f.parts
ship("slime_prickles", parts)
