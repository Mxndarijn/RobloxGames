# bat_skin_foam_finger: Foam Finger Bat skin (Exclusive Shop, contract §10): a giant stadium foam "#1" hand.
# Red foam hand (rounded palm, curled finger roll, thumb folded across it, tall pointing index finger) on a
# ribbed foam grip with a butter pommel knob and a butter cuff. A raised butter "#1" sits on the palm front and,
# bigger, on the back of the hand (the side a player's camera sees from behind), mirrored so it reads there.
# Frame = ranch_bat (models/_bat_skin.py): z 0..5.09, grip z = 1.2.
from models._bat_skin import *

FOAM = mix(RED, PINK, 0.2)
FOAM_LO = mix(FOAM, RED, 0.25)
FOAM_HI = mix(FOAM, PINK, 0.35)
TEXT = mix(BUTTER, CREAM, 0.25)
PALM = (1.5, 0.62, 1.62)  # palm block size (X, Y, Z)
PALM_Z = 2.2  # palm bottom
TIP = HEIGHT  # index finger tip


def foam_col(lo, hi):
    def col(i, k, c):
        return mix(FOAM_LO, FOAM_HI, min(1, max(0, (c.z - lo) / (hi - lo))))
    return col


def grip():
    prof = [(0.0, 0.0), (0.32, 0.0), (0.42, 0.14), (0.44, 0.36), (0.33, 0.58),  # butter pommel knob
            (0.28, 0.7), (0.28, 0.8), (0.3, 0.86), (0.3, 1.74), (0.28, 1.8),  # ribbed foam grip
            (0.36, 1.86), (0.4, 2.0), (0.44, 2.12), (0.4, 2.3), (0.0, 2.35)]  # butter cuff into the palm

    def col(i, k, c):
        if c.z < 0.64 or 1.84 < c.z:
            return mix(mix(BUTTER, WOOD, 0.2), BUTTER, min(1, c.z / 0.6) if c.z < 0.64 else 1)
        return FOAM if (int(c.z * 7)) % 2 else FOAM_LO  # ribs
    return lathe("Grip", prof, col, segs=8)


def hand():
    pz = PALM_Z + PALM[2] / 2
    palm = rbox("Palm", PALM, foam_col(PALM_Z, PALM_Z + PALM[2]), pos=(0, 0, pz), bevel_w=0.22, segments=2)
    top = PALM_Z + PALM[2]
    index = lathe("Index", [(0.0, top - 0.25), (0.26, top - 0.2), (0.32, top), (0.32, TIP - 0.4),
                            (0.27, TIP - 0.15), (0.15, TIP - 0.03), (0.0, TIP)],
                  foam_col(top, TIP), segs=10, M=place((0.38, 0.0, 0)))
    # curled fingers: one roll across the front top of the palm (axis X), with knuckle dents
    roll = lathe("Fingers", [(0.0, -0.05), (0.18, -0.02), (0.25, 0.1), (0.25, 0.25), (0.21, 0.31),
                             (0.25, 0.37), (0.25, 0.52), (0.21, 0.58), (0.25, 0.64), (0.25, 0.8),
                             (0.18, 0.92), (0.0, 0.95)],
                 lambda i, k, c: FOAM if c.y < -0.3 else FOAM_LO, segs=8,
                 M=place((-0.7, -0.2, top - 0.22), (0, 90, 0)))
    thumb = lathe("Thumb", [(0.0, 0.0), (0.16, 0.03), (0.21, 0.15), (0.21, 0.6), (0.15, 0.74), (0.0, 0.78)],
                  lambda i, k, c: FOAM_HI if c.z > top - 0.6 else FOAM, segs=8,
                  M=place((-0.72, -0.36, top - 0.72), (0, 72, 0)))
    return [palm, index, roll, thumb]


def glyphs(x0, z0, h, y, mirror, name):
    """Raised "#1" (slabs in the XZ plane), lower-left corner (x0, z0), height h, on the face at y."""
    w = h * 0.12  # stroke
    t = 0.09
    s = -1 if mirror else 1

    def bar(n, pts):
        return slab("%s%s" % (name, n), [(s * (x0 + x), z0 + z) for x, z in (pts if not mirror else pts[::-1])],
                    t, TEXT, y=y)

    g = h * 0.62  # "#" width
    out = [
        bar("H1", [(0.0, h * 0.3), (g, h * 0.3), (g, h * 0.3 + w), (0.0, h * 0.3 + w)]),
        bar("H2", [(0.0, h * 0.62), (g, h * 0.62), (g, h * 0.62 + w), (0.0, h * 0.62 + w)]),
        bar("V1", [(g * 0.18, 0.0), (g * 0.18 + w, 0.0), (g * 0.38 + w, h), (g * 0.38, h)]),
        bar("V2", [(g * 0.6, 0.0), (g * 0.6 + w, 0.0), (g * 0.8 + w, h), (g * 0.8, h)]),
    ]
    one = g + h * 0.16
    out += [
        bar("1S", [(one + h * 0.14, 0.0), (one + h * 0.14 + w * 1.2, 0.0), (one + h * 0.14 + w * 1.2, h),
                   (one + h * 0.14, h)]),
        bar("1F", [(one, h * 0.72), (one + h * 0.14, h * 0.86), (one + h * 0.14, h), (one, h * 0.86)]),
        bar("1B", [(one, 0.0), (one + h * 0.42, 0.0), (one + h * 0.42, w), (one, w)]),
    ]
    return out


def text():
    front_y, back_y = -PALM[1] / 2 - 0.03, PALM[1] / 2 + 0.03
    hf, hb = 0.62, 0.95
    wf, wb = hf * 1.2, hb * 1.2  # "#1" total width ~ 1.2 h
    return glyphs(-wf / 2 + 0.08, PALM_Z + 0.2, hf, front_y, False, "F") \
        + glyphs(-wb / 2, PALM_Z + 0.33, hb, back_y, True, "B")


h_parts = hand() + text()
lo, hi = bounds(h_parts)
for o in h_parts:  # centre the hand's depth on the grip axis (the finger roll and thumb sit in front)
    o.location.y -= (lo.y + hi.y) / 2
ship_skin("bat_skin_foam_finger", [grip()] + h_parts)
