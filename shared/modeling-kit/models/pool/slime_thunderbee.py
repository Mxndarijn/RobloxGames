# Thunderbee (hybrid, tier 5: zap + bumble + imp): electric bee. Bumble's round bee body in
# electric yellow with Zap's indigo bands, lightning-bolt antennae, glassy wings with yellow
# electric rims and crackle lines, Imp's arrow tail as the stinger, a glowing visor and Imp's
# fanged crescent grin, sparks all round.
from models._slimepool import *

Y, Y_L, Y_D = hexc("ffe21a"), hexc("fff59a"), hexc("f0a810")
IND, IND_D, IND_L = hexc("3a2c9c"), hexc("221a5c"), hexc("5a48d8")
BOLT, BOLT_L = hexc("ffe02a"), hexc("fffbd0")
WING, WING_TIP, ARC = hexc("f0fbff"), hexc("9fe4ff"), hexc("ffd400")
GLOW = hexc("7af4ff")


def axes(x, y):
    x = Vector(x).normalized()
    y = Vector(y)
    y = (y - x * y.dot(x)).normalized()
    return x, y


def paint(a, z, p):
    c = mix(Y_D, Y, smoothstep(0.0, 0.9, z))
    return mix(c, Y_L, 0.35 * smoothstep(1.3, 2.5, z))


def back_band(a, z):
    if abs(a) > math.radians(100) and 1.05 <= z <= 1.38:
        return IND
    return None


b = Body([(0, 1.08), (0.15, 1.42), (0.5, 1.6), (1.1, 1.58), (1.7, 1.36), (2.2, 0.96), (2.55, 0.46), (2.68, 0)],
         paint=paint, segs=40, sub=2, sy=1.04, sectors=back_band,
         bands=[(0.0, 0.58, IND_D), (1.9, 2.22, IND)])
parts = [b.obj]


def bolt_poly(s=1.0):
    pts = [(-0.05, 0.5), (0.25, 0.5), (0.08, 0.1), (0.3, 0.1), (-0.15, -0.55), (0.0, -0.08), (-0.22, -0.08)]
    return [(x * s, y * s) for x, y in pts]


# lightning-bolt antennae: indigo stalk ending in a big yellow bolt
for sd in (-1, 1):
    r0 = Vector((sd * 0.3, 0.0, 2.55))
    pts = [r0, r0 + Vector((sd * 0.12, -0.04, 0.35)), r0 + Vector((sd * 0.35, -0.08, 0.62)), r0 + Vector((sd * 0.55, -0.1, 0.78))]
    parts.append(horn(f"Ant{sd}", pts, [0.08, 0.065, 0.055, 0.05], IND_D, IND_L, segs=6))
    tip = pts[-1] + Vector((sd * 0.12, 0, 0.36))
    poly = [(x * (1 if sd > 0 else -1), y) for x, y in bolt_poly(1.3)]
    parts.append(slab(f"AntBolt{sd}", poly if sd > 0 else list(reversed(poly)), 0.14, tip, (1, 0, 0), (sd * -0.25, 0, 1),
                      zgrad(BOLT, BOLT_L, tip.z - 0.5, tip.z + 0.55)))


# glassy wings with an electric yellow rim and a crackle line
def wing_poly(L, W, n=8):
    pts = [(0.0, 0.0)]
    for k in range(1, n):
        t = math.pi * k / n
        pts.append((L * (0.5 - 0.5 * math.cos(t)) ** 0.8, W / 2 * math.sin(t) ** 1.2))
    pts.append((L, 0.0))
    for k in range(n - 1, 0, -1):
        t = math.pi * k / n
        pts.append((L * (0.5 - 0.5 * math.cos(t)) ** 0.8, -W / 2 * math.sin(t) ** 1.2 * 0.8))
    return pts


for sd in (-1, 1):
    for nm, L, W, root, xd, up in (("WingU", 2.0, 1.2, (sd * 0.4, 0.9, 2.15), (sd * 0.85, 0.45, 0.8), (0, -0.25, 1)),
                                   ("WingL", 1.3, 0.78, (sd * 0.45, 0.95, 1.9), (sd * 0.95, 0.55, 0.0), (0, -0.2, 1))):
        X, Yax = axes(xd, up)
        O = Vector(root)
        col = along(WING, WING_TIP, O, O + X * L, 1.3)
        parts.append(puffy_slab(f"{nm}{sd}", wing_poly(L, W), 0.09, O, X, Yax, col, rows=2))
        rim = [(x + (x - L * 0.5) * 0.06, y * 1.12) for x, y in wing_poly(L, W)]
        parts.append(slab(f"{nm}Rim{sd}", rim, 0.03, O, X, Yax, ARC))
        crack = zigzag(L * 0.18, L * 0.86, 0.02, W * 0.11, 5, 0.045)
        parts.append(slab(f"{nm}Crack{sd}", crack, 0.13, O, X, Yax, ARC))

# Imp's arrow tail as the stinger: indigo curl out of the back, yellow arrow tip
tail = [(0, 1.45, 0.75), (0.0, 1.85, 0.8), (0.1, 2.2, 1.05), (0.18, 2.35, 1.4), (0.12, 2.25, 1.7)]
parts.append(horn("Tail", tail, [0.17, 0.13, 0.1, 0.085, 0.07], IND_D, IND, segs=8))
tip = Vector(tail[-1])
parts.append(slab("Arrow", [(0, 0.62), (0.46, -0.08), (0.12, 0.0), (0.0, -0.18), (-0.12, 0.0), (-0.46, -0.08)], 0.11,
                  tip + Vector((0, 0, -0.05)), (1, 0, 0), (0, 0.3, 1), zgrad(Y_D, Y, tip.z, tip.z + 0.4)))

# sparks crackling round it
for k, (x, y, z, r) in enumerate([(-2.0, -0.3, 2.9, 0.15), (2.1, -0.2, 3.1, 0.13), (-1.0, -0.5, 3.75, 0.11),
                                  (1.2, -0.3, 3.85, 0.1), (-2.2, 0.2, 1.4, 0.1), (2.25, 0.1, 1.6, 0.11)]):
    parts.append(gem(f"Spark{k}", (x, y, z), r, BOLT if k % 2 else hexc("8ef6ff"), segs=4))

# face: glowing visor + fanged crescent grin
f = Face(b, eye_v=1.5, mouth_v=0.98, s=1.08)
f.eyes("visor", color=GLOW)
for k, (du, w_) in enumerate(((-0.62, 0.08), (-0.48, 0.04), (0.62, 0.06))):
    f.d(f"Glint{k}", rect(du, f.ev + 0.02, w_, 0.3, math.radians(-30)), hexc("8a86c8"), off=0.075, th=0.008)
mv = f.mv
W = 0.44
top = [(W * (k / 8 - 1), mv + 0.15 * (k / 8 - 1) ** 2) for k in range(17)]
bot = [(W * (k / 8 - 1), mv + 0.15 * (k / 8 - 1) ** 2 - 0.22 * (1 - (k / 8 - 1) ** 2)) for k in range(15, 0, -1)]
f.d("Mouth", top + bot, IND_D)
for sd in (-1, 1):
    f.d(f"Fang{sd}", [(sd * 0.09, mv + 0.005), (sd * 0.23, mv + 0.04), (sd * 0.16, mv - 0.14)], WHITE, off=0.04, th=0.012)
f.d("Tongue", oval(0, mv - 0.15, 0.18, 0.06), TONGUE, off=0.04, th=0.012)
f.cheeks(color=hexc("ff9a5a"), u=0.95, v=1.08)
parts += f.parts
# bolt markings on the cheeks/flanks
for k, yaw in enumerate((80, -80)):
    parts.append(decal(f"Mark{k}", bolt_poly(0.9), IND, frame_at(yaw, 1.25), off=0.015, on=["Body"], step=0))
ship("slime_thunderbee", parts)
