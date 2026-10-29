# Lock stopper style "Sleepy guard": jar 1's door as a big slime guard squashed into the round doorway, fast asleep
# on duty: closed eyes, blush, a little snore mouth with a goo bubble, and a red-and-cream striped nightcap over the
# top whose floppy tip hangs down the opening side (the cap is the red lock signal). Same box as goo_jar_stopper.
from models._lock_stopper import *

GOO = PALETTE["ranch_goo"]
GOO_HI = PALETTE["ranch_goo_hi"]
GOO_D = mix(GOO, PALETTE["ranch_field_dark"], 0.55)
CREAM = PALETTE["ranch_cream"]
PINK = PALETTE["ranch_pink"]
INK = rgb(70, 52, 50)
segs = 36
CAP_A0, CAP_A1, CAP_R = 30.0, 150.0, 2.95  # the cap covers the top band of the face: angles and inner radius


def depth(r):
    return 0.7 + 0.45 * (1 - (r / R) ** 2)  # a soft belly bulge toward -Y


def front_y(x, z, lift=0.0):
    r = math.hypot(x, z - CZ)
    return -0.05 - depth(r) - lift


def body_col(r, a, i, j):
    deg = math.degrees(a) % 360
    z = CZ + r * math.sin(a)
    if r >= CAP_R and CAP_A0 <= deg <= CAP_A1:
        return RED if (j // 2) % 2 == 0 else CREAM
    t = max(0.0, min(1.0, z / (2 * R)))
    return mix(GOO_D, GOO, min(1.0, t * 1.6))  # dark below, light above


slime = plug("Slime", [0.9, 1.8, 2.45, CAP_R, 3.6, 4.15, R], segs, depth, body_col, back_y=-0.05, back_col=GOO)
# the cap is a soft volume on the head, not paint: push its front verts out, most in the middle of the band
for v in slime.data.vertices:
    x, y, z = v.co
    r, deg = math.hypot(x, z - CZ), math.degrees(math.atan2(z - CZ, x)) % 360
    if y < -0.1 and r >= CAP_R - 0.01 and CAP_A0 - 0.1 <= deg <= CAP_A1 + 0.1:
        band = math.sin(math.pi * min(1.0, (r - CAP_R) / (R - CAP_R + 1e-6)))
        v.co.y -= 0.12 + 0.3 * band
parts = [slime]

# the cap's fluffy cream brim along its lower edge
parts.append(torus("Brim", CAP_R, 0.36, (0, front_y(0, CZ + CAP_R) - 0.1, CZ), CREAM, segs=18, sides=6,
                   arc=(CAP_A0 - 6, CAP_A1 + 6), squash=0.8))
# the floppy tip: from the cap's top right, over the rim and down the opening side, to a cream pompom
tip = [(2.2, -0.95, CZ + 3.55), (3.4, -0.8, CZ + 2.6), (3.95, -0.7, CZ + 1.3), (3.85, -0.7, CZ + 0.2)]
cap_tip = tube("CapTip", tip, [0.7, 0.55, 0.38, 0.2], RED, segs=8)
gradient(cap_tip, shade(RED, 0.85), RED_HI)
parts.append(cap_tip)
parts.append(painted(blob("Pompom", 0.55, (3.85, -0.75, CZ - 0.2), CREAM, subdiv=2, jitter=0.06, seed=3), shade(CREAM, 0.88), CREAM))

# the face: closed sleepy eyes (drooping arcs), blush, a small round snore mouth with a goo bubble
for k, ex in enumerate((-1.45, 1.45)):
    ez = CZ + 0.75
    pts = []
    for m in range(7):
        t = m / 6
        x = ex - 0.65 + 1.3 * t
        z = ez - 0.32 * math.sin(t * math.pi)
        pts.append((x, front_y(x, z) - 0.02, z))
    parts.append(tube(f"Eye{k}", pts, [0.13] * len(pts), INK, segs=6))
    cx, cz = ex * 1.45, CZ - 0.15
    parts.append(blob(f"Cheek{k}", 0.48, (cx, front_y(cx, cz) + 0.12, cz), PINK, subdiv=2, squash=(1.2, 0.3, 0.75), jitter=0))
parts.append(blob("Mouth", 0.32, (0.15, front_y(0.15, CZ - 0.85) + 0.08, CZ - 0.85), INK, subdiv=2, squash=(0.9, 0.3, 1.1), jitter=0))
# a little "Zz" floating off the hinge side, cream boxes on the face
def zed(name, x, z, h):
    y = front_y(x, z) - 0.06
    w, t = h * 0.85, h * 0.2
    diag = math.hypot(w - t, h - t)
    ang = math.degrees(math.atan2(h - t, w - t))
    return [box(name + "T", (w, 0.14, t), (x, y, z + (h - t) / 2), CREAM),
            box(name + "B", (w, 0.14, t), (x, y, z - (h - t) / 2), CREAM),
            box(name + "D", (diag, 0.12, t * 0.9), (x, y, z), CREAM, rot=(0, -ang, 0))]


parts += zed("Z0", -2.3, CZ - 1.8, 0.9) + zed("Z1", -3.15, CZ - 0.85, 0.62)
# a glossy slime highlight on the brow
parts.append(blob("Gloss", 0.4, (-2.2, front_y(-2.2, CZ + 1.9) + 0.06, CZ + 1.9), GOO_HI, subdiv=2, squash=(1.4, 0.25, 0.7), jitter=0))

parts += hinges(PALETTE["ranch_metal"], t=0.85, reach=3.0)
ship("lock_stopper_sleepy", fit_to_classic(parts))
