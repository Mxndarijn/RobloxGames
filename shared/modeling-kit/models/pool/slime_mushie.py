# Mushie (Uncommon): shy mushroom slime. Squat cream body hiding under a big glossy red cap with
# white spots, worried eyes and a huge blush.
from models._slimepool import *

CREAM, CREAM_D = hexc("fff1d6"), hexc("f0c89a")
RED, RED_D, RED_L = hexc("f0303c"), hexc("b8162a"), hexc("ff6a5c")
GILL, GILL_D = hexc("ffd9c4"), hexc("e8a890")
SPOT = hexc("fffaf0")


def paint(a, z, p):
    return mix(CREAM_D, CREAM, smoothstep(0.0, 1.0, z))


b = Body([(0, 1.12), (0.12, 1.38), (0.5, 1.48), (1.1, 1.42), (1.7, 1.22), (2.2, 0.85), (2.5, 0.35), (2.58, 0)],
         paint=paint, segs=36, sub=2, gloss=0.6)
parts = [b.obj]

# cap: wide dome with a rolled rim, pale gills underneath
CAP_Z = 1.95


def cap_col(p, n):
    if n.z < -0.25 and p.z < CAP_Z + 0.35:
        r = math.hypot(p.x, p.y)
        return mix(GILL_D, GILL, smoothstep(0.4, 1.8, r))
    top = mix(RED_D, RED, smoothstep(CAP_Z + 0.1, CAP_Z + 0.8, p.z))
    d = (p - Vector((0, 0, CAP_Z + 0.4))).normalized()
    h = max(0.0, d.dot(Vector((-0.45, -0.55, 0.7)).normalized()))
    return mix(top, RED_L, 0.8 * smoothstep(0.86, 0.97, h))


cap = lathe("Cap", [(CAP_Z + 0.12, 0.0), (CAP_Z + 0.1, 0.9), (CAP_Z - 0.02, 1.7), (CAP_Z + 0.06, 2.0), (CAP_Z + 0.3, 2.08),
                    (CAP_Z + 0.75, 1.88), (CAP_Z + 1.15, 1.4), (CAP_Z + 1.4, 0.75), (CAP_Z + 1.5, 0.0)],
            cap_col, segs=32, sub=2)
register(cap)
parts.append(cap)
for k, (yaw, z, tilt, w) in enumerate(((0, 3.0, 55, 0.55), (-55, 2.8, 30, 0.42), (60, 2.85, 35, 0.45), (180, 3.0, 50, 0.6),
                                       (120, 2.6, 15, 0.4), (-125, 2.65, 18, 0.44), (0, 3.4, 88, 0.42), (-25, 2.4, 6, 0.3), (28, 2.42, 6, 0.28))):
    parts.append(decal(f"CapSpot{k}", oval(0, 0, w, w * 0.9, n=12), SPOT, frame_at(yaw, z, tilt), off=0.01, th=0.03, on=["Cap"]))

f = Face(b, eye_v=1.22, mouth_v=0.78)
f.eyes("round", w=0.46, h=0.62, look=(0.05, -0.02)).mouth("wobbly", w=0.62).cheeks(w=0.5, h=0.24, color=hexc("ff8aa8"))
for sd in (-1, 1):  # worried brows: inner ends UP (local: the kit's "worried" brows tilt the other way)
    f.d(f"Brow{sd}", rect(sd * f.eu + 0.03, f.ev + 0.42, 0.28, 0.065, math.radians(-20 * sd)), INK)
f.tear(1, color=hexc("9fdcff"))
parts += f.parts
ship("slime_mushie", parts)
