# Eclipse (Secret): a void slime that IS the eclipse. Black-violet body full of tiny stars with a
# hot pink rim glow, a burning corona ring standing behind it, glowing eyes and a glowing fanged
# grin, and four little planets orbiting on a tilted path.
from models._slimepool import *

VOID, VOID_M = hexc("0c0620"), hexc("23104a")
RIM, RIM_H = hexc("ff3fb4"), hexc("ffb3f0")
COR_D, COR, COR_L = hexc("ff2d6f"), hexc("ff9a3c"), hexc("fff2b0")
EYE = hexc("ffe6fb")


def paint(a, z, p):
    ad = abs(math.degrees(a))
    c = mix(VOID, VOID_M, smoothstep(0.3, 2.4, z))
    side = smoothstep(62, 92, ad) * smoothstep(135, 105, ad)  
    side *= smoothstep(2.75, 2.2, z)  # rim light on the silhouette as seen from the front
    c = mix(c, RIM, 0.9 * side)
    c = mix(c, RIM_H, 0.45 * smoothstep(80, 95, ad) * smoothstep(110, 95, ad))
    c = mix(c, RIM, 0.8 * smoothstep(0.35, 0.0, z))  # glowing foot
    return c


b = Body([(0, 1.0), (0.14, 1.34), (0.55, 1.55), (1.25, 1.56), (1.95, 1.34), (2.45, 1.0), (2.8, 0.55), (2.96, 0.2), (3.0, 0)],
         paint=paint, gloss=0.55, shade=0.6)
parts = [b.obj]
H = b.H

# corona: a burning ring behind the body with flame tongues
C = Vector((0, 0.75, 1.9))
R = 1.82
parts.append(torus("Ring", R, 0.13, C, (0, -1, 0), lambda p, n: mix(COR, COR_L, 0.5 + 0.5 * n.y * -1), segs=40, rsegs=6))
parts.append(torus("RingIn", R - 0.2, 0.06, C + Vector((0, 0.05, 0)), (0, -1, 0), COR_D, segs=40, rsegs=5))
NF = 22
for k in range(NF):
    a = k * math.tau / NF + 0.1
    if 235 < math.degrees(a) % 360 < 305:
        continue  # no flames into the ground
    big = k % 2 == 0
    L = (0.62 if big else 0.4) * (1 + 0.15 * math.sin(k * 2.1))
    w = 0.2 if big else 0.14
    radial = Vector((math.cos(a), 0, math.sin(a)))
    tang = Vector((-math.sin(a), 0, math.cos(a)))
    base = C + radial * (R - 0.02)
    flame = [(-w, 0), (w, 0), (w * 0.6, L * 0.45), (w * 0.15 + 0.08, L), (-w * 0.3, L * 0.5)]
    parts.append(slab(f"Flame{k}", flame, 0.07, base, tang, radial,
                      along(COR_D, COR_L, base, base + radial * L)))

# orbiting planets on a tilted ellipse (with a tiny trail)
OC = Vector((0, 0, 1.45))
tilt = math.radians(18)


def orbit(t):
    x, y = math.cos(t) * 2.2, math.sin(t) * 1.7
    return OC + Vector((x, y * math.cos(tilt), y * math.sin(tilt) + x * 0.12))


for k, (t, r, c) in enumerate([(math.radians(205), 0.25, hexc("57e8ff")), (math.radians(330), 0.2, hexc("ffd84a")),
                               (math.radians(80), 0.22, hexc("b06bff")), (math.radians(140), 0.17, hexc("ff6fa8"))]):
    p = orbit(t)
    parts.append(ball(f"Orb{k}", r, p, lambda q, n, c=c, p=p, r=r: mix(c, WHITE, 0.55 * max(0.0, n.dot(Vector((-0.4, -0.6, 0.7)).normalized())))))
    for j in (1, 2):
        parts.append(ball(f"Trail{k}{j}", r * (0.55 - 0.18 * j), orbit(t - 0.17 * j - 0.03), mix(c, WHITE, 0.3), subdiv=1))
# ring around one planet
parts.append(torus("OrbRing", 0.36, 0.035, orbit(math.radians(205)), (0.3, -0.3, 1), hexc("c9fbff"), segs=18, rsegs=4))

# stars in the void (avoid the face area)
stars = [(25, 0.55, 0.08), (-30, 0.7, 0.06), (45, 2.2, 0.07), (-48, 2.05, 0.09), (150, 1.2, 0.1), (190, 1.9, 0.08),
         (165, 0.6, 0.07), (215, 1.0, 0.09), (120, 2.4, 0.06), (-120, 2.35, 0.07), (0, 2.5, 0.08), (12, 2.15, 0.05)]
for k, (yaw, z, s) in enumerate(stars):
    parts.append(decal(f"Star{k}", star(0, 0, s, s * 0.35, n=4), WHITE, frame_at(yaw, z), off=0.012, th=0.012, on=["Body"]))

f = Face(b, eye_u=0.5, eye_v=1.5, mouth_v=1.0, mouth_col=RIM)
f.eyes("glow", w=0.55, h=0.66, color=EYE)
for sd in (-1, 1):
    f.d(f"EyeRim{sd}", [(x, y) for x, y in oval(sd * 0.5, 1.5, 0.62, 0.62, n=16)], RIM, off=0.012, th=0.01)
f.mouth("fangs", w=1.05)
parts += f.parts
ship("slime_eclipse", parts)
