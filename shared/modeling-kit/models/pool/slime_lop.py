# Lop (Rare): sweet lop-eared bunny slime. Tall soft bean of white-pink goo, two long floppy goo
# ears draping down the sides (pink tips), big shiny eyes, buck teeth, cotton tail.
from models._slimepool import *

WH, PK, PK_D, PK_L = hexc("fff6fa"), hexc("ffb3cf"), hexc("f06e9e"), hexc("ffe0ec")
IRIS = hexc("c46bff")


def paint(a, z, p):
    return mix(PK, WH, smoothstep(0.2, 1.9, z))


b = Body([(0, 1.08), (0.15, 1.36), (0.55, 1.5), (1.25, 1.44), (2.0, 1.16), (2.6, 0.72), (2.98, 0.24), (3.08, 0)],
         paint=paint, sy=0.98, segs=44)
parts = [b.obj]


def ear(sd):
    # chain of flattened ellipsoids from the crown, arching up and out, then hanging down the side
    pts = [(0.42, 0.12, 2.9), (0.7, 0.14, 3.12), (1.02, 0.14, 3.08), (1.3, 0.12, 2.8), (1.48, 0.1, 2.4),
           (1.58, 0.06, 1.95), (1.6, 0.02, 1.5), (1.56, 0.0, 1.12)]
    rad = [0.3, 0.32, 0.34, 0.36, 0.38, 0.4, 0.4, 0.36]
    balls = []
    for i, ((x, y, z), r) in enumerate(zip(pts, rad)):
        flat = 0.42 if i >= 3 else 0.6
        sc = (flat, 1.0, 1.0) if i >= 3 else (1.0, 1.0, flat)
        balls.append(((sd * x, y, z), r, sc))
    col = lambda p, n: mix(mix(PK_L, hexc("ffcade"), smoothstep(2.6, 1.9, p.z)), PK, smoothstep(1.9, 1.15, p.z))
    return goo(f"Ear{'L' if sd < 0 else 'R'}", balls, col, tris=700, resolution=0.08)


for sd in (-1, 1):
    parts.append(ear(sd))
# cotton tail
parts.append(goo("Cotton", [((0, 1.45, 0.62), 0.42), ((0.15, 1.5, 0.75), 0.3), ((-0.14, 1.52, 0.72), 0.3),
                            ((0, 1.58, 0.5), 0.28)], WH, tris=300, resolution=0.08))

# little bow on the viewer-right ear root
BOW, BOW_D = hexc("ff5c9a"), hexc("d0306e")
bc = Vector((0.62, -0.16, 3.14))
for sd in (-1, 1):
    parts.append(puffy_slab(f"Bow{sd}", [(0.06, 0), (0.52, 0.27), (0.58, -0.02), (0.46, -0.28)], 0.16, bc,
                            (sd * 0.9, 0, sd * 0.25 + 0.15), (0.0, 0.25, 1), zgrad(BOW_D, BOW, 2.95, 3.3)))
parts.append(ball("BowKnot", 0.13, bc + Vector((0, -0.04, 0)), BOW))
f = Face(b, eye_v=1.62, mouth_v=1.05, eye_u=0.5)
f.eyes("sparkle", w=0.46, h=0.58, iris=IRIS, look=(0, 0.02))
f.nose(color=PK_D, w=0.2, h=0.12, v=1.28)
f.mouth("buck", w=1.15, v=1.1)
f.cheeks(color=hexc("ff8fb4"), w=0.34, h=0.17, u=0.92, v=1.22)
parts += f.parts
ship("slime_lop", parts)
