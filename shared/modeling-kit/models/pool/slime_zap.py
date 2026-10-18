# Zap (Epic): storm slime. Dark indigo, grey storm cloud on its head, yellow bolt markings, zigzag mouth, sparkle eyes.
from models._slimepool import *

IND, IND_D, IND_L = hexc("3a2c8c"), hexc("221a5c"), hexc("5a48c8")
BOLT, BOLT_L = hexc("ffe02a"), hexc("fff6a0")
CLOUD_D, CLOUD, CLOUD_L = hexc("3c3f56"), hexc("7a809c"), hexc("aeb4cc")


def body_paint(a, z, p):
    return mix(IND_D, IND_L, smoothstep(0.0, 2.2, z))


b = Body([(0, 1.25), (0.15, 1.55), (0.5, 1.68), (1.0, 1.62), (1.5, 1.38), (1.95, 0.95), (2.25, 0.4), (2.32, 0)],
         paint=body_paint)
parts = [b.obj]

# storm cloud: dark flat underside (goo lens) + distinct round puffs on top (separate balls keep the scalloped outline)
ccol = lambda p, n: mix(CLOUD_D, CLOUD_L, smoothstep(2.15, 3.2, p.z))
parts.append(goo("CloudBase", [((0, 0.08, 2.25), 0.8, (1.65, 1.2, 0.36)), ((-1.2, 0.1, 2.3), 0.38), ((1.25, 0.05, 2.3), 0.38)],
                 ccol, tris=350, resolution=0.09))
for k, (x, y, z, r) in enumerate([(-0.85, 0.0, 2.55, 0.55), (0.05, 0.1, 2.8, 0.7), (0.9, 0.05, 2.55, 0.55),
                                  (-0.4, -0.45, 2.55, 0.45), (0.45, -0.42, 2.55, 0.45), (-0.4, 0.6, 2.6, 0.5),
                                  (0.5, 0.6, 2.6, 0.48), (-1.35, 0.1, 2.38, 0.34), (1.4, 0.1, 2.38, 0.34)]):
    parts.append(ball(f"Puff{k}", r, (x, y, z), ccol, subdiv=3 if r > 0.5 else 2))

def bolt_poly(s=1.0):
    pts = [(-0.05, 0.5), (0.25, 0.5), (0.08, 0.1), (0.3, 0.1), (-0.15, -0.55), (0.0, -0.08), (-0.22, -0.08)]
    return [(x * s, y * s) for x, y in pts]


# 3D bolts dropping from the cloud on both sides
for sd in (-1, 1):
    poly = [(x * 1.3, y * 1.3) for x, y in bolt_poly()]
    parts.append(slab(f"Bolt{sd}", poly, 0.14, (sd * 1.7, 0.15, 1.95), (sd * 0.75, 0.66, 0), (0, 0, 1),
                      zgrad(BOLT, BOLT_L, 1.4, 2.6)))
# bolt markings on the body sides + back
for k, yaw in enumerate((75, -75, 180)):
    poly = bolt_poly(1.0)
    parts.append(decal(f"Mark{k}", poly, BOLT, frame_at(yaw, 1.0), off=0.015, on=["Body"]))

f = Face(b, eye_v=1.25, mouth_v=0.74)
for k, (x, y, z, r) in enumerate([(-1.75, -0.3, 3.1, 0.15), (1.8, -0.2, 3.25, 0.13), (-0.9, -0.4, 3.55, 0.11), (1.0, 0.2, 3.6, 0.1)]):
    parts.append(gem(f"Spark{k}", (x, y, z), r, BOLT, segs=4))
f.eyes("sparkle", iris=BOLT).mouth("zigzag", w=1.4, color=BOLT)
parts += f.parts
ship("slime_zap", parts)
