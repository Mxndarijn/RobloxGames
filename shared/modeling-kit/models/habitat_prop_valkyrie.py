# habitat_prop_valkyrie: a round blue-and-gold shield and a gold-banded horn resting against a rune stone.
import math
from models._habitat_prop5 import *
from models._habitat_prop4 import lathe, torus, paint, move

STONE, STONE_HI = rgb(160, 172, 196), rgb(206, 216, 236)
RUNE = rgb(110, 210, 255)
BLUE, BLUE_HI = rgb(60, 150, 245), rgb(120, 196, 255)
GOLD, GOLD_HI = rgb(255, 200, 64), rgb(255, 236, 150)
RED = rgb(236, 64, 72)
IVORY, IVORY_HI = rgb(250, 236, 206), rgb(255, 250, 236)

parts = []
# rune stone: rounded-top slab behind
out = [(-0.44, 0), (0.44, 0)] + [(0.44 * math.cos(a), 0.86 + 0.48 * math.sin(a)) for a in [k * math.pi / 10 for k in range(11)]]
parts.append(slab("Stone", out, 0.26, STONE, (0.12, 0.3, 0), hi=STONE_HI))
# glowing rune high on the stone, above the shield
for k, ((x0, z0), (x1, z1)) in enumerate((((0.0, 1.24), (0.0, 0.98)), ((0.0, 1.18), (0.12, 1.26)), ((0.0, 1.1), (0.12, 1.18)))):
    parts.append(rod(f"Rune{k}", (x0 + 0.12, 0.16, z0), (x1 + 0.12, 0.16, z1), 0.028, RUNE, segs=4))
# shield leaning back against the stone
SC = (-0.1, -0.02, 0.44)
disc = gcyl("Disc", 0.42, 0.06, (0, 0, -0.03), BLUE, segs=16)
paint(disc, lambda c, n: BLUE_HI if (int((math.atan2(c.y, c.x) + math.pi) / (math.pi / 3)) % 2) else BLUE)
rim = torus("Rim", 0.42, 0.04, seg=16, seg2=4, color=GOLD)
boss = blob("Boss", 0.1, (0, 0, -0.05), GOLD_HI, subdiv=1, jitter=0, squash=(1, 1, 0.7))
crossA = box("CrossA", (0.76, 0.07, 0.03), (0, 0, -0.04), RED)
crossB = box("CrossB", (0.07, 0.76, 0.03), (0, 0, -0.04), RED)
for p in (disc, rim, crossA, crossB, boss):
    move(p, rot=(-90 + 18, 0, 0))
    move(p, pos=SC)
    parts.append(p)
# horn lying on the ground front-right, curling up toward the bell
pts, rad = [], []
for i in range(7):
    t = i / 6
    a = math.radians(-60 + 150 * t)
    pts.append((0.42 + 0.3 * math.cos(a), -0.3 + 0.08 * t, 0.05 + 0.34 * (math.sin(a) + 0.87)))
    rad.append(0.025 + 0.12 * t ** 1.4)
parts.append(gradient(tube("Horn", pts, rad, IVORY, segs=8, twist_free=True), IVORY, IVORY_HI))
for k, i in enumerate((1, 3)):
    parts.append(tube(f"HB{k}", [pts[i], pts[i + 1]], [rad[i] + 0.015, rad[i + 1] + 0.015], GOLD, segs=8))
ship("habitat_prop_valkyrie", parts)
