# habitat_prop_djinn: a gold magic lamp on a stack of two plump cushions (magenta and turquoise) with gold tassels.
import math
from models._habitat_prop5 import *
from models._habitat_prop4 import lathe, torus, paint, move

MAG, MAG_HI = rgb(236, 70, 170), rgb(255, 130, 210)
TEAL, TEAL_HI = rgb(40, 200, 210), rgb(120, 236, 236)
GOLD, GOLD_LO, GOLD_HI = rgb(255, 200, 64), rgb(244, 164, 40), rgb(255, 238, 150)
PURPLE = rgb(170, 110, 255)


def cushion(name, w, d, h, z, lo, hi, rz=0):
    o = blob(name, 0.5, (0, 0, 0), lo, subdiv=2, jitter=0)
    for v in o.data.vertices:  # near-flat bottom, pillowy top
        v.co.z = max(v.co.z, -0.3)
    move(o, scale=(w, d, h / 0.8))
    move(o, pos=(0, 0, z + 0.3 * h / 0.8), rot=(0, 0, rz))
    paint(o, lambda c, n: hi if n.z > 0.5 else lo)
    return o


parts = []
parts.append(cushion("Low", 1.3, 0.95, 0.36, 0.0, MAG, MAG_HI))
parts.append(cushion("Up", 0.98, 0.74, 0.3, 0.3, TEAL, TEAL_HI, rz=8))
# gold tassels on the bottom cushion's corners, laid on the deck pointing out
for k, (sx, sy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
    x, y = sx * 0.5, sy * 0.3
    parts.append(rod(f"Tas{k}", (x, y, 0.06), (x + sx * 0.12, y + sy * 0.06, 0.03), 0.035, GOLD, segs=5))
    parts.append(blob(f"Knot{k}", 0.05, (x, y, 0.07), GOLD_HI, subdiv=1, jitter=0))
# the lamp: squat gold belly, long spout to +X, curled handle to -X, lid with a purple gem
Z = 0.6
lamp = lathe("Lamp", [(0.1, Z), (0.18, Z + 0.04), (0.22, Z + 0.12), (0.17, Z + 0.2), (0.08, Z + 0.24)], segs=12,
             squash=(1.25, 0.9, 1))
parts.append(gradient(lamp, GOLD_LO, GOLD_HI))
parts.append(gcyl("Foot", 0.12, 0.05, (0, 0, Z - 0.04), GOLD_LO, segs=10))
parts.append(gradient(tube("Spout", [(0.22, 0, Z + 0.1), (0.36, 0, Z + 0.13), (0.46, 0, Z + 0.22), (0.52, 0, Z + 0.3)],
                           [0.07, 0.05, 0.035, 0.03], GOLD, segs=6), GOLD, GOLD_HI))
parts.append(torus("Handle", 0.09, 0.025, seg=10, seg2=4, rot=(90, 0, 0), pos=(-0.3, 0, Z + 0.14), color=GOLD,
                   arc=(1.6, 4.7)))
parts.append(gcyl("Lid", 0.1, 0.06, (0, 0, Z + 0.23), GOLD, GOLD_HI, segs=10, r_top=0.05))
parts.append(blob("Gem", 0.055, (0, 0, Z + 0.33), PURPLE, subdiv=1, jitter=0))
parts.append(torus("Band", 0.19, 0.02, seg=12, seg2=4, pos=(0, 0, Z + 0.12), color=PURPLE))
ship("habitat_prop_djinn", parts)
