# habitat_prop_truffle: a fancy black top hat with a red band, and a black cane with a gold knob leaning on it.
import math
from lib import *
from models._habitat_prop2 import *

HAT, HAT_HI = rgb(64, 58, 72), rgb(96, 88, 108)  # lifted blacks: true black goes to a hole in game
BAND = rgb(214, 46, 62)

parts = [lathe("Brim", [(0.0, 0.0), (0.5, 0.0), (0.54, 0.04), (0.52, 0.07), (0.0, 0.07)], segs=16, col=HAT, sy=0.92),
         lathe("Crown", [(0.33, 0.06), (0.31, 0.2), (0.32, 0.62), (0.35, 0.72), (0.0, 0.74)], segs=14,
               col=lambda c, i, k: HAT_HI if c.z > 0.73 else HAT, sy=0.92),
         lathe("Band", [(0.325, 0.12), (0.34, 0.12), (0.34, 0.24), (0.325, 0.24)], segs=14, col=BAND, sy=0.92)]
# a gold buckle on the band front
parts.append(box("Buckle", (0.12, 0.03, 0.1), (0.0, -0.32, 0.18), GOLD))
parts.append(box("BuckleIn", (0.06, 0.035, 0.05), (0.0, -0.325, 0.18), BAND))
# cane: shaft from the floor at front-right leaning onto the hat side, crooked handle on top, gold knob tip
foot = (0.82, -0.12, 0.0)
top = (0.42, -0.02, 0.96)
d = [top[i] - foot[i] for i in range(3)]
shaft = [tuple(foot[i] + d[i] * t for i in range(3)) for t in (0, 0.5, 1.0)]
parts.append(tube("Shaft", shaft, [0.04, 0.04, 0.04], HAT, segs=6))
parts.append(cylinder("Ferrule", 0.045, 0.06, foot, GOLD, segs=6))
# crook: half circle going over to -x and down
crook = []
for j in range(7):
    a = math.pi * j / 6
    crook.append((top[0] - 0.13 + math.cos(a) * 0.13, top[1], top[2] + math.sin(a) * 0.13))
parts.append(tube("Crook", crook, [0.04] * 6 + [0.045], HAT, segs=6))
parts.append(blob("Knob", 0.055, crook[-1], GOLD, subdiv=1, jitter=0))
parts.append(lathe("CrookRing", [(0.048, -0.03), (0.048, 0.03)], pos=(0, 0, 0), segs=6, col=GOLD))
move(parts[-1], top, (0, -22, 0))
ship("habitat_prop_truffle", parts)
