# habitat_prop_venus: a terracotta pot with a cluster of four open flytraps (green jaws, pink insides, pale teeth)
# on curving stalks. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

POT, POT_D, POT_HI = rgb(222, 112, 62), rgb(186, 84, 50), rgb(240, 146, 90)
SOIL = rgb(140, 94, 62)
GREEN, GREEN_D, GREEN_HI = rgb(96, 196, 70), rgb(66, 156, 58), rgb(150, 224, 90)
PINK, TOOTH = rgb(240, 70, 100), rgb(236, 252, 190)
parts = []
pot = lathe("Pot", [(0, 0), (0.25, 0), (0.33, 0.34), (0, 0.34)], segs=14)
gradient(pot, POT_D, POT)
parts.append(pot)
rim = lathe("Rim", [(0, 0.3), (0.38, 0.3), (0.39, 0.42), (0.34, 0.43), (0, 0.41)], segs=14)
paint(rim, lambda c, n: SOIL if n.z > 0.9 and math.hypot(c.x, c.y) < 0.3 else POT_HI)
parts.append(rim)


def trap(i, base, top, yaw, s, open_up=48, open_dn=112):
    """Stalk from base to top, then a head of two half-disc jaws hinged at the back, opening toward -Y."""
    mid = ((base[0] + top[0]) / 2, (base[1] + top[1]) / 2 + 0.03, (base[2] + top[2]) / 2)
    out = [tube(f"Stalk{i}", [base, mid, top], [0.035 * s, 0.03 * s, 0.028 * s], GREEN_D, segs=5)]
    for j, (a, inner) in enumerate(((open_up, -1), (open_dn, 1))):
        n = 9
        pts = [(0.2 * math.cos(math.pi * k / n), 0.17 * math.sin(math.pi * k / n)) for k in range(n + 1)]
        jaw = slab(f"Jaw{i}{j}", pts, 0.035)
        teeth = []
        for k in range(1, n):
            th = math.pi * k / n
            teeth.append(cone(f"T{i}{j}{k}", 0.018, 0.08, (0.2 * math.cos(th), 0, 0.17 * math.sin(th)), TOOTH, segs=3,
                              rot=(0, 90 - math.degrees(th), 0)))
        for o in [jaw] + teeth:
            move(o, rot=(a, 0, 0))
            move(o, top, (0, 0, yaw), (s, s, s))
        paint(jaw, lambda c, n_, inner=inner: PINK if n_.z * inner > 0.25 else (GREEN_HI if inner < 0 else GREEN))
        out += [jaw] + teeth
    return out


parts += trap(0, (0.0, 0.02, 0.38), (0.0, -0.06, 1.0), 0, 1.25)
parts += trap(1, (-0.12, 0.05, 0.38), (-0.42, -0.02, 0.78), 35, 1.0)
parts += trap(2, (0.12, 0.05, 0.38), (0.44, 0.0, 0.72), -35, 1.0)
parts += trap(3, (0.05, 0.12, 0.38), (0.2, 0.2, 0.92), -15, 0.85)
# leaves at the soil
for k, (yaw, l) in enumerate(((150, 0.42), (30, 0.4), (-90, 0.3))):
    leaf = slab(f"Leaf{k}", [(0, 0), (l * 0.5, 0.07), (l, 0.0), (l * 0.5, -0.05)], 0.03, color=GREEN)
    move(leaf, rot=(90, -25, 0))
    move(leaf, (0, 0.04, 0.4), (0, 0, yaw))
    parts.append(leaf)
prop_finish("habitat_prop_venus", parts)
