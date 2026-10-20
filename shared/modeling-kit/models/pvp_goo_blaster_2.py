# pvp_goo_blaster_2 "Goo Blaster": tier-2 held goo gun, ~3.2 studs long.
# Red capsule body with a butter stripe, twin green goo tanks side by side on top (brass bridge),
# long butter barrel with a ribbed wooden pump slide and a flared brass muzzle, wooden pistol grip.
# Kit convention: barrel points -Y (front), Z up, grip bottom on z=0. GRIP = palm centre on the pistol grip.
from models._pvp import *

BODY_Z = 1.22
GRIP = (0.0, 0.92, 0.52)
parts = []

RED_LO, RED_HI = mix(ROOF, PINK, 0.25), mix(ROOF, CREAM, 0.22)
BUT_LO, BUT_HI = mix(BUTTER, WOOD, 0.12), mix(BUTTER, CREAM, 0.25)


def updown(lo, hi, k, segs):
    a = (k + 0.5) / segs * math.tau
    return mix(lo, hi, 0.5 + 0.5 * math.sin(a))


# body capsule along -Y (t = -world y): back end, stripe, front shoulder into the barrel
BODY = [(0.00, -1.56), (0.26, -1.54), (0.39, -1.40), (0.43, -1.15), (0.43, -0.55), (0.445, -0.52), (0.445, -0.30),
        (0.43, -0.27), (0.43, 0.05), (0.40, 0.30), (0.30, 0.48), (0.00, 0.52)]


def body_col(i, k, z):
    if i == 5:
        return updown(BUT_LO, BUT_HI, k, 14)
    return updown(RED_LO, RED_HI, k, 14)


parts.append(lathe("Body", BODY, mat_at((0, 0, BODY_Z), "-y"), segs=14, color_fn=body_col, sx=0.98, sy=1.12))

# barrel (from inside the body) with a flared brass muzzle
BAR = [(0.00, 0.30), (0.17, 0.30), (0.17, 1.38), (0.20, 1.42), (0.27, 1.52), (0.27, 1.62), (0.18, 1.64), (0.00, 1.64)]


def bar_col(i, k, z):
    if i >= 3:
        return updown(BRASS, BRASS_HI, k, 12)
    return updown(BUT_LO, BUT_HI, k, 12)


parts.append(lathe("Barrel", BAR, mat_at((0, 0, BODY_Z), "-y"), segs=12, color_fn=bar_col))

# ribbed wooden pump slide round the barrel
PUMP = [(0.00, 0.62)]
for j in range(4):
    t0 = 0.62 + j * 0.16
    PUMP += [(0.25, t0 + 0.01), (0.27, t0 + 0.035), (0.27, t0 + 0.115), (0.25, t0 + 0.15)]
PUMP += [(0.00, 0.62 + 4 * 0.16 + 0.01)]
parts.append(lathe("Pump", PUMP, mat_at((0, 0, BODY_Z - 0.04), "-y"), segs=12,
                   color_fn=lambda i, k, z: updown(mix(WOOD_D, WOOD, 0.4), mix(WOOD, CREAM, 0.15), k, 12) if i % 4 in (2, 3)
                   else updown(mix(WOOD_D, WOOD, 0.75), mix(WOOD, CREAM, 0.08), k, 12)))

# wooden pistol grip + brass trigger guard + red trigger
parts.append(rbox("Grip", (0.40, 0.52, 1.10), (0, 0.92, 0.55), mix(WOOD_D, WOOD, 0.6), mix(WOOD, CREAM, 0.18), bev=0.11, rot=(-15, 0, 0)))
parts.append(tube("Guard", [(0, 0.12, 0.86), (0, 0.10, 0.58), (0, 0.38, 0.46), (0, 0.70, 0.50)],
                  [0.07] * 4, color=BRASS, segs=6))
parts.append(rbox("Trigger", (0.13, 0.13, 0.32), (0, 0.40, 0.70), ROOF, mix(ROOF, CREAM, 0.2), bev=0.03, rot=(20, 0, 0)))

# twin goo tanks on top, leaning out a little, brass bridge across their caps
TPROF = [(0.00, 0.00), (0.15, 0.00), (0.17, 0.10), (0.26, 0.16), (0.30, 0.34), (0.30, 0.66), (0.25, 0.80),
         (0.16, 0.86), (0.18, 0.90), (0.18, 1.00), (0.00, 1.03)]


def tank_col(i, k, z):
    if i <= 1 or i >= 7:
        return BRASS_HI if i >= 8 else BRASS
    t = min(1, max(0, (z - 0.16) / 0.64))
    c = mix(mix(GOO, P["ranch_field_dark"], 0.25), GOO, t)
    if k in (10, 11) and 3 <= i <= 5:
        c = mix(GOO, GOO_HI, 0.8)
    return c


TY, TZ = 0.10, BODY_Z + 0.36
for s in (-1, 1):
    M = Matrix.Translation((s * 0.24, TY, TZ)) @ Matrix.Rotation(math.radians(s * 9), 4, "Y")
    parts.append(lathe(f"Tank{s}", TPROF, M, segs=12, color_fn=tank_col))
top = TZ + 0.98
parts.append(tube("Bridge", [(-0.40, TY, top - 0.02), (0, TY, top + 0.12), (0.40, TY, top - 0.02)],
                  [0.07, 0.08, 0.07], color=BRASS_HI, segs=6))

# goo drop on the muzzle lip
parts.append(blob("Drop", 0.12, (0, -1.60, BODY_Z - 0.30), mix(GOO, GOO_HI, 0.3), subdiv=2, squash=(1, 1, 1.35), jitter=0.0))

report_grip(parts, GRIP)
finish("pvp_goo_blaster_2", parts)
