# Goo God (Divine tier jackpot): the biggest, grandest slime (about 1.3x the others). Luminous
# white-gold body (warm gold foot -> cream -> white crown) with gold trim, a radiant sunburst disc
# standing behind it, a floating halo tilted toward the face, a glowing third-eye gem, four tiny
# pastel mini-slimes orbiting it like moons, and a serene, powerful face with glowing eyes.
from models._slimepool import *
import re

GF, GM, CREAM, WHITE_W = hexc("ffb830"), hexc("ffe07a"), hexc("fff2c4"), hexc("fffdf4")
GD, G, GL, GW = hexc("c87400"), hexc("ffb81c"), hexc("ffe46a"), hexc("fff8d6")
EYE_RIM, EYE_IN, EYE_CORE = hexc("7a4006"), hexc("3ad8ff"), hexc("f4ffff")
SUN_IN, SUN_MID, SUN_OUT = hexc("fff6c8"), hexc("ffd040"), hexc("ff9a1a")
S = 1.3  # size vs a normal species


def paint(a, z, p):
    c = mix(GF, GM, smoothstep(0.0, 0.9, z))
    c = mix(c, CREAM, smoothstep(0.7, 1.9, z))
    return mix(c, WHITE_W, smoothstep(2.2, 3.5, z))


prof = [(0, 1.12), (0.14, 1.38), (0.55, 1.52), (1.25, 1.5), (1.95, 1.3), (2.5, 0.94), (2.85, 0.45), (3.0, 0)]
BANDS = [(0.26, 0.4, G)]
b = Body([(z * S, r * S) for z, r in prof], paint=paint, bands=BANDS, segs=48, sub=3, gloss=0.9, shade=0.7)
parts = [b.obj]
H = b.H

# ---------------------------------------------------------------- sunburst disc behind
C = Vector((0, 1.7 * S, 2.0 * S))
RD = 1.85 * S  # disc radius
parts.append(lathe("SunDisc", [(-0.06, 0), (-0.06, RD * 0.55), (-0.06, RD), (0.06, RD), (0.06, RD * 0.55), (0.06, 0)],
                   lambda p, n: mix(SUN_IN, SUN_MID, smoothstep(0.3 * RD, RD, (p - C).length)), pos=C, axis=(0, -1, 0), segs=40))
parts.append(torus("SunRim", RD, 0.11, C, (0, -1, 0), lambda p, n: mix(G, GL, 0.5 + 0.5 * n.z), segs=40, rsegs=5))
parts.append(torus("SunRing", RD * 0.72, 0.06, C + Vector((0, -0.07, 0)), (0, -1, 0), GL, segs=32, rsegs=4))
for k, rr in enumerate((0.72, 0.4)):  # the back of the disc gets rings and a sun core too
    parts.append(torus(f"SunBackRing{k}", RD * rr, 0.06, C + Vector((0, 0.07, 0)), (0, 1, 0), GL, segs=28, rsegs=4))
parts.append(lathe("SunBackCore", [(0, 0.5), (0.08, 0.45), (0.14, 0)], lambda p, n: mix(G, GW, 0.5), pos=C + Vector((0, 0.06, 0)), axis=(0, 1, 0), segs=20))
NR = 24
for k in range(NR):
    a = k * math.tau / NR + math.pi / 2
    deg = math.degrees(a) % 360
    if 245 < deg < 295:
        continue  # nothing into the ground
    big = k % 2 == 0
    L = (1.1 if big else 0.6) * S * (1 + 0.12 * math.cos(k * 1.7))
    w = (0.25 if big else 0.16) * S
    radial = Vector((math.cos(a), 0, math.sin(a)))
    tang = Vector((-math.sin(a), 0, math.cos(a)))
    base = C + radial * (RD - 0.05)
    if (base + radial * L).z < 0.6 or base.z - w < 0.3:
        continue  # rays never reach into the ground (the slime would float)
    ray = [(-w, 0), (w, 0), (0.0, L)]
    parts.append(slab(f"Ray{k}", ray, 0.08, base, tang, radial, along(SUN_MID if big else SUN_OUT, SUN_IN if big else GL, base, base + radial * L)))

# ---------------------------------------------------------------- floating halo, tilted toward the face
HC = Vector((0, 0.15, H + 0.55))
parts.append(torus("Halo", 0.82, 0.12, HC, (0, -0.32, 1), lambda p, n: mix(GL, GW, 0.4 + 0.6 * max(0.0, n.z)), segs=32, rsegs=6))

# ---------------------------------------------------------------- face: serene, powerful, glowing eyes
EV, EU = 2.2 * S, 0.62 * S
for sd in (-1, 1):
    u = sd * EU
    # calm almond eyes: flat-ish top lid, glowing core, amber rim
    rim = [(x, min(y, EV + 0.24 + (x - u) * 0.14 * -sd)) for x, y in oval(u, EV, 0.76, 0.58, n=20)]
    parts.append(decal(f"EyeRim{sd}", rim, EYE_RIM, FRONT, off=0.015, th=0.02, on=["Body"], step=0.08))
    glow = [(x, min(y, EV + 0.17 + (x - u) * 0.14 * -sd)) for x, y in oval(u, EV - 0.02, 0.66, 0.5, n=18)]
    parts.append(decal(f"Eye{sd}", glow, lambda p, n, u=u: mix(EYE_CORE, EYE_IN, smoothstep(0.08, 0.3, math.hypot(p.x - u, (p.z - EV) * 1.3))),
                       FRONT, off=0.035, th=0.012, on=["Body"], step=0.08))
    parts.append(decal(f"EyeHi{sd}", star(u - 0.1, EV + 0.02, 0.1, 0.035, n=4), WHITE, FRONT, off=0.05, th=0.01, on=["Body"]))
# third eye: a glowing gem on the forehead, in a gold setting
fp = b.point(0, 2.72 * S, 0.0)
parts.append(lathe("BrowSet", [(0, 0.2), (0.06, 0.21), (0.1, 0.0)], G, pos=tuple(fp), axis=(0, -1, 0.35), segs=12))
parts.append(gem("BrowGem", tuple(fp + Vector((0, -0.07, 0.02))), 0.15, hexc("4ae8ff"), axis=(0, -1, 0.35), h=0.18, segs=6))
# calm small smile
MV = 1.62 * S
parts.append(decal("Mouth", arc(0, MV + 0.24, 0.26, 215, 325, 0.075, n=10), hexc("a0480a"), FRONT, off=0.02, th=0.02, on=["Body"]))
for sd in (-1, 1):
    parts.append(decal(f"Cheek{sd}", oval(sd * (EU + 0.38), EV - 0.48, 0.34, 0.15, n=12), hexc("ffa86a"), FRONT, off=0.012, th=0.015, on=["Body"]))


# ---------------------------------------------------------------- mini-slime moons
MINIS = [(-2.75, -0.85, 2.7, hexc("ff7ac0"), hexc("ffd6ea")), (2.8, -0.6, 3.5, hexc("3ac8ff"), hexc("d0f4ff")),
         (2.6, -0.2, 0.9, hexc("7ae04a"), hexc("e0ffc8")), (-2.55, 0.5, 1.1, hexc("a07aff"), hexc("e6dcff"))]
for k, (x, y, z, c0, c1) in enumerate(MINIS):
    name = f"Mini{k}"
    mb = Body([(z * 1.3, r * 1.3) for z, r in [(0, 0.34), (0.08, 0.42), (0.3, 0.45), (0.55, 0.38), (0.75, 0.2), (0.82, 0)]],
              paint=lambda a, zz, p, c0=c0, c1=c1: mix(c0, c1, smoothstep(0.1, 0.8, zz)), segs=12, sub=1, gloss=0.8, name=name, tuck=0.15, dome=0.6)
    mf = Face(mb, eye_u=0.22, eye_v=0.58, mouth_v=0.4, s=0.55)
    mf.eyes("dot", w=0.5)
    mf.mouth("smile", w=1.1)
    group = [mb.obj] + mf.parts
    # face the god a little (turn toward -Y and toward the middle)
    yaw = math.atan2(-x, 2.0) * 0.6
    T = Matrix.Translation((x, y, z)) @ Matrix.Rotation(yaw, 4, "Z")
    for o in group:
        o.data.transform(T)
        o.name = o.name if o.name.startswith(name) else f"{name}{o.name}"
    parts += group
    # a short sparkle trail behind each moon
    for j in (1, 2):
        tp = Vector((x, y, z + 0.4)) + Vector((-math.copysign(0.42, x) * j * 0.8, 0.25 * j, -0.12 * j))
        parts.append(ball(f"Trail{k}{j}", 0.11 - 0.035 * j, tp, mix(c1, WHITE, 0.4), subdiv=1))

# twinkles
for k, (x, y, z, sz) in enumerate([(-1.7, -1.0, 4.9, 0.22), (1.6, -1.1, 4.6, 0.18), (-3.3, -0.4, 4.0, 0.16), (3.4, -0.3, 2.3, 0.15)]):
    parts.append(slab(f"Twinkle{k}", star(0, 0, sz, sz * 0.3, n=4), 0.05, (x, y, z), (0.9, 0.45 * (1 if x > 0 else -1), 0), (0, 0, 1), GW))

if os.environ.get("TRI_DBG"):
    import collections
    cnt = collections.Counter()
    for o in parts:
        cnt[re.sub(r"[-0-9]+$", "", o.name)] += sum(len(pl.vertices) - 2 for pl in o.data.polygons)
    print("TRIS", sorted(cnt.items(), key=lambda x: -x[1]))
ship("slime_goo_god", parts)
