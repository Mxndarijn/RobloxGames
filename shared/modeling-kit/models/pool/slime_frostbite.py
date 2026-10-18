# Frostbite (Epic): ice slime. Pale icy blue, snow-frosted top, icicle crown, snowflake cheeks, icy shades, cool smirk.
from models._slimepool import *

ICE, ICE_D, ICE_L, SNOW = hexc("6cc8ff"), hexc("2f8ee0"), hexc("b4e8ff"), hexc("ffffff")
CRY0, CRY1 = hexc("1f86e8"), hexc("bff2ff")


def snowline(a):
    return 2.0 + 0.12 * math.sin(a * 5) + 0.06 * math.sin(a * 9 + 1)


def body_paint(a, z, p):
    c = mix(ICE_D, ICE, smoothstep(0.0, 1.2, z))
    c = mix(c, ICE_L, smoothstep(1.2, 1.9, z))
    return mix(c, SNOW, smoothstep(snowline(a) - 0.04, snowline(a) + 0.04, z))


b = Body([(0, 1.1), (0.15, 1.4), (0.5, 1.52), (1.2, 1.46), (1.9, 1.18), (2.45, 0.78), (2.8, 0.3), (2.9, 0)],
         paint=body_paint, bump=lambda a, z: 0.045 * math.cos(4 * a) * smoothstep(0.0, 0.4, z))
parts = [b.obj]

# icicle crown: ring of crystals on top, tallest at the front-centre
for k in range(7):
    a = math.radians(-90 + k * 30)
    r = 0.62
    z = 2.58
    tall = 1.35 - 0.5 * abs(k - 3) / 3
    base = (math.sin(a) * r, -math.cos(a) * r * 0.6 + 0.1, z)
    d = (math.sin(a) * 0.45, -math.cos(a) * 0.2, 1)
    parts.append(crystal(f"Crown{k}", base, d, tall, 0.17 + 0.04 * (k == 3), CRY0, CRY1))
for k in range(5):  # back row
    a = math.radians(140 + k * 20)
    base = (math.sin(a) * 0.5, -math.cos(a) * 0.45, 2.6)
    parts.append(crystal(f"CrownB{k}", base, (math.sin(a) * 0.3, -math.cos(a) * 0.2, 1), 0.8, 0.14, CRY0, CRY1))

# icicles hanging off the snow edge
for k, yaw in enumerate(range(28, 360, 38)):
    a = math.radians(yaw)
    z = snowline(a)
    p = b.point(a, z - 0.04, 0.02)
    L = 0.5 + 0.3 * ((k * 7) % 3) / 2
    parts.append(lathe(f"Icicle{k}", [(0, 0.15), (L, 0)], along(ICE_L, hexc("3aa8ff"), p, p - Vector((0, 0, L))),
                       pos=p, axis=(0, 0, -1), segs=5, smooth=False))

f = Face(b, eye_v=1.42, mouth_v=0.95, s=1.12)
f.eyes("shades", color=hexc("1f4fb8")).mouth("smirk", w=1.35, color=hexc("1c3a7a"))
parts += f.parts
for sd in (-1, 1):  # snowflake cheeks
    u, v = sd * 0.92, 1.05
    for j in range(3):
        parts.append(decal(f"Flake{sd}{j}", rect(u, v, 0.36, 0.06, math.radians(j * 60)), SNOW, off=0.02 + j * 0.01, th=0.012, on=["Body"]))
    parts.append(decal(f"FlakeC{sd}", oval(u, v, 0.1, 0.1, n=6), SNOW, off=0.05, th=0.01, on=["Body"]))
ship("slime_frostbite", parts)
