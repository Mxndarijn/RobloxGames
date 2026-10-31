# habitat_prop_mushie: a cluster of tiny red spotted mushrooms; the biggest one is shy (closed eyes, pink blush)
# and the little ones lean in behind it.
import math
from lib import *
from models._habitat_prop2 import *

CAP, CAP_D = rgb(236, 64, 60), rgb(200, 44, 52)
STEM = rgb(252, 238, 214)
BLUSH = rgb(255, 150, 170)
GRASS = rgb(110, 196, 84)


def shroom(i, x, y, h, r, lean=(0, 0)):
    """Stem + domed cap + white spots. lean tilts the whole mushroom (deg about X, Y)."""
    out = [lathe(f"Stem{i}", [(r * 0.42, 0), (r * 0.36, h * 0.6), (r * 0.32, h), (0, h)], segs=8, col=STEM)]
    cap = lathe(f"Cap{i}", [(0, h - r * 0.05), (r * 0.9, h - r * 0.05), (r, h + r * 0.12), (r * 0.82, h + r * 0.42),
                            (r * 0.45, h + r * 0.62), (0, h + r * 0.68)], segs=10,
                col=lambda c, ii, k: CAP_D if c.z < h + r * 0.05 else CAP)
    out.append(cap)
    ns = 5 if r > 0.25 else 3
    for k in range(ns):
        a = k * math.tau / ns + i
        rr = r * (0.55 if k % 2 else 0.75)
        z = h + r * (0.56 if k % 2 else 0.32)
        out.append(blob(f"Spot{i}_{k}", r * 0.13, (math.cos(a) * rr, math.sin(a) * rr, z), WHITE, subdiv=1,
                        squash=(1, 1, 0.5), jitter=0))
    out.append(blob(f"SpotTop{i}", r * 0.15, (0, 0, h + r * 0.68), WHITE, subdiv=1, squash=(1, 1, 0.4), jitter=0))
    for o in out:
        move(o, (x, y, 0), (lean[0], lean[1], 0))
    return out


parts = []
parts += shroom(0, 0.0, -0.05, 0.42, 0.42)                     # the shy one, front centre
parts += shroom(1, -0.5, 0.18, 0.28, 0.28, lean=(6, -14))       # peeking from behind, left
parts += shroom(2, 0.48, 0.2, 0.34, 0.3, lean=(8, 12))          # right
parts += shroom(3, 0.72, -0.18, 0.14, 0.17, lean=(0, 18))       # tiny ones
parts += shroom(4, -0.74, -0.2, 0.12, 0.15, lean=(-4, -16))
# shy face on the big stem: closed-eye arcs (little tubes) and blush
for s in (-1, 1):
    pts = [(s * 0.06 + s * dx, -0.05 - 0.17, 0.27 + dz) for dx, dz in ((-0.03, -0.01), (0, 0.012), (0.03, -0.01))]
    parts.append(tube(f"EyeLid{s}", pts, [0.012] * 3, BLACK, segs=4))
    parts.append(blob(f"Blush{s}", 0.035, (s * 0.115, -0.05 - 0.155, 0.22), BLUSH, subdiv=1, squash=(1.5, 0.4, 0.8), jitter=0))
# grass tufts at the base
for j, (x, y) in enumerate([(-0.25, -0.25), (0.27, -0.28), (0.0, 0.25), (-0.85, 0.05), (0.85, 0.08)]):
    for b in (-1, 0, 1):
        parts.append(move(cone(f"Grass{j}{b}", 0.035, 0.17 - abs(b) * 0.04, (0, 0, 0), GRASS, segs=3), (x + b * 0.04, y, 0), (0, b * 25, 0)))
ship("habitat_prop_mushie", parts)
