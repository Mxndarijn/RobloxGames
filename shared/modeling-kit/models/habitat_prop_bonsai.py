# habitat_prop_bonsai: a little stone lantern (toro) on an oval patch of raked white gravel with a mossy rock.
# Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

STONE, STONE_D, STONE_HI = rgb(178, 176, 170), rgb(140, 138, 134), rgb(214, 212, 204)
GRAVEL, RAKE = rgb(238, 232, 214), rgb(204, 194, 170)
GLOW, GLOW_HI = rgb(255, 196, 70), rgb(255, 240, 150)
MOSS, ROCK = rgb(110, 196, 84), rgb(160, 150, 140)
LX, LY = 0.15, 0.04  # lantern foot
parts = [lathe("Gravel", [(0, 0), (0.9, 0), (0.88, 0.04), (0, 0.04)], segs=24, squash=(1, 0.6, 1), color=GRAVEL)]
# raked rings round the lantern + straight rake lines along the front
for k, r in enumerate((0.36, 0.48)):
    parts.append(move(torus(f"RakeRing{k}", r, 0.016, seg=22, seg2=3, color=RAKE), (LX, LY, 0.04), scale=(1, 0.62, 1)))
for k in range(2):
    y = -0.4 - k * 0.07
    hw = math.sqrt(max(0.0, 1 - (y / 0.54) ** 2)) * 0.85
    parts.append(tube(f"Line{k}", [(-hw, y, 0.04), (hw, y, 0.04)], [0.016, 0.016], RAKE, segs=3))


def hexp(name, r, h, z, col, hi=None, r_top=None, segs=6):
    o = cylinder(name, r, h, (LX, LY, z), col, segs=segs, r_top=r_top)
    if hi:
        gradient(o, col, hi)
    return o


parts.append(hexp("Base", 0.24, 0.1, 0.04, STONE_D, STONE))
parts.append(hexp("Base2", 0.17, 0.06, 0.14, STONE))
parts.append(hexp("Pillar", 0.085, 0.36, 0.2, STONE, STONE_HI, r_top=0.075, segs=8))
parts.append(hexp("Plat", 0.2, 0.08, 0.56, STONE_D, STONE, r_top=0.23))
parts.append(box("Fire", (0.26, 0.26, 0.22), (LX, LY, 0.75), STONE))
for k, (dx, dy) in enumerate(((0, -0.13), (0.13, 0), (-0.13, 0))):
    size = (0.13, 0.03, 0.13) if dx == 0 else (0.03, 0.13, 0.13)
    w = box(f"Win{k}", size, (LX + dx, LY + dy, 0.76), GLOW)
    paint(w, lambda c, n: GLOW_HI if c.z > 0.77 else GLOW)
    parts.append(w)
roof = lathe("Roof", [(0, 0.85), (0.34, 0.85), (0.37, 0.9), (0.2, 1.0), (0.06, 1.06), (0, 1.06)], segs=6, pos=(LX, LY, 0),
             phase=math.pi / 6)
gradient(roof, STONE_D, STONE_HI)
parts.append(roof)
parts.append(hexp("Neck", 0.05, 0.05, 1.05, STONE))
parts.append(lathe("Finial", [(0, 0), (0.07, 0.03), (0.08, 0.08), (0.04, 0.15), (0, 0.18)], segs=8, pos=(LX, LY, 1.09),
                   color=STONE_HI))
# mossy rock on the left
rock = blob("Rock", 0.2, (-0.55, 0.05, 0.06), ROCK, subdiv=2, squash=(1.3, 1.0, 0.8), jitter=0.12, seed=4)
paint(rock, lambda c, n: MOSS if n.z > 0.55 else ROCK)
parts.append(floor(rock, 0.02))
prop_finish("habitat_prop_bonsai", parts)
