# pvp_goo_blaster_3 "Goo Cannon": tier-3 held goo gun, ~4 studs long, chunky shoulder-ish cannon.
# Fat red barrel with brass bands and a flared brass bell whose throat glows with live goo, a glowing goo drum
# (brass rims, glowing side windows) on top, wooden pistol grip + front handle, wooden stock with a red butt pad.
# Kit convention: barrel points -Y (front), Z up, grip bottom on z=0. GRIP = palm centre on the pistol grip.
from models._pvp import *

BODY_Z = 1.36
GRIP = (0.0, 0.86, 0.52)
parts = []

RED_LO, RED_HI = mix(ROOF, PINK, 0.25), mix(ROOF, CREAM, 0.22)
BR_LO, BR_HI = mix(BUTTER, WOOD, 0.35), mix(BUTTER, CREAM, 0.2)  # richer gold than the palette pewter-brass
G_LO, G_HI = mix(GLOW, GOO, 0.35), GLOW_HI


def updown(lo, hi, k, segs):
    a = (k + 0.5) / segs * math.tau
    return mix(lo, hi, 0.5 + 0.5 * math.sin(a))


# barrel along -Y (t = -world y): rounded rear cap, three brass bands, bell muzzle with a glowing throat
R = 0.46
BAR = [(0.00, -1.30), (0.30, -1.28), (0.42, -1.20),
       (0.46, -1.08), (0.51, -1.05), (0.51, -0.88), (0.46, -0.85),     # band A rows 3-5
       (0.46, 0.25), (0.51, 0.28), (0.51, 0.45), (0.46, 0.48),         # band B rows 7-9
       (0.44, 1.40), (0.50, 1.50), (0.62, 1.78), (0.66, 1.98), (0.62, 2.06),  # bell rows 11-14
       (0.48, 2.06), (0.40, 1.98), (0.00, 1.88)]                        # lip + glowing throat
BANDS = {3, 4, 5, 7, 8, 9, 11, 12, 13, 14}


def bar_col(i, k, z):
    if i >= 15:
        return {15: mix(BR_HI, CREAM, 0.2), 16: GLOW}.get(i, GLOW_HI)
    if i in BANDS:
        return updown(BR_LO, BR_HI, k, 16)
    return updown(RED_LO, RED_HI, k, 16)


parts.append(lathe("Barrel", BAR, mat_at((0, 0, BODY_Z), "-y"), segs=16, color_fn=bar_col))

# goo drum on top, axis along X: brass rims, glowing goo band, glowing side windows
DR, DW = 0.56, 0.36
DRUM = [(0.00, -DW - 0.04), (0.26, -DW - 0.03), (0.30, -DW - 0.01),             # glowing window rows 0-1
        (0.36, -DW), (DR, -DW), (DR + 0.03, -DW + 0.06), (DR + 0.03, -DW + 0.14),  # brass face + rim rows 2-5
        (DR - 0.03, -DW + 0.16), (DR - 0.03, DW - 0.16),                        # glowing band row 6-7
        (DR + 0.03, DW - 0.14), (DR + 0.03, DW - 0.06), (DR, DW), (0.36, DW),     # rim + face rows 8-11
        (0.30, DW + 0.01), (0.26, DW + 0.03), (0.00, DW + 0.04)]
DRUM_Z = BODY_Z + R + DR - 0.10
DRUM_Y = 0.15


def drum_col(i, k, z):
    if i <= 1 or i >= 12:
        return GLOW_HI if i in (0, 14) else GLOW
    if i == 7:
        # goo band: lighter on top (local -x is world up for the X axis frame)
        a = (k + 0.5) / 16 * math.tau
        return mix(G_LO, G_HI, 0.5 - 0.5 * math.cos(a))
    a = (k + 0.5) / 16 * math.tau
    return mix(BR_LO, BR_HI, 0.5 - 0.5 * math.cos(a))


parts.append(lathe("Drum", DRUM, mat_at((0, DRUM_Y, DRUM_Z), "x"), segs=16, color_fn=drum_col))
# brass saddle under the drum
parts.append(rbox("Saddle", (0.46, 0.70, 0.30), (0, DRUM_Y, BODY_Z + R - 0.02), BR_LO, BR_HI, bev=0.07))

# pistol grip, trigger guard, trigger
parts.append(rbox("Grip", (0.42, 0.54, 1.12), (0, 0.86, 0.55), mix(WOOD_D, WOOD, 0.6), mix(WOOD, CREAM, 0.18), bev=0.11, rot=(-15, 0, 0)))
parts.append(tube("Guard", [(0, 0.05, 0.98), (0, 0.04, 0.62), (0, 0.32, 0.48), (0, 0.64, 0.52)],
                  [0.075] * 4, color=BRASS, segs=6))
parts.append(rbox("Trigger", (0.14, 0.14, 0.32), (0, 0.36, 0.76), ROOF, RED_HI, bev=0.03, rot=(20, 0, 0)))

# front handle under the barrel
parts.append(rbox("FrontGrip", (0.38, 0.40, 0.80), (0, -0.85, 0.78), mix(WOOD_D, WOOD, 0.6), mix(WOOD, CREAM, 0.18), bev=0.1, rot=(10, 0, 0)))

# wooden stock + red butt pad behind the barrel
parts.append(rbox("Stock", (0.50, 0.70, 0.80), (0, 1.50, BODY_Z - 0.18), mix(WOOD_D, WOOD, 0.6), mix(WOOD, CREAM, 0.18), bev=0.12, rot=(8, 0, 0)))
parts.append(rbox("Pad", (0.58, 0.18, 0.92), (0, 1.88, BODY_Z - 0.24), ROOF, RED_HI, bev=0.07, rot=(8, 0, 0)))

# live goo drooling off the bell lip
parts.append(blob("Drop", 0.16, (0, -2.02, BODY_Z - 0.62), mix(GLOW, GLOW_HI, 0.3), subdiv=2, squash=(1, 0.8, 1.4), jitter=0.0))
parts.append(blob("Drool", 0.13, (0, -2.03, BODY_Z - 0.47), GLOW, subdiv=2, squash=(1.2, 0.7, 1.2), jitter=0.0))

report_grip(parts, GRIP)
finish("pvp_goo_blaster_3", parts)
