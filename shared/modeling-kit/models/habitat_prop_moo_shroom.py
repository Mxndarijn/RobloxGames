# habitat_prop_moo_shroom: a small wooden feed trough on two legs, filled with red white-spotted mushrooms
# for the Moo Shroom slime.
import math, random
from lib import *
from models._habitat_prop import *

WOOD, WOOD_DK = P["ranch_wood"], P["ranch_wood_dark"]
RED_LO, RED_HI = rgb(206, 44, 48), rgb(246, 72, 66)
STEM = rgb(246, 234, 212)
SPOT = rgb(255, 250, 240)
R = random.Random(7)

TW, TD, TB, TH = 1.56, 0.72, 0.12, 0.44  # trough width, depth, bottom z, top z
T = 0.08  # board thickness
parts = []
# legs (X trestles at both ends)
for s in (-1, 1):
    parts.append(box(f"Leg{s}", (0.14, TD + 0.12, 0.14), (s * (TW / 2 - 0.16), 0, 0.07), WOOD_DK))
# floor and walls (front/back slope out a little)
parts.append(box("Floor", (TW - 0.1, TD - 0.1, T), (0, 0, TB + T / 2), WOOD_DK))
for s in (-1, 1):
    parts.append(box(f"Side{s}", (TW, T, TH - TB), (0, s * (TD / 2 - T / 2), (TB + TH) / 2), WOOD, rot=(s * -8, 0, 0)))
    parts.append(box(f"End{s}", (T, TD + 0.04, TH - TB + 0.06), (s * (TW / 2 - T / 2), 0, (TB + TH) / 2 + 0.03), WOOD_DK))
# plank seam on the front wall
parts.append(box("Seam", (TW - 0.2, 0.02, 0.025), (0, -(TD / 2) - 0.03, (TB + TH) / 2), shade(WOOD_DK, 0.85), rot=(8, 0, 0)))
# feed filling (hay-gold) just under the rim
parts.append(box("Feed", (TW - 0.18, TD - 0.14, 0.06), (0, 0, TH - 0.08), rgb(232, 196, 98)))


def mushroom(name, x, y, z, cap_r, stem_h, tilt=(0, 0)):
    out = []
    stem = lathe(name + "Stem", [(0, 0), (cap_r * 0.42, 0), (cap_r * 0.36, stem_h), (0, stem_h)], segs=8,
                 color_fn=lambda i, k, zz: STEM)
    cap = lathe(name + "Cap", [(0, stem_h - 0.04), (cap_r * 0.9, stem_h - 0.02), (cap_r, stem_h + 0.06),
                               (cap_r * 0.85, stem_h + cap_r * 0.5), (cap_r * 0.45, stem_h + cap_r * 0.78), (0, stem_h + cap_r * 0.84)],
                segs=12, color_fn=lambda i, k, zz: STEM if i == 0 else mix(RED_LO, RED_HI, min(1, i / 4)))
    out += [stem, cap]
    # white spots: small flattened domes on the cap's upper surface
    for j, (ang, el) in enumerate([(30, 0.55), (150, 0.55), (270, 0.5), (90, 0.85), (210, 0.9), (330, 0.85)][: 4 + (cap_r > 0.28) * 2]):
        a = math.radians(ang + R.uniform(-15, 15))
        rr = cap_r * (1.02 - el * 0.55)
        zz = stem_h + cap_r * (0.15 + el * 0.62)
        d = blob(name + f"Spot{j}", cap_r * 0.17, (math.cos(a) * rr, math.sin(a) * rr, zz), SPOT, subdiv=1, jitter=0, squash=(1, 1, 0.45))
        out.append(d)
    for o in out:
        xf(o, (x, y, z), (tilt[0], tilt[1], 0))
    return out


parts += mushroom("M0", -0.40, 0.02, TH - 0.1, 0.34, 0.30, (6, -10))
parts += mushroom("M1", 0.18, -0.04, TH - 0.1, 0.40, 0.42, (-4, 4))
parts += mushroom("M2", 0.58, 0.08, TH - 0.1, 0.24, 0.20, (-8, 16))

ship("habitat_prop_moo_shroom", parts)
