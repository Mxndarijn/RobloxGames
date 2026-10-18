# Midas (Secret): the flex slime. Solid liquid gold with molten drips running down from the crown,
# gold-rimmed shades, a chunky gold chain with a ruby, a tiny tilted crown, a smug smirk, and a
# little pile of coins and a gold puddle at its feet.
from models._slimepool import *

G_D, G, G_L, G_W = hexc("c25a00"), hexc("ffa914"), hexc("ffe455"), hexc("fff8d0")
MOLTEN = hexc("fff06a")
RUBY, RUBY_L = hexc("e8173c"), hexc("ff8aa0")
INKB = hexc("2a1406")

# drips: (yaw deg, tip z, half-width deg)
DRIPS = [(-150, 0.85, 13), (-112, 1.25, 10), (-78, 0.7, 12), (-38, 1.55, 9), (28, 1.35, 9), (62, 0.8, 12),
         (100, 1.15, 10), (138, 0.6, 13), (175, 1.05, 11)]
COLLAR = 2.05


def angd(a, b):
    return (a - b + 180) % 360 - 180


def mask(a, z):
    """1 on the molten layer: everything above a wavy collar + drips hanging from it"""
    ad = math.degrees(a)
    collar = COLLAR + 0.08 * math.sin(a * 5 + 0.6)
    m = smoothstep(collar - 0.06, collar + 0.04, z)
    for yaw, tip, w in DRIPS:
        d = abs(angd(ad, yaw))
        # stem narrows a bit towards the tip, ends in a round fat drop
        wz = w * (0.75 + 0.25 * smoothstep(tip, collar, z))
        stem = smoothstep(wz, wz * 0.6, d) * smoothstep(tip + 0.12, tip + 0.22, z)
        drop = smoothstep(1.0, 0.75, math.hypot(d / (w * 1.15), (z - tip - 0.14) / 0.17))
        m = max(m, stem, drop)
    return m


def bump(a, z):
    ad = math.degrees(a)
    extra = 0.0
    for yaw, tip, w in DRIPS:  # the fat drop bulges out most
        d = abs(angd(ad, yaw))
        extra = max(extra, 0.05 * smoothstep(1.0, 0.4, math.hypot(d / (w * 1.15), (z - tip - 0.14) / 0.17)))
    return 0.07 * mask(a, z) + extra


def paint(a, z, p):
    # metal look: banded body (dark low, bright band, mid, bright crown) + brighter molten layer
    t = 0.5 + 0.5 * math.sin(z * 2.6 - 0.6)
    body = mix(G_D, G, smoothstep(0.0, 0.9, z))
    body = mix(body, G_L, 0.25 * t * smoothstep(0.3, 1.0, z))
    return mix(body, MOLTEN, mask(a, z))


b = Body([(0, 1.1), (0.12, 1.42), (0.45, 1.6), (1.0, 1.56), (1.7, 1.27), (2.3, 0.8), (2.7, 0.32), (2.85, 0)],
         paint=paint, bump=bump, segs=52, sub=3, gloss=1.0)
parts = [b.obj]
H = b.H

# puddle of gold round the foot
pud = [((0, 0, 0.02), 0.9, (1.95, 1.75, 0.12))]
for k, (a, r) in enumerate([(-78, 1.55), (62, 1.5), (138, 1.5), (-150, 1.5), (175, 1.45)]):
    rad = math.radians(a)
    pud.append(((math.sin(rad) * r, -math.cos(rad) * r, 0.02), 0.32, (1.2, 1.2, 0.3)))
parts.append(goo("Puddle", pud, lambda p, n: mix(G, G_L, 0.45), tris=360, resolution=0.08))

# coin stack + a loose coin
for k, (x, y, z, tilt) in enumerate([(1.65, -0.95, 0.06, 0), (1.66, -0.93, 0.18, 0.04), (1.63, -0.97, 0.30, -0.05), (1.67, -0.95, 0.42, 0.06),
                                     (-1.7, -0.9, 0.2, 1.2)]):
    c = lathe(f"Coin{k}", [(0, 0), (0, 0.24), (0.1, 0.24), (0.1, 0)], lambda p, n: mix(G, G_L, 0.5 + 0.5 * n.z), pos=(x, y, z - 0.05),
              axis=(math.sin(tilt) * 0.6, -math.sin(tilt), math.cos(tilt)), segs=14, smooth=False)
    parts.append(c)

# tiny tilted crown on top
ca = Vector((0.3, 0.05, 1)).normalized()
cpos = Vector((0.32, 0.08, H - 0.16))
q = ca.to_track_quat("Z", "Y")
parts.append(lathe("CrownBand", [(0, 0.38), (0.24, 0.42), (0.24, 0.36), (0, 0.32)], lambda p, n: mix(G, G_L, 0.6), pos=cpos, axis=ca, segs=16, smooth=False))
for k in range(5):
    a = k * math.tau / 5 + math.pi / 2
    base = cpos + q @ Vector((math.cos(a) * 0.4, math.sin(a) * 0.4, 0.22))
    tip = cpos + q @ Vector((math.cos(a) * 0.46, math.sin(a) * 0.46, 0.56))
    parts.append(lathe(f"CrownPt{k}", [(0, 0.11), (0.34, 0)], G_L, pos=base, axis=tip - base, segs=4, smooth=False))
    parts.append(ball(f"CrownBall{k}", 0.06, tip, G_W, subdiv=1))
    parts.append(gem(f"CrownGem{k}", cpos + q @ Vector((math.cos(a) * 0.43, math.sin(a) * 0.43, 0.12)), 0.07, RUBY if k % 2 else hexc("2fd4ff"),
                     axis=q @ Vector((math.cos(a), math.sin(a), 0))))

# chunky gold chain draped over the front, ruby pendant
chain = []
N = 11
for k in range(N):
    t = k / (N - 1)
    yaw = math.radians(-78 + 156 * t)
    z = 1.02 - 0.32 * math.sin(t * math.pi)
    chain.append(b.point(yaw, z, 0.07))
for k in range(N):
    p = chain[k]
    tng = (chain[min(k + 1, N - 1)] - chain[max(k - 1, 0)]).normalized()
    out = Vector((p.x, p.y, 0)).normalized()
    nrm = out if k % 2 else tng.cross(out).normalized()
    # link plane contains the tangent: normal is perpendicular to it
    nrm = (nrm - tng * nrm.dot(tng)).normalized()
    parts.append(torus(f"Link{k}", 0.13, 0.05, p, nrm, lambda p, n: mix(G_L, G_W, 0.2 + 0.6 * max(0, n.z)), segs=8, rsegs=4))
pend = b.point(0, 0.48, 0.16)
parts.append(torus("Bail", 0.09, 0.035, b.point(0, 0.68, 0.1), (1, 0, 0), G_L, segs=10, rsegs=5))
parts.append(lathe("PendRim", [(0, 0.24), (0.06, 0.26), (0.12, 0.24), (0.12, 0)], G_L, pos=pend - Vector((0, 0.05, 0)), axis=(0, -1, 0.15), segs=16, smooth=False))
parts.append(gem("Ruby", pend + Vector((0, -0.1, 0)), 0.2, RUBY, h=0.24, segs=8, axis=(0, -1, 0.15)))

# face: shades with a gold rim, smug smirk with a gold tooth
f = Face(b, eye_u=0.5, eye_v=1.62, mouth_v=1.28, mouth_col=INKB)
fs = Face(b, eye_u=0.52, eye_v=1.64, s=1.25)
fs.eyes("shades", color=hexc("1a0f2e"))
parts += fs.parts
f.mouth("smirk", w=1.1)
parts += f.parts
# bling: little glints floating round the crown and chain
for k, (x, y, z, sz) in enumerate([(-1.25, -0.6, 2.6, 0.2), (1.35, -0.5, 3.15, 0.16), (-1.55, -0.9, 1.15, 0.14)]):
    parts.append(slab(f"Glint{k}", star(0, 0, sz, sz * 0.28, n=4), 0.05, (x, y, z), (0.9, 0.45 * (1 if x > 0 else -1), 0), (0, 0, 1), G_W))
ship("slime_midas", parts)
