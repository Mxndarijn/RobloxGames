# Truffle (Rare hybrid: mushie + flan + pebble): posh chocolate-truffle mushroom. Caramel stem-body
# with knobbly pebble lumps, a glossy cocoa cap (mushie) dripping ganache, rainbow sprinkles, a cream
# dollop with a cherry (flan), a gold monocle and one haughty raised brow (pebble's grump, gone posh).
from models._slimepool import *

CAR, CAR_D, CAR_L = hexc("f0a446"), hexc("b8641e"), hexc("ffd88a")
COC, COC_D, COC_L = hexc("7e3e1e"), hexc("42190a"), hexc("d08a5a")
GILL, GILL_D = hexc("e8b07a"), hexc("a8683a")
CHERRY, CHERRY_D = hexc("ff2a44"), hexc("a8102a")
CREAM, CREAM_D = hexc("fffaf2"), hexc("f2dcc8")
SPRINKLES = [hexc("ff5ea8"), hexc("ffe14a"), hexc("5ad2ff"), hexc("8cf06a"), hexc("ffffff"), hexc("b88cff")]


def nz(a, z, s=1.0):
    return noise.noise(Vector((math.sin(a) * 1.7 * s, math.cos(a) * 1.7 * s, z * 1.3 * s)))


def paint(a, z, p):
    c = mix(CAR_D, CAR, smoothstep(0.0, 1.1, z))
    c = mix(c, CAR_L, 0.4 * smoothstep(0.85, 0.25, abs(a)) * smoothstep(1.5, 0.5, z))
    return mix(c, CAR_L, 0.35 * max(0.0, nz(a, z, 2.2)))


b = Body([(0, 1.15), (0.12, 1.4), (0.5, 1.48), (1.2, 1.4), (1.8, 1.2), (2.25, 0.88), (2.55, 0.4), (2.62, 0)],
         paint=paint, bump=lambda a, z: 0.05 * nz(a, z, 0.9) * smoothstep(0.1, 0.5, z), segs=36, sub=2, gloss=0.6)
parts = [b.obj]

# ---- cocoa cap: round truffle dome with a rolled rim, gills underneath
CZ = 2.02


def cap_col(p, n):
    if n.z < -0.3 and p.z < CZ + 0.3:
        return mix(GILL_D, GILL, smoothstep(0.4, 1.8, math.hypot(p.x, p.y)))
    c = mix(COC_D, COC, smoothstep(CZ, CZ + 0.9, p.z))
    d = (p - Vector((0, 0, CZ + 0.5))).normalized()
    h = max(0.0, d.dot(Vector((-0.45, -0.55, 0.7)).normalized()))
    return mix(c, COC_L, 0.85 * smoothstep(0.88, 0.975, h))


CAP_PROF = [(CZ + 0.1, 0.0), (CZ + 0.08, 0.9), (CZ - 0.06, 1.5), (CZ - 0.02, 1.7), (CZ + 0.22, 1.8),
            (CZ + 0.72, 1.72), (CZ + 1.18, 1.36), (CZ + 1.48, 0.78), (CZ + 1.58, 0.0)]
cap = lathe("Cap", CAP_PROF, cap_col, segs=32, sub=2)
register(cap)
parts.append(cap)


def cap_at(t):
    """point (z, r) and outward normal elevation (deg) on the cap's upper side, t 0 (rim) .. 1 (top)."""
    up = CAP_PROF[4:]
    L = [0.0]
    for (z0, r0), (z1, r1) in zip(up, up[1:]):
        L.append(L[-1] + math.hypot(z1 - z0, r1 - r0))
    l = t * L[-1]
    for k in range(len(up) - 1):
        if L[k + 1] >= l:
            u = (l - L[k]) / (L[k + 1] - L[k])
            (z0, r0), (z1, r1) = up[k], up[k + 1]
            return z0 + (z1 - z0) * u, r0 + (r1 - r0) * u, math.degrees(math.atan2(r0 - r1, z1 - z0))
    return up[-1][0], 0.0, 90.0


# ganache drips over the cap rim: short wide tongues (lip of 3 balls, a neck, a fat round tip)
for k, (yaw, L) in enumerate(((38, 0.22), (-34, 0.14), (80, 0.28), (-84, 0.2), (128, 0.16), (-140, 0.26), (176, 0.2))):
    a = math.radians(yaw)
    out = Vector((math.sin(a), -math.cos(a), 0))
    tan = Vector((math.cos(a), math.sin(a), 0))
    rim = out * 1.74 + Vector((0, 0, CZ + 0.14))
    balls = [(tuple(rim + tan * dt), 0.15) for dt in (-0.16, 0.0, 0.16)]
    balls.append((tuple(out * 1.7 + Vector((0, 0, CZ + 0.02 - L * 0.5))), 0.14))
    balls.append((tuple(out * 1.68 + Vector((0, 0, CZ - L))), 0.16))
    parts.append(goo(f"Drip{k}", balls, lambda p, n: mix(COC_D, COC, 0.75), tris=70, resolution=0.05))

# rainbow sprinkles all over the cap: each aimed straight at a point on the cap surface
for k in range(38):
    yaw = (k * 137.5) % 360
    t = 0.03 + 0.8 * ((k * 0.7548 + 0.37 * math.sin(k * 2.3) + 0.5) % 1.0) ** 1.3
    z, r, el = cap_at(t)
    a = math.radians(yaw)
    rot = math.radians((k * 71) % 180)
    parts.append(decal(f"Sprinkle{k}", rect(0, 0, 0.26, 0.08, rot), SPRINKLES[k % len(SPRINKLES)],
                       frame_at(yaw, z, el, math.sin(a) * r, -math.cos(a) * r), off=0.012, th=0.035, on=["Cap"], step=None))

# cream dollop + cherry on top (flan)
TOPZ = CZ + 1.54
parts.append(goo("Cream", [((0, 0.05, TOPZ + 0.06), 0.52, (1, 1, 0.42)), ((0, 0.05, TOPZ + 0.28), 0.36, (1, 1, 0.55)),
                           ((0, 0.05, TOPZ + 0.46), 0.2)], zgrad(CREAM_D, CREAM, TOPZ, TOPZ + 0.6), tris=160, resolution=0.08))
CH = Vector((0.02, 0.05, TOPZ + 0.84))
parts.append(ball("Cherry", 0.34, tuple(CH), along(CHERRY_D, CHERRY, CH + Vector((0.2, 0.2, -0.25)), CH + Vector((-0.15, -0.2, 0.2)))))
parts.append(ball("CherryHi", 0.07, tuple(CH + Vector((-0.13, -0.23, 0.14))), WHITE, subdiv=1))
parts.append(horn("Stem", [tuple(CH + Vector((0, 0, 0.26))), tuple(CH + Vector((0.08, 0.05, 0.54))), tuple(CH + Vector((0.25, 0.12, 0.72)))],
                  [0.04, 0.035, 0.03], hexc("4a8a2a"), hexc("6ab838"), segs=5))

# ---- face: haughty, one eye behind a gold monocle, raised brow over it, flat brow on the other
f = Face(b, eye_u=0.5, eye_v=1.34, mouth_v=0.86)
f._eye_round(-1, 0.48, 0.6, lid=0.48, tilt=-0.15, iris=hexc("7a3a1a"))
f._eye_round(1, 0.56, 0.72, iris=hexc("7a3a1a"), look=(0, 0.02))
mu, mv_ = 0.5, 1.34
f.d("BrowR", arc(mu, mv_ + 0.3, 0.3, 45, 135, 0.085, n=8), COC_D, off=0.02)
f.d("BrowL", rect(-mu, mv_ + 0.3, 0.38, 0.085, math.radians(-6)), COC_D, off=0.02)
f.mouth("smirk", w=1.1)
f.cheeks(color=hexc("ff9a7a"), w=0.3, h=0.14)
parts += f.parts
mono_c = b.point(math.asin(mu / 1.45), mv_, 0.06)
mono_c = Vector((mu, mono_c.y, mv_))
parts.append(torus("Monocle", 0.38, 0.06, tuple(mono_c), (0, 1, 0.15), GOLD, segs=24, rsegs=6))
# chain from the monocle down the cheek to the side
ch = [mono_c + Vector((0.2, 0.0, -0.3))] + [b.point(math.radians(y), z, 0.05) for y, z in ((28, 0.92), (38, 0.72), (50, 0.62), (60, 0.66))]
parts.append(horn("Chain", [tuple(p) for p in ch], [0.035] * 5, GOLD_D, GOLD, segs=5))
# posh red bow tie low on the front
BT, BT_D = hexc("e8203c"), hexc("9a0c22")
bp = b.point(0, 0.42, 0.06)
for sd in (-1, 1):
    parts.append(puffy_slab(f"Tie{sd}", [(0.05, 0), (0.5, 0.25), (0.54, -0.25)], 0.16, tuple(bp + Vector((0, -0.02, 0)) ),
                            (sd, -0.12, 0), (0, 0.15, 1), zgrad(BT_D, BT, 0.2, 0.62)))
parts.append(ball("TieKnot", 0.13, tuple(bp + Vector((0, -0.08, 0))), BT, squash=(1, 0.8, 1.1)))
ship("slime_truffle", parts)
