# pvp_goo_trap_1 "Goo Puddle": tier-1 goo trap, a green goo splat with bubbles, ~3.4 studs wide, ~0.7 tall.
# Shown lying on the ground AND held in hand, so it is a thick, rounded splat (not a decal) with bubbles
# that give it a readable top. Lies on z = 0. Lobed polar dome (rounded rolled edge) + satellite droplets.
from models._pvp import *

R0 = 1.45
LOBES = [(0.13, 5, 0.4), (0.06, 9, 1.7), (0.04, 13, 0.2)]


def outline(a):
    return R0 * (1 + sum(amp * math.sin(n * a + ph) for amp, n, ph in LOBES))


# rows (f, z): soft dome top, a fat rolled edge, tucked foot on the ground
ROWS = [(0.0, 0.40), (0.30, 0.39), (0.55, 0.36), (0.75, 0.31), (0.88, 0.25), (0.96, 0.17), (1.0, 0.08), (0.985, 0.0)]
# live goo (gameplay: players must spot it on the grass): more saturated and darker-rimmed than ranch_goo
G_LO = rgb(40, 162, 126)
G_MID = rgb(72, 218, 170)
G_TOP = rgb(156, 248, 214)


def goo_col(i, th, c):
    if i < 0:
        return G_LO
    t = min(1.0, max(0.0, c.z / 0.40))
    col_ = mix(G_LO, G_MID, t / 0.6) if t < 0.6 else mix(G_MID, G_TOP, (t - 0.6) / 0.4)
    if i == 4 and 0.6 < th < 1.6:   # glossy rim highlight on the sunny side
        col_ = mix(col_, GOO_HI, 0.5)
    return col_


parts = [splat("Puddle", outline, ROWS, segs=36, color_fn=goo_col)]

# satellite droplets round the splat (small flat domes)
for k, (a, d, r) in enumerate([(0.3, 1.18, 0.26), (1.9, 1.12, 0.20), (3.4, 1.22, 0.24), (4.6, 1.15, 0.18), (5.6, 1.20, 0.15)]):
    x, y = d * outline(a) * math.cos(a), d * outline(a) * math.sin(a)
    rr = r
    parts.append(splat(f"Drop{k}", lambda _a, rr=rr: rr, [(0.0, rr * 0.55), (0.6, rr * 0.45), (1.0, rr * 0.15), (0.95, 0.0)],
                       segs=10, color_fn=lambda i, th, c: G_LO if i < 0 else mix(G_LO, G_TOP, min(1, c.z / 0.15)), pos=(x, y, 0)))

# bubbles on top (big, mid, small) sunk into the dome
for k, (x, y, r) in enumerate([(-0.35, 0.15, 0.36), (0.45, -0.30, 0.27), (0.30, 0.55, 0.20), (-0.70, -0.55, 0.17), (-0.05, -0.75, 0.13)]):
    z = 0.40 - 0.35 * (x * x + y * y) / (R0 * R0) * 0.6
    parts.append(bubble(f"Bubble{k}", r, (x, y, z + r * 0.25), mix(G_MID, G_TOP, 0.55), mix(G_TOP, CREAM, 0.3)))

for o in parts:
    mark_smooth(o)
ship("pvp_goo_trap_1", parts)
