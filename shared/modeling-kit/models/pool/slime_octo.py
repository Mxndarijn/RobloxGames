# Octo (Epic): octopus slime. Purple-pink bulb head, 6 curly tentacles with suckers, big round eyes, 'o' mouth.
from models._slimepool import *

PUR, PUR_D, PINK, PINK_L = hexc("b04ad8"), hexc("6e2aa0"), hexc("ff7ad0"), hexc("ffc8ec")


def body_paint(a, z, p):
    return mix(mix(PUR_D, PUR, smoothstep(0.0, 1.0, z)), PINK, smoothstep(1.4, 3.2, z))


b = Body([(0, 1.0), (0.2, 1.15), (0.6, 1.25), (1.3, 1.5), (2.1, 1.52), (2.8, 1.2), (3.25, 0.6), (3.42, 0)],
         paint=body_paint)
parts = [b.obj]

def tentacle_path():
    """(r, z, radius): along the ground, then a spiral curling up and outward at the tip."""
    out = [(0.85, 0.3, 0.38), (1.2, 0.24, 0.31), (1.55, 0.2, 0.25), (1.85, 0.2, 0.21)]
    cr, R0, R1 = 2.05, 0.42, 0.13
    cz = 0.2 + R0 - 0.02
    n = 13
    for i in range(1, n + 1):
        t = i / n
        ang = -math.pi / 2 + t * math.tau * 0.95
        R = R0 + (R1 - R0) * t
        out.append((cr + R * math.cos(ang), cz + R * math.sin(ang), 0.19 - 0.14 * t ** 0.8))
    return out


TP = tentacle_path()
for k, yaw in enumerate((35, 90, 145, 215, 270, 325)):
    a = math.radians(yaw + (6 if k % 2 else -6))
    pts = [(math.sin(a) * r, -math.cos(a) * r, z) for r, z, _ in TP]
    parts.append(horn(f"Tent{k}", pts, [w for _, _, w in TP], PUR_D, PINK, segs=8))
    for j, (r, z) in enumerate(((1.2, 0.52), (1.55, 0.44), (1.85, 0.4))):
        parts.append(ball(f"Suck{k}{j}", 0.12 - 0.02 * j, (math.sin(a) * r, -math.cos(a) * r, z), PINK_L,
                          squash=(1, 1, 0.4), subdiv=1))

parts += spots(b, [(130, 2.4, 0.3), (165, 1.8, 0.22), (200, 2.6, 0.26), (230, 1.9, 0.2), (100, 2.9, 0.18), (260, 2.8, 0.18)],
               PINK_L)
f = Face(b, eye_v=1.85, mouth_v=1.22)
f.eyes("big", w=0.5, h=0.62).mouth("o", w=1.1).cheeks(color=hexc("ff9ad8"))
parts += f.parts
ship("slime_octo", parts)
