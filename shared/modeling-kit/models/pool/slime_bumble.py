# Bumble (Uncommon): bee slime. Round yellow bee with black bands, glassy double wings, a curved
# stinger, ball antennae and cool shades + smirk.
from models._slimepool import *

Y, Y_L, K = hexc("ffd02a"), hexc("fff08a"), hexc("2a2230")
WING, WING_TIP, WING_RIM = hexc("f4fcff"), hexc("a8e2ff"), hexc("5aa8e0")


def axes(x, y):
    """orthonormal in-plane axes: x as given, y made perpendicular to x."""
    x = Vector(x).normalized()
    y = Vector(y)
    y = (y - x * y.dot(x)).normalized()
    return x, y


def paint(a, z, p):
    # warm honey glow: lighter belly low on the front
    f = smoothstep(0.9, 0.3, abs(a)) * smoothstep(1.4, 0.7, z)
    return mix(Y, Y_L, 0.45 * f)


def back_band(a, z):
    # third stripe only on the back half so the face stays clean
    if abs(a) > math.radians(95) and 1.12 <= z <= 1.42:
        return K
    return None


b = Body([(0, 0.95), (0.12, 1.3), (0.5, 1.53), (1.2, 1.56), (1.9, 1.38), (2.45, 0.98), (2.8, 0.5), (2.95, 0)],
         paint=paint, segs=36, sub=2, sy=1.04,
         bands=[(0.36, 0.7, K), (2.12, 2.46, K)])
parts = [b.obj]

# antennae: curly stalks with shiny ball tips
for sd in (-1, 1):
    parts.append(horn(f"Ant{sd}", [(sd * 0.22, 0.05, 2.8), (sd * 0.38, -0.05, 3.3), (sd * 0.66, -0.1, 3.62), (sd * 0.88, -0.06, 3.7)],
                      [0.075, 0.06, 0.05, 0.045], K, K, segs=6))
    parts.append(ball(f"AntB{sd}", 0.18, (sd * 0.92, -0.06, 3.72), along(K, hexc("6a5a78"), (sd * 0.92, 0.1, 3.6), (sd * 0.85, -0.2, 3.9))))

# wings: two glassy teardrop pairs on the back with a blue rim, root white -> cyan tip
def wing_poly(L, W, n=8):
    pts = [(0.0, 0.0)]
    for k in range(1, n):
        t = math.pi * k / n  # 0..pi around the far end
        x = L * (0.5 - 0.5 * math.cos(t)) ** 0.8
        y = W / 2 * math.sin(t) ** 1.2
        pts.append((x, y))
    pts.append((L, 0.0))
    for k in range(n - 1, 0, -1):
        t = math.pi * k / n
        x = L * (0.5 - 0.5 * math.cos(t)) ** 0.8
        y = -W / 2 * math.sin(t) ** 1.2 * 0.8
        pts.append((x, y))
    return pts


for sd in (-1, 1):
    for nm, L, W, root, xd, up in (("WingU", 1.55, 0.95, (sd * 0.4, 0.9, 2.35), (sd * 0.85, 0.45, 0.75), (0, -0.25, 1)),
                                   ("WingL", 1.05, 0.62, (sd * 0.45, 0.95, 2.1), (sd * 0.95, 0.55, 0.05), (0, -0.2, 1))):
        X, Yax = axes(xd, up)
        O = Vector(root)
        tip = O + X * L
        col = along(WING, WING_TIP, O, tip, 1.3)
        parts.append(puffy_slab(f"{nm}{sd}", wing_poly(L, W), 0.09, O, X, Yax, col, rows=2))
        rim = [(x * 1.0 + (x - L * 0.5) * 0.06, y * 1.1) for x, y in wing_poly(L, W)]
        parts.append(slab(f"{nm}Rim{sd}", rim, 0.025, O, X, Yax, WING_RIM))

# stinger: dark curved spike low on the back, pointing back and slightly up
sb = b.point(math.pi, 1.1)
parts.append(lathe("Stinger", [(-0.2, 0.34), (0.15, 0.28), (0.5, 0.15), (0.95, 0)], along(K, hexc("5a4e6a"), sb, sb + Vector((0, 0.9, 0.5))),
                   pos=(0, sb.y, sb.z), axis=(0, 1, 0.55), segs=10, sub=2))

parts += Face(b, eye_v=1.58, mouth_v=1.1, s=1.15).eyes("shades", color=hexc("1c1626")).mouth("smirk").cheeks(color=hexc("ff9a5a")).parts
ship("slime_bumble", parts)
