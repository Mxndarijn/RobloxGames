# Yeti (Mythic, Frost & Sea family): a big frosty yeti slime. Shaggy white-to-pale-blue fur (layered
# tuft rows in the body surface + fur tufts on the crown and cheeks), two curled blue ice horns, a dark
# blue face patch with a wide happy roar and fangs, ice crystal spikes down the back, snowflakes floating.
from models._slimepool import *

FUR, FUR_B, FUR_D = hexc("f4faff"), hexc("c8e6ff"), hexc("98c6f4")
PATCH, PATCH_L = hexc("23408e"), hexc("3a62b8")
ICE_D, ICE, ICE_L = hexc("1e78e0"), hexc("5ec4ff"), hexc("d8f6ff")
ROAR, TONGUE_C = hexc("7a1830"), hexc("ff7a9a")

NT = 16       # tuft columns round the body
ROW = 0.42    # tuft row height (studs)
EV = 1.78     # eye height
PATCH_W, PATCH_Z0, PATCH_Z1 = 58.0, 0.85, 2.3


def patch(a, z):
    """1 inside the dark face patch (front), 0 outside; soft 0.06 edge."""
    zc, zh = (PATCH_Z0 + PATCH_Z1) / 2, (PATCH_Z1 - PATCH_Z0) / 2
    e = (math.degrees(a) / PATCH_W) ** 2 + ((z - zc) / zh) ** 2
    return 1 - smoothstep(0.9, 1.0, e)


def tuft(a, z):
    """0..1 inside a fur clump: rows of down-pointing clumps, every other row shifted half a column."""
    v = z / ROW + 0.18 * noise.noise(Vector((math.cos(a) * 2.0, math.sin(a) * 2.0, z * 0.7)))
    row = math.floor(v)
    fv = v - row
    u = a * NT / math.tau + 0.5 * (row % 2)
    fu = u - math.floor(u)
    across = 1 - abs(fu - 0.5) * 2          # 1 mid-clump, 0 at the clump sides
    return max(0.0, across ** 0.6 - (1 - fv) * 0.9) if fv > 0 else 0.0


def fur_amount(a, z):
    return (1 - patch(a, z)) * smoothstep(0.15, 0.5, z) * (1 - smoothstep(2.75, 3.05, z))


def bump(a, z):
    return 0.12 * fur_amount(a, z) * tuft(a, z)


def paint(a, z, p):
    c = mix(FUR_B, FUR, smoothstep(0.3, 2.3, z))
    t = tuft(a, z)
    c = mix(c, FUR_D, 0.5 * fur_amount(a, z) * (1 - smoothstep(0.0, 0.2, t)))  # shadow between clumps
    pt = patch(a, z)
    return mix(c, mix(PATCH, PATCH_L, smoothstep(PATCH_Z0, PATCH_Z1, z)), pt)


H = 3.1
b = Body([(0, 1.2), (0.12, 1.48), (0.5, 1.66), (1.1, 1.66), (1.8, 1.45), (2.45, 1.02), (2.9, 0.47), (H, 0)],
         paint=paint, bump=bump, segs=56, sub=4, gloss=0.25)
parts = [b.obj]


def tuft_cone(name, base, d, L, r, c0=FUR, c1=FUR):
    d = Vector(d).normalized()
    return lathe(name, [(0, r), (L * 0.45, r * 0.8), (L, 0)], along(c0, c1, base, Vector(base) + d * L),
                 pos=tuple(base), axis=tuple(d), segs=6, smooth=True)


# ---- fur tufts: a shaggy crown and fluffy cheek tufts sticking out sideways
for k, (x, y, dx, dy, L) in enumerate(((0, 0.05, 0, 0.1, 0.75), (-0.32, 0.1, -0.5, 0.15, 0.6), (0.32, 0.1, 0.5, 0.15, 0.6),
                                       (-0.15, 0.4, -0.2, 0.6, 0.55), (0.15, 0.4, 0.2, 0.6, 0.55))):
    base = Vector((x, y, H - 0.32))
    parts.append(tuft_cone(f"Crown{k}", base, (dx, dy, 1), L, 0.26, FUR_B, FUR))
for sd in (-1, 1):
    for k, (yaw, z, dz, L) in enumerate(((68, 1.25, -0.35, 0.7), (78, 1.62, -0.1, 0.62), (72, 0.9, -0.6, 0.55))):
        a = math.radians(sd * yaw)
        base = b.point(a, z, -0.18)
        out = Vector((math.sin(a), -math.cos(a) * 0.4, dz))
        parts.append(tuft_cone(f"Cheek{sd}{k}", base, out, L, 0.24, FUR_B, FUR))


# ---- curled ice horns: tapered tubes along a ram curl from the sides of the head
def curl_pts(sd, n=11):
    """ram curl: from the head side up, over and out, then down and round to the front."""
    root = b.point(math.radians(sd * 62), 2.42, -0.12)
    U = Vector((sd, -0.15, 0)).normalized()
    Z = Vector((0, 0, 1))
    C = root + U * 0.5 + Z * 0.08
    pts = []
    for k in range(n):
        t = k / (n - 1)
        th = math.radians(190 - 330 * t)
        R = 0.52 * (1 - 0.5 * t)
        pts.append(tuple(C + (U * math.cos(th) + Z * math.sin(th)) * R + Vector((0, -0.38 * t, 0))))
    return pts


for sd in (-1, 1):
    pts = curl_pts(sd)
    radii = [0.34 * (1 - 0.8 * k / (len(pts) - 1)) + 0.02 for k in range(len(pts))]
    parts.append(horn(f"Horn{sd}", pts, radii, ICE_D, ICE_L, segs=7, smooth=False))

# ---- ice crystal spikes down the back
for k, (yaw, z, L, r, tilt) in enumerate(((180, 2.55, 1.05, 0.2, 0.35), (180, 1.85, 1.0, 0.2, 0.15), (180, 1.15, 0.8, 0.17, 0.0),
                                          (150, 2.2, 0.7, 0.15, 0.3), (-150, 2.2, 0.7, 0.15, 0.3), (145, 1.45, 0.6, 0.14, 0.1),
                                          (-145, 1.45, 0.6, 0.14, 0.1))):
    a = math.radians(yaw)
    base = b.point(a, z, -0.15)
    nrm = Vector((math.sin(a), -math.cos(a), 0))
    d = (nrm + Vector((0, 0, 0.55 + tilt))).normalized()
    parts.append(crystal(f"Spike{k}", tuple(base), tuple(d), L, r, ICE_D, ICE_L, segs=6))

# ---- face on the dark patch: happy squeezed eyes, wide roar with fangs
f = Face(b, eye_v=EV, eye_u=0.46, mouth_v=1.28)
for sd in (-1, 1):
    u = sd * 0.46
    f.d(f"Eye{sd}", arc(u, EV - 0.08, 0.2, 18, 162, 0.11), ICE_L, off=0.02)
    f.d(f"Brow{sd}", rect(u + sd * 0.05, EV + 0.32, 0.36, 0.09, math.radians(-14 * sd)), hexc("9fd4ff"), off=0.02)
mw, mh, mv = 0.92, 0.5, 1.36
f.d("Mouth", half_oval(0, mv, mw, mh, n=16), ROAR, off=0.02, th=0.03)
f.d("Tongue", oval(0, mv - mh * 0.72, 0.42, 0.18, n=12), TONGUE_C, off=0.045, th=0.012)
for sd in (-1, 1):
    x = sd * 0.25
    f.d(f"Fang{sd}", [(x - 0.09, mv - 0.005), (x + 0.09, mv - 0.005), (x + sd * 0.01, mv - 0.24)], WHITE, off=0.05, th=0.02)
    x2 = sd * 0.12
    f.d(f"FangLo{sd}", [(x2 - 0.06, mv - mh * 0.86), (x2 + 0.06, mv - mh * 0.86), (x2, mv - mh * 0.62)], WHITE, off=0.05, th=0.02)
f.d("Nose", oval(0, EV - 0.2, 0.26, 0.15, n=12), hexc("10204e"), off=0.02, th=0.03)
f.d("NoseHi", oval(-0.04, EV - 0.17, 0.08, 0.05, n=8), hexc("8fb0ff"), off=0.055, th=0.008)
f.cheeks(color=hexc("8fb6ff"), w=0.24, h=0.12, u=0.78, v=EV - 0.3)
parts += f.parts


# ---- snowflakes floating round it: six-armed flakes (star arms + a ring of nubs)
def flake_poly(r):
    pts = []
    for k in range(6):
        a = k * math.tau / 6
        for da, rr in ((-0.3, r * 0.32), (-0.1, r * 0.95), (0.0, r * 1.05), (0.1, r * 0.95), (0.3, r * 0.32)):
            pts.append((math.cos(a + da) * rr, math.sin(a + da) * rr))
    return pts


for k in range(5):
    a = k * math.tau / 5 + 0.31
    R = 2.25 + 0.12 * math.sin(k * 1.9)
    p = Vector((math.cos(a) * R, math.sin(a) * R * 0.85, 1.4 + 0.75 * math.sin(a * 2 + 1.0)))
    face_d = Vector((-math.cos(a), -math.sin(a), 0.3)).normalized()
    xa = Vector((0, 0, 1)).cross(face_d).normalized()
    ya = face_d.cross(xa).normalized()
    r = 0.42 + 0.06 * math.cos(k * 2.2)
    parts.append(slab(f"Flake{k}", flake_poly(r), 0.08, tuple(p), tuple(xa), tuple(ya), lambda q, n: ICE_L))

ship("slime_yeti", parts)
