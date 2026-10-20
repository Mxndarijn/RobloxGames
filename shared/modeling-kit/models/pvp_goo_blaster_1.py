# pvp_goo_blaster_1 "Goo Squirter": tier-1 held goo gun, ~2.5 studs long.
# Toy squirt gun: butter-yellow capsule body, red nozzle, red pistol grip, one green goo bottle on top.
# Kit convention: barrel points -Y (front), Z up, grip bottom on z=0. GRIP = palm centre on the pistol grip.
from models._pvp import *

BODY_Z = 1.12          # barrel axis height
GRIP = (0.0, 0.62, 0.5)

parts = []

# body + nozzle: one lathe along -Y (t = -world y), oval section (taller than wide)
PROF = [(0.00, -1.20), (0.22, -1.18), (0.33, -1.06), (0.37, -0.80), (0.37, -0.62), (0.375, -0.60), (0.375, -0.42),
        (0.37, -0.40), (0.37, -0.10), (0.34, 0.25),
        (0.26, 0.45), (0.17, 0.52),                      # body shoulder -> nozzle
        (0.13, 0.56), (0.11, 1.05), (0.15, 1.10), (0.15, 1.22), (0.08, 1.28), (0.00, 1.29)]
BODY_LO, BODY_HI = mix(BUTTER, WOOD, 0.12), mix(BUTTER, CREAM, 0.25)


def body_col(i, k, z):
    if i >= 10:  # nozzle
        return ROOF if i < 12 else mix(ROOF, CREAM, 0.15)
    if i == 5:  # red stripe round the body
        return ROOF
    # local y (world z) is lost here: use the segment index for a top-light / bottom-dark split
    a = k / 14.0 * math.tau
    t = 0.5 + 0.5 * math.sin(a)
    return mix(BODY_LO, BODY_HI, t)


parts.append(lathe("Body", PROF, mat_at((0, 0, BODY_Z), "-y"), segs=14, color_fn=body_col, sx=0.95, sy=1.1))

# brass collar where the nozzle leaves the body
parts.append(torus("Collar", 0.15, 0.06, mat_at((0, -0.62, BODY_Z), "-y"), segs=12, rsegs=5,
                   color_fn=lambda k, j, c: BRASS_HI if c.y > 0 else BRASS))

# pistol grip: tilted bevelled box under the rear of the body
g = rbox("Grip", (0.36, 0.48, 1.05), (0, 0.62, 0.52), ROOF, mix(ROOF, CREAM, 0.18), bev=0.1, rot=(-14, 0, 0))
parts.append(g)

# trigger guard (tube loop) + trigger
parts.append(tube("Guard", [(0, -0.12, 0.80), (0, -0.14, 0.55), (0, 0.10, 0.42), (0, 0.42, 0.45)],
                  [0.065, 0.065, 0.065, 0.065], color=BRASS, segs=6))
parts.append(rbox("Trigger", (0.12, 0.12, 0.3), (0, 0.12, 0.66), ROOF_D, ROOF, bev=0.03, rot=(20, 0, 0)))

# goo bottle on top (vertical lathe): brass neck ring, goo bulb, brass cap
TANK_Y, TZ = 0.35, BODY_Z + 0.28
TPROF = [(0.00, 0.00), (0.17, 0.00), (0.19, 0.10),             # brass neck
         (0.30, 0.16), (0.36, 0.34), (0.36, 0.56), (0.30, 0.70),  # goo bulb
         (0.18, 0.76), (0.20, 0.80), (0.20, 0.92), (0.00, 0.96)]   # cap


def tank_col(i, k, z):
    if i <= 1 or i >= 7:
        return BRASS if i <= 1 else (BRASS_HI if i >= 8 else BRASS)
    t = (z - 0.16) / 0.54
    c = mix(mix(GOO, P["ranch_field_dark"], 0.25), GOO, min(1, max(0, t)))
    if k in (10, 11) and 3 <= i <= 5:
        c = mix(GOO, GOO_HI, 0.8)  # glossy window streak
    return c


parts.append(lathe("Tank", TPROF, mat_at((0, TANK_Y, TZ)), segs=12, color_fn=tank_col))

# goo drop hanging off the nozzle tip
parts.append(blob("Drop", 0.11, (0, -1.24, BODY_Z - 0.17), mix(GOO, GOO_HI, 0.3), subdiv=2, squash=(1, 1, 1.35), jitter=0.0))

report_grip(parts, GRIP)
finish("pvp_goo_blaster_1", parts)
