# Cerberus (Mythic, Meadow set): a three-headed puppy slime, cute not scary. The slime body is the
# middle head (big glossy puppy eyes, black button nose, tongue out); two smaller puppy heads sit on
# its shoulders, turned outward, each with its own mood (left: sleepy, right: excited). Floppy ears
# on every head, cream muzzles, red spiked collars with gold studs and a gold bone tag, a little tail.
from models._slimepool import *

FUR, FUR_D, FUR_L = hexc("b2a0ff"), hexc("9a88f0"), hexc("cbc0ff")
EAR, EAR_D = hexc("8c7cea"), hexc("7c6cde")
MUZ = hexc("fff2e4")
NOSE = hexc("2a2040")
COLLAR, COLLAR_D = hexc("ff4d6d"), hexc("e8385a")
STUD, STUD_L = hexc("ffda5c"), hexc("fff2a8")

H = 2.75


def paint(a, z, p):
    c = mix(FUR_D, FUR, smoothstep(0.1, 1.3, z))
    c = mix(c, FUR_L, smoothstep(1.9, 2.75, z))
    # cream muzzle patch on the middle head
    e = (math.degrees(a) / 34) ** 2 + ((z - 1.12) / 0.36) ** 2
    return mix(c, MUZ, 1 - smoothstep(0.8, 1.0, e))


b = Body([(0, 1.08), (0.12, 1.34), (0.5, 1.5), (1.05, 1.47), (1.7, 1.26), (2.25, 0.88), (2.6, 0.42), (H, 0)],
         paint=paint, segs=32, sub=2, gloss=0.8)
parts = [b.obj]


def furgrad(C, r):
    return lambda p, n: mix(mix(FUR_D, FUR, smoothstep(C.z - r, C.z, p.z)), FUR_L, smoothstep(C.z, C.z + r, p.z))


# ---- side heads on the shoulders, turned outward
HEADS = {}
for sd in (-1, 1):
    C = Vector((sd * 1.38, -0.22, 2.12))
    r = 0.82
    yaw = sd * 26

    def hpaint(p, n, C=C, yaw=yaw, r=r):
        c = furgrad(C, r)(p, n)
        a = math.radians(yaw)
        f = Vector((math.sin(a), -math.cos(a), 0))
        q = p - (C + f * r * 0.85 + Vector((0, 0, -0.16)))
        d = (q.length / 0.36)
        return mix(c, MUZ, 1 - smoothstep(0.8, 1.0, d))
    sph = [(-r * 0.9 * math.cos(math.pi * k / 12), r * math.sin(math.pi * k / 12)) for k in range(13)]
    sph[0], sph[-1] = (sph[0][0], 0.0), (sph[-1][0], 0.0)
    hd = lathe(f"Head{sd}", sph, hpaint, pos=tuple(C), segs=20, sy=0.96)
    register(hd, f"Head{sd}")
    parts.append(hd)
    HEADS[sd] = (C, r, yaw)


def head_frame(sd):
    C, r, yaw = HEADS[sd]
    return frame_at(yaw, C.z, cx=C.x, cy=C.y)


# ---- floppy ears: teardrops hanging down the side of each head
EAR_POLY = [(0, 0.05), (0.2, 0.02), (0.3, -0.25), (0.32, -0.6), (0.22, -0.88), (0.0, -0.98), (-0.22, -0.88), (-0.3, -0.55), (-0.24, -0.2), (-0.16, 0.02)]


def ear(name, root, radial, scale, splay):
    radial = Vector(radial).normalized()
    tan = Vector((0, 0, 1)).cross(radial).normalized()
    down = (Vector((0, 0, -1)) + radial * splay).normalized()
    poly = [(x * scale, y * scale) for x, y in EAR_POLY]
    R = Vector(root) + radial * 0.06
    col = lambda p, n, R=R, s=scale: mix(EAR, EAR_D, smoothstep(0.0, 0.9 * s, R.z - p.z))
    return puffy_slab(name, poly, 0.16 * scale + 0.04, tuple(R), tuple(tan), tuple(-down), col, rows=2)


for sd in (-1, 1):
    a = math.radians(sd * 40)
    root = b.point(a, 2.5, 0.0)
    parts.append(ear(f"Ear{sd}", root, (math.sin(a), -math.cos(a), 0), 1.0, 0.55))
    C, r, yaw = HEADS[sd]
    for k, off in enumerate((62, -48)):  # outer ear, inner ear (smaller, behind the middle head)
        aa = math.radians(yaw + sd * off)
        radial = Vector((math.sin(aa), -math.cos(aa), 0))
        root = C + radial * r * 0.82 + Vector((0, 0, r * 0.42))
        parts.append(ear(f"Ear{'O' if k == 0 else 'I'}{sd}", root, radial, 0.66 if k == 0 else 0.55, 0.5))

# ---- middle face: big glossy puppy eyes, button nose, tongue out, blush
f = Face(b, eye_v=1.58, eye_u=0.5, mouth_v=0.96)
f.eyes("big", w=0.5, h=0.6)
f.d("Nose", oval(0, 1.26, 0.3, 0.2, n=14), NOSE, off=0.02, th=0.03)
f.d("NoseHi", oval(-0.05, 1.3, 0.1, 0.06, n=8), WHITE, off=0.06, th=0.008)
f.mouth("tongue", w=1.15, v=1.06)
f.cheeks(color=hexc("ff9ec4"), w=0.28, h=0.13, u=0.86, v=1.3)
parts += f.parts


# ---- side faces (decals on each head): named Eye* so they blink with the middle face
def hd(name, sd, poly, color, off=0.02, th=0.025, k=1.3):
    poly = [(x * k, (y + 0.02) * k - 0.02) for x, y in poly]
    return decal(name, poly, color, head_frame(sd), off=off, th=th, on=[f"Head{sd}"])


# left head (viewer's left, sd=-1): sleepy, content
sd = -1
for e in (-1, 1):
    parts.append(hd(f"EyeS{e}", sd, arc(e * 0.23, 0.12, 0.11, 200, 340, 0.06, n=8), INK))
parts.append(hd("NoseS", sd, oval(0, -0.06, 0.18, 0.12, n=12), NOSE, off=0.02, th=0.03))
parts.append(hd("MouthS", sd, arc(0, -0.13, 0.09, 200, 340, 0.045, n=8), hexc("5c1830")))
parts.append(hd("CheekS", sd, oval(-0.36, -0.02, 0.16, 0.08, n=10), hexc("ff9ec4"), off=0.012, th=0.015))
# right head (sd=1): excited, sparkly eyes, open mouth
sd = 1
for e in (-1, 1):
    parts.append(hd(f"EyeX{e}", sd, oval(e * 0.23, 0.12, 0.22, 0.27, n=14), INK, off=0.015))
    parts.append(hd(f"EyeXHi{e}", sd, oval(e * 0.23 - 0.04, 0.17, 0.08, 0.08, n=8), WHITE, off=0.05, th=0.012))
parts.append(hd("NoseX", sd, oval(0, -0.06, 0.18, 0.12, n=12), NOSE, off=0.02, th=0.03))
parts.append(hd("MouthX", sd, half_oval(0, -0.13, 0.2, 0.13, n=10), hexc("5c1830")))
parts.append(hd("TongueX", sd, oval(0, -0.21, 0.1, 0.06, n=8), TONGUE, off=0.04, th=0.012))
parts.append(hd("CheekX", sd, oval(0.36, -0.02, 0.16, 0.08, n=10), hexc("ff9ec4"), off=0.012, th=0.015))


# ---- spiked collars: one round the middle body low, one round each side head's neck
def spike(name, base, direction, L=0.2, r=0.08):
    d = Vector(direction).normalized()
    return lathe(name, [(0, r), (L * 0.55, r * 0.6), (L, 0)], zgrad(STUD, STUD_L, base.z - 0.1, base.z + 0.1),
                 pos=tuple(base), axis=tuple(d), segs=6, smooth=False)


zc = 0.62
Rc = b.radius(zc)
parts.append(torus("Collar", Rc + 0.02, 0.1, (0, 0, zc), (0, 0, 1), lambda p, n: mix(COLLAR_D, COLLAR, 0.5 + 0.5 * n.z), segs=32, rsegs=5))
for k in range(10):
    a = math.radians(18 + k * 36)
    rad = Vector((math.sin(a), -math.cos(a), 0))
    parts.append(spike(f"Spike{k}", Vector((0, 0, zc)) + rad * (Rc + 0.1), rad, L=0.26, r=0.1))
# gold bone tag at the front, under the mouth
tag_c = b.point(0, zc - 0.2, 0.06)
for sd in (-1, 1):
    parts.append(ball(f"Tag{sd}", 0.075, tuple(tag_c + Vector((sd * 0.13, -0.02, 0.05))), STUD_L, subdiv=1))
    parts.append(ball(f"TagB{sd}", 0.075, tuple(tag_c + Vector((sd * 0.13, -0.02, -0.05))), STUD_L, subdiv=1))
parts.append(horn("TagBar", [tuple(tag_c + Vector((-0.13, -0.02, 0))), tuple(tag_c + Vector((0.13, -0.02, 0)))], [0.06, 0.06], STUD, STUD, segs=6))
parts.append(horn("TagRing", [tuple(b.point(0, zc, 0.12)), tuple(tag_c + Vector((0, -0.01, 0.06)))], [0.03, 0.03], STUD, STUD, segs=5))

for sd in (-1, 1):
    C, r, yaw = HEADS[sd]
    axis = Vector((-sd * 0.42, 0.0, 1)).normalized()
    nc = C + Vector((sd * 0.06, 0.0, -0.5))
    parts.append(torus(f"CollarS{sd}", 0.62, 0.09, tuple(nc), tuple(axis), lambda p, n: mix(COLLAR_D, COLLAR, 0.5 + 0.5 * n.z), segs=18, rsegs=5))
    q = axis.to_track_quat("Z", "Y")
    for k in range(5):
        a = math.radians((0 if sd > 0 else 180) - sd * 40 + (k - 2) * 40 * sd)
        rad = q @ Vector((math.cos(a), math.sin(a), 0))
        if rad.y > 0.5:
            continue
        parts.append(spike(f"SpikeS{sd}{k}", nc + rad * 0.7, rad, L=0.16, r=0.065))

# ---- little wagging tail behind
tp = [(0, 1.36, 0.6), (0.05, 1.78, 0.78), (0.12, 2.0, 1.15), (0.1, 1.96, 1.5), (-0.02, 1.8, 1.72)]
parts.append(horn("Tail", tp, [0.2, 0.18, 0.15, 0.11, 0.05], FUR, FUR_L, segs=8))

ship("slime_cerberus", parts)
