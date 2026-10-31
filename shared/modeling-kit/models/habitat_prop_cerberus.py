# habitat_prop_cerberus: signature prop for Cerberus: a big red dog bowl full of kibble with a cartoon bone resting
# across it and a red spiked collar (gold studs, gold name tag) leaning on its right side. Cute, not scary.
# Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

BOWL, BOWL_D, BOWL_HI = rgb(236, 70, 96), rgb(222, 64, 92), rgb(255, 130, 150)
KIBBLE, KIBBLE_HI = rgb(196, 120, 70), rgb(226, 160, 96)
BONE, BONE_LO = rgb(255, 250, 236), rgb(236, 224, 204)
COLLAR, COLLAR_D, GOLD = rgb(240, 56, 76), rgb(222, 52, 76), rgb(255, 210, 70)

parts = []
BX = -0.22
bowl = lathe("Bowl", [(0.0, 0.0), (0.4, 0.0), (0.5, 0.24), (0.53, 0.29), (0.46, 0.3), (0.38, 0.14), (0.0, 0.14)], segs=18, pos=(BX, 0.02, 0))
paint(bowl, lambda c, n: BOWL_HI if c.z > 0.26 else (BOWL_D if c.z < 0.06 else BOWL))
parts.append(bowl)
# white paw print on the bowl front
paw = [blob("Pad", 0.085, (BX, -0.47, 0.1), BONE, subdiv=1, jitter=0, squash=(1.2, 0.4, 0.9))]
for k, (dx, dz) in enumerate(((-0.1, 0.07), (-0.035, 0.115), (0.035, 0.115), (0.1, 0.07))):
    paw.append(blob(f"Toe{k}", 0.036, (BX + dx, -0.47 + abs(dx) * 0.25, 0.11 + dz), BONE, subdiv=1, jitter=0, squash=(1, 0.5, 1)))
for o in paw:
    move(o, (0, 0, 0), (-14, 0, 0))
parts += paw
# kibble heap
for i in range(16):
    a = i * 2.4
    rr = 0.33 * math.sqrt((i + 0.5) / 16)
    z = 0.2 + 0.06 * (1 - rr / 0.33)
    parts.append(blob(f"Kib{i}", 0.065, (BX + math.cos(a) * rr, 0.02 + math.sin(a) * rr * 0.9, z), KIBBLE_HI if i % 3 == 0 else KIBBLE,
                      subdiv=1, jitter=0.08, seed=i, squash=(1, 1, 0.75)))
# bone resting across the bowl, rising toward the back-left
bone = [cylinder("Shaft", 0.06, 0.62, (0, 0, -0.31), BONE, segs=8)]
for s in (-1, 1):
    for t in (-1, 1):
        bone.append(blob(f"Knob{s}{t}", 0.085, (t * 0.06, 0, s * 0.33), BONE, subdiv=2, jitter=0))
for o in bone:
    move(o, (BX + 0.02, -0.08, 0.42), (0, 62, 18))
    gradient(o, BONE_LO, BONE)
parts += bone
# spiked collar leaning on the bowl's right side
CR, CXp = 0.27, 0.55
col = [torus("Collar", CR, 0.065, seg=18, seg2=5, rot=(90, 0, 0), pos=(0, 0, 0), color=COLLAR)]
paint(col[0], lambda c, n: COLLAR if n.y < 0.3 else COLLAR_D)
for k in range(7):
    a = math.radians(30 + k * 20)
    col.append(cone(f"Spike{k}", 0.045, 0.1, (math.cos(a) * (CR + 0.04), 0, math.sin(a) * (CR + 0.04)), GOLD, segs=5,
                    rot=(0, 90 - math.degrees(a), 0)))
col.append(box("Buckle", (0.1, 0.06, 0.12), (0, -0.01, -CR), GOLD))
tag = cylinder("Tag", 0.075, 0.03, (0.0, -0.05, -CR + 0.13), GOLD, segs=8, rot=(90, 0, 0))
col.append(tag)
for o in col:
    move(o, (CXp, 0.05, CR + 0.07), (0, -14, 0))
parts += [floor(o) for o in col]
prop_finish("habitat_prop_cerberus", parts)
