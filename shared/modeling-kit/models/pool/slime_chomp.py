# Chomp (Rare): battle-scarred shark slime. Countershaded goo (white belly sweeping up into the
# grin), a tall swept dorsal fin with a bite out of it, crescent tail, scar over one eye.
from models._slimepool import *

BLUE, BLUE_D, BLUE_L, BELLY = hexc("2f86f2"), hexc("1a4fb0"), hexc("63b4ff"), hexc("f4f9ff")
SCAR = hexc("ff7a9c")


def belly_z(a):
    # belly line: high under the face, sweeping down along the flanks
    return 0.35 + 1.05 * max(0.0, math.cos(a * 0.9)) ** 1.4


def paint(a, z, p):
    top = mix(BLUE, BLUE_D, smoothstep(1.4, 2.9, z))
    f = smoothstep(belly_z(a) + 0.15, belly_z(a) - 0.15, z)
    return mix(top, BELLY, f)


b = Body([(0, 1.12), (0.15, 1.4), (0.5, 1.55), (1.1, 1.47), (1.8, 1.16), (2.4, 0.7), (2.75, 0.25), (2.86, 0)],
         paint=paint, gloss=0.45, sy=1.08, segs=48, sub=4, lean=lambda z: 0.12 * max(0.0, (z - 1.6) / 1.26) ** 2)
parts = [b.obj]

# dorsal fin: tall, swept back, with a bite notch on the trailing edge
fin = [(-0.62, 0), (0.55, 0), (0.62, 0.3), (0.72, 0.42), (0.6, 0.55), (0.62, 0.78), (0.78, 1.2),
       (0.55, 1.15), (0.1, 0.85), (-0.3, 0.45)]
parts.append(puffy_slab("Fin", fin, 0.34, (0, 0.28, 2.42), (0, 1, 0), (0, 0, 1), zgrad(BLUE_D, hexc("2f6fd8"), 2.5, 3.7)))
# crescent tail fin standing up behind
tail = [(0, -0.3), (0.55, -0.55), (0.95, -0.85), (0.72, -0.3), (0.6, 0), (0.85, 0.55), (1.05, 1.05),
        (0.55, 0.6), (0, 0.32)]
parts.append(puffy_slab("Tail", tail, 0.22, (0, 1.3, 0.62), (0, 1, 0.25), (0, -0.25, 1), BLUE_D))
for sd in (-1, 1):
    pec = [(0, -0.22), (0.55, -0.4), (0.95, -0.6), (0.55, -0.05), (0.15, 0.22)]
    parts.append(puffy_slab(f"Pec{sd}", pec, 0.16, (sd * 1.42, -0.15, 0.55), (sd, 0.25, -0.4), (0, 1, 0), BLUE_D))
    for k in range(3):
        parts.append(decal(f"Gill{sd}{k}", arc(0, 0, 0.24, 62, 118, 0.06, n=5), BLUE_D,
                           frame_at(sd * (68 + k * 10), 1.38), on=["Body"]))

f = Face(b, eye_v=1.78, mouth_v=1.15, eye_u=0.52)
f.eyes("angry", w=0.48, h=0.62, iris=hexc("8fdcff"))
f.brows("angry", w=0.36, th=0.085, lift=-0.04)
f.mouth("shark", w=1.35)
# battle scar slashing over the viewer-left eye, with stitches
su, sv = -0.66, 1.8
f.d("Scar", rect(su + 0.03, sv, 0.1, 1.0, math.radians(-18)), SCAR, off=0.008, th=0.006)
for k, dv in enumerate((-0.36, 0.0, 0.36)):
    f.d(f"Stitch{k}", rect(su + 0.03 + math.tan(math.radians(18)) * dv, sv + dv, 0.22, 0.055, math.radians(-18)), SCAR, off=0.009, th=0.005)
parts += f.parts
ship("slime_chomp", parts)
