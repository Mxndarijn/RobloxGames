# habitat_prop_queen_jelly: signature prop for Queen Jelly: a little pearl throne: a ribbed pink clam shell seat
# with the upper shell standing open as the backrest, a big pearl on the seat, gold hinge. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

PINK, PINK_HI, PINK_D = rgb(255, 150, 196), rgb(255, 206, 228), rgb(226, 112, 170)
PEARL, PEARL_HI = rgb(236, 228, 250), rgb(255, 252, 255)
GOLD = rgb(255, 200, 70)
CORAL = rgb(250, 120, 140)


def shell_col(par, u):
    base = PINK_HI if par else PINK
    return mix(PINK_D, base, min(1, 0.45 + u))


parts = []
hy = 0.32  # hinge line (back)
seat = scallop("Seat", 0.68, spread=150, ribs=7, cup=0.16, thick=0.06, color_fn=shell_col)
move(seat, (0, hy, 0.22), (0, 0, 180))
back = scallop("Back", 0.82, spread=150, ribs=7, cup=0.16, thick=0.06, color_fn=shell_col)
move(back, (0, hy + 0.02, 0.2), (78, 0, 0))
parts += [seat, back]
# coral foot under the seat + gold hinge bar
foot = cylinder("Foot", 0.3, 0.18, (0, 0.02, 0), CORAL, segs=10, r_top=0.2)
gradient(foot, shade(CORAL, 0.85), CORAL)
parts.append(foot)
parts.append(cylinder("Hinge", 0.06, 0.34, rot=(0, 90, 0), pos=(-0.17, hy, 0.2), segs=8, color=GOLD))
# the pearl on the seat, a small one on the backrest's top
pearl = blob("Pearl", 0.2, (0, 0.0, 0.43), PEARL, subdiv=2, jitter=0)
paint(pearl, lambda c, n: PEARL_HI if n.z > 0.4 and n.x < 0.2 else PEARL)
parts.append(pearl)
top = max((v.co for v in back.data.vertices if abs(v.co.x) < 0.12), key=lambda c: c.z)  # backrest's top rib
parts.append(blob("Crest", 0.085, (0, top.y - 0.02, top.z + 0.03), PEARL_HI, subdiv=1, jitter=0))
prop_finish("habitat_prop_queen_jelly", parts)
