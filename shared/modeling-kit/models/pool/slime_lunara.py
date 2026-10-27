# Lunara (Celestial): a moon spirit slime. Pale silver-lavender body that glows white at the crown,
# soft crater freckles on the sides and back, two glowing crescent-moon horns, a small cratered moon
# orbiting on a tilted silver ring, a soft lavender aura halo behind the head, floating star
# sparkles, and a calm sleepy smile.
from models._slimepool import *
import random

LAV_D, LAV, SILVER, GLOW = hexc("7a68d8"), hexc("a898f2"), hexc("d8d0ff"), hexc("f4f0ff")
CRATER, CRATER_RIM = hexc("8574d6"), hexc("f4f1ff")
HORN_D, HORN, HORN_L = hexc("ffb52e"), hexc("ffe070"), hexc("fff8d0")
MOON_D, MOON, MOON_L = hexc("d9cfa8"), hexc("fff4c8"), hexc("fffdf0")
RING_C, RING_L = hexc("cfc8ff"), hexc("ffffff")
AURA_D, AURA_L = hexc("8a6cff"), hexc("e4d8ff")
STAR_Y, STAR_W = hexc("fff2a0"), hexc("ffffff")
INKL = hexc("3a2c6a")

# crater freckles (yaw deg, z, radius) painted soft into the body, off the face
CRATERS = [(70, 1.05, 0.26), (95, 1.85, 0.2), (-75, 1.2, 0.22), (-100, 2.0, 0.17), (140, 1.0, 0.3), (165, 2.0, 0.22),
           (-150, 1.5, 0.28), (-175, 0.75, 0.2), (120, 2.5, 0.16), (-125, 2.55, 0.15), (40, 2.55, 0.13), (-38, 2.62, 0.11),
           (55, 0.5, 0.15), (-55, 0.55, 0.14), (180, 2.6, 0.13), (62, 1.55, 0.1), (-60, 1.75, 0.09), (22, 2.35, 0.08)]


def body_pt(yaw, z):
    a = math.radians(yaw)
    return Vector((math.sin(a), -math.cos(a), 0)), z


def paint(a, z, p):
    c = mix(LAV_D, LAV, smoothstep(0.0, 1.0, z))
    c = mix(c, SILVER, smoothstep(1.0, 2.2, z))
    c = mix(c, GLOW, smoothstep(2.3, 2.95, z))
    for yaw, cz, r in CRATERS:
        ca = math.radians(yaw)
        da = math.atan2(math.sin(a - ca), math.cos(a - ca)) * 1.45  # yaw diff in studs (radius ~1.45)
        d = math.hypot(da, z - cz) / r
        if d < 1.35:
            c = mix(c, CRATER, 0.9 * smoothstep(1.0, 0.55, d))
            c = mix(c, CRATER_RIM, 0.55 * smoothstep(0.85, 1.0, d) * smoothstep(1.3, 1.05, d))
    c = mix(c, AURA_L, 0.7 * smoothstep(0.35, 0.0, z))  # glowing foot
    return c


b = Body([(0, 1.05), (0.14, 1.36), (0.55, 1.54), (1.2, 1.54), (1.85, 1.32), (2.4, 0.95), (2.8, 0.48), (3.0, 0)],
         paint=paint, segs=44, sub=3, gloss=0.7, shade=0.55)
parts = [b.obj]
H = b.H


def crescent(rc, a0, a1, W, n=16, tip=0.02):
    """crescent moon: thick arc with tapered tips, centre radius rc, from a0 to a1 deg, max width W."""
    outer, inner = [], []
    for k in range(n + 1):
        s = k / n
        a = math.radians(a0 + (a1 - a0) * s)
        w = tip + (W - tip) * math.sin(math.pi * s) ** 0.8
        outer.append((math.cos(a) * (rc + w * 0.65), math.sin(a) * (rc + w * 0.65)))
        inner.append((math.cos(a) * (rc - w * 0.35), math.sin(a) * (rc - w * 0.35)))
    return outer + list(reversed(inner))


# ---- two crescent horns on the head, curling up and outwards
for sd in (-1, 1):
    root = b.point(math.radians(sd * 36), 2.5, -0.15)
    yaw = math.radians(sd * 22)
    X = Vector((math.cos(yaw), math.sin(yaw), 0))
    Y = Vector((0, 0, 1))
    # arc centred above the root: out sideways, then curling up to the tip (a crescent moon)
    poly = crescent(0.78, -100, 60, 0.46)
    poly = [(sd * x, y + 0.78) for x, y in poly]
    if sd < 0:
        poly = list(reversed(poly))
    P = root
    parts.append(puffy_slab(f"Horn{sd}", poly, 0.26, P, X, Y,
                            lambda p, n, P=P: mix(HORN_D, HORN_L, smoothstep(0.0, 1.2, (p - P).z + 0.2 * (1 - abs(n.y)))), rows=3))

# ---- aura halo: a soft glowing ring standing behind the head, tilted towards the face
AC = Vector((0, 0.55, 1.75))
an = Vector((0, -1, 0.18)).normalized()
parts.append(torus("Aura", 1.95, 0.13, AC, an, lambda p, n: mix(AURA_D, AURA_L, 0.5 + 0.5 * n.z), segs=44, rsegs=6))
parts.append(torus("AuraIn", 1.7, 0.04, AC + Vector((0, 0.03, 0)), an, AURA_L, segs=40, rsegs=4))
aq = an.to_track_quat("Z", "Y")
for k in range(12):  # little star beads on the aura
    a = k * math.tau / 12 + math.pi / 12
    if 230 < math.degrees(a) % 360 < 310:
        continue
    p = AC + aq @ Vector((math.cos(a) * 1.95, math.sin(a) * 1.95, 0)) + an * 0.04
    r = 0.32 if k % 2 == 0 else 0.2
    rad = (p - AC).normalized()
    tng = an.cross(rad)
    parts.append(puffy_slab(f"AuraStar{k}", star(0, 0, r, r * 0.38, n=4, rot=0), 0.08, p + an * 0.12, tng, rad,
                            STAR_Y if k % 2 == 0 else STAR_W, rows=2))

# ---- tilted orbit ring with the little moon
OC = Vector((0, 0, 1.25))
on_ = Vector((0.22, -0.42, 1)).normalized()
OR = 2.25
oq = on_.to_track_quat("Z", "Y")


def orbit(t):
    return OC + oq @ Vector((math.cos(t) * OR, math.sin(t) * OR, 0))


parts.append(torus("Orbit", OR, 0.045, OC, on_, lambda p, n: mix(RING_C, RING_L, 0.5 + 0.5 * n.z), segs=56, rsegs=4))
MT = math.radians(-35)
MC = orbit(MT)
key = Vector((-0.45, -0.6, 0.65)).normalized()
parts.append(register(ball("Moon", 0.48, MC, lambda p, n: mix(MOON_D, MOON_L, smoothstep(-0.6, 0.9, n.dot(key))), subdiv=3)))
mf = frame_at(0, 0, cy=MC.y)
for j, (du, dv, w) in enumerate(((-0.22, 0.24, 0.12), (0.26, 0.22, 0.09), (0.3, -0.2, 0.08), (-0.3, -0.12, 0.07))):
    parts.append(decal(f"MoonCrater{j}", oval(MC.x + du, MC.z + dv, w, w, n=10), MOON_D, mf, off=0.006, th=0.01, on=["Moon"], step=0))
for sd in (-1, 1):  # the little moon dozes too
    parts.append(decal(f"MoonEye{sd}", arc(MC.x + sd * 0.13, MC.z + 0.04, 0.065, 200, 340, 0.04, n=6), INKL, mf, off=0.012, th=0.01, on=["Moon"], step=0))
    parts.append(decal(f"MoonCheek{sd}", oval(MC.x + sd * 0.22, MC.z - 0.07, 0.09, 0.05, n=8), hexc("ffb0d8"), mf, off=0.01, th=0.008, on=["Moon"], step=0))
parts.append(decal("MoonMouth", arc(MC.x, MC.z - 0.06, 0.045, 200, 340, 0.03, n=5), hexc("7a3a7a"), mf, off=0.012, th=0.01, on=["Moon"], step=0))
# dotted sparkle trail behind the moon on the ring
for j in range(1, 5):
    parts.append(ball(f"MoonTrail{j}", 0.075 - 0.012 * j, orbit(MT + 0.28 * j), mix(MOON_L, AURA_D, j / 5), subdiv=1))

# ---- floating sparkles
for j, (pos, r, rot, c) in enumerate((((-1.55, -0.6, 3.15), 0.24, 0, STAR_Y), ((1.75, -0.35, 2.85), 0.17, 15, STAR_W),
                                      ((-2.1, 0.1, 0.55), 0.15, 10, STAR_W), ((2.3, -0.6, 0.85), 0.13, 0, STAR_Y),
                                      ((0.95, -0.9, 3.5), 0.12, 30, STAR_W))):
    parts.append(puffy_slab(f"Spark{j}", star(0, 0, r, r * 0.3, n=4, rot=rot), 0.07, pos, (1, 0, 0), (0, 0, 1), c, rows=2))

# ---- tiny star specks on the body (back and sides)
rng = random.Random(11)
k = 0
for i in range(30):
    yaw = rng.uniform(-180, 180)
    z = rng.uniform(0.45, 2.7)
    if abs(yaw) < 58 and 0.7 < z < 2.3:
        continue
    r = rng.uniform(0.05, 0.1)
    shape = star(0, 0, r, r * 0.32, n=4) if r > 0.075 else oval(0, 0, r, r, n=6)
    parts.append(decal(f"Speck{k}", shape, STAR_W if rng.random() < 0.6 else STAR_Y, frame_at(yaw, z), off=0.01, th=0.012, on=["Body"], step=0))
    k += 1

# ---- little crescent jewel on the forehead
fc = crescent(0.17, 110, 330, 0.12, n=12)
parts.append(decal("BrowMoon", [(x, y + 2.33) for x, y in fc], HORN, FRONT, off=0.015, th=0.03, on=["Body"], step=0.05))

# ---- calm sleepy smile
f = Face(b, eye_u=0.52, eye_v=1.6, mouth_v=1.2, s=1.1, ink=INKL, mouth_col=hexc("7a3a7a"))
f.eyes("sleepy")
f.mouth("smile", w=1.1)
f.cheeks(color=hexc("ff9fd6"), w=0.32, h=0.15)
parts += f.parts

ship("slime_lunara", parts)
