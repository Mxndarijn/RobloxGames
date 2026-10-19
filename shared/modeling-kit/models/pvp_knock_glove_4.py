# pvp_knock_glove_4 "Thunder Glove" (Knockback line, rank 4): purple mitt with two big yellow lightning-bolt fins swept
# up off the fist sides, a bolt emblem on the knuckles, yellow cuff with a purple stripe.
# Held tool, built upright like ranch_bat: see models/_pvp_glove.py for axes, grip and the shared builders.
from models._pvp_glove import *

S, FIST, LIFT = 1.15, 1.08, 0.05
PU_LO, PU, PU_HI = rgb(118, 70, 200), rgb(150, 94, 232), rgb(200, 156, 255)
YEL, YEL_SIDE, YEL_HI = rgb(255, 218, 52), rgb(240, 168, 40), rgb(255, 240, 150)
HOLE = rgb(110, 70, 170)

parts = mitt("Mitt", mitt_colour(PU_LO, PU, PU_HI, S), S=S, fist=FIST, lift=LIFT, tris=400)
body = parts[0]

pal = {"hole": HOLE, "lip": PU, "band_lo": YEL, "band": PU_LO, "band_hi": YEL, "top": YEL_SIDE}
parts.append(cuff("Cuff", lambda row, k: pal[row], S=S, segs=16))

# lightning bolt outline (u right, v up), tip at the bottom
BOLT = [(0.00, 1.00), (0.42, 1.00), (0.26, 0.60), (0.52, 0.60), (0.06, -0.10), (0.20, 0.42), (-0.04, 0.42)]


def bolt_colour(c, n, front):
    if abs(n.dot(front)) > 0.8:
        return YEL
    return YEL_SIDE if n.z < 0.3 else YEL_HI


def bolt_frame(origin, e_u, e_v):
    e_w = e_u.cross(e_v).normalized()
    m = Matrix((e_u, e_v, e_w)).transposed().to_4x4()
    m.translation = origin
    return m, e_w


# fins: bolts on both fist sides, tip sunk in the side, the broad top flaring up and out, swept back 25 deg
for s in (-1, 1):
    tilt, sweep_back = math.radians(30), math.radians(25 * s)
    rz = Matrix.Rotation(sweep_back, 3, "Z")
    e_v = rz @ Vector((s * math.sin(tilt), 0, math.cos(tilt)))      # bolt "up": outward and up
    e_u = rz @ Vector((s * math.cos(tilt), 0, -math.sin(tilt)))     # bolt "right": outward and down (mirrored per side)
    p, q, n = on_surface(body, (s * 3, 0.05 * S, (1.44 + LIFT) * S), (-s, 0, 0))
    k = 0.80 * S
    origin = p - e_v * (-0.10 * k) - e_u * (0.06 * k) - Vector((s, 0, 0)) * 0.22 * S  # bolt tip buried in the side
    m, w = bolt_frame(origin, e_u * k, e_v * k)
    parts.append(slab("Fin%d" % (s > 0), BOLT, 0.12 * S, lambda c, nn, w=w: bolt_colour(c, nn, w), m, bevel_w=0.03))

# bolt emblem on the back of the hand
p, q, n = on_surface(body, (0.0, -3, (1.42 + LIFT) * S), (0, 1, 0), sink=0.02)
k = 0.46 * S
e_v = (Vector((0, 0, 1)) - n * n.z).normalized()
e_u = e_v.cross(n).normalized()
m, w = bolt_frame(p - e_u * 0.24 * k - e_v * 0.45 * k, e_u * k, e_v * k)
parts.append(slab("Emblem", BOLT, 0.09 * S, lambda c, nn, w=w: bolt_colour(c, nn, w), m, bevel_w=0.02))

ship("pvp_knock_glove_4", parts, grip=(0, 0, GRIP_Z * S))
