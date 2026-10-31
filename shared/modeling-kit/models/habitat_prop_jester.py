# habitat_prop_jester: a red/yellow striped circus drum pedestal with gold rims, a big blue ball on top and three
# juggling pins (two on the drum, one leaning against it). Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

RED, YEL, PURP = rgb(232, 52, 70), rgb(255, 210, 60), rgb(150, 92, 230)
GOLD, WHITE_, BLUE = rgb(255, 204, 70), rgb(250, 248, 240), rgb(60, 150, 255)
R, H = 0.44, 0.5
parts = []
drum = lathe("Drum", [(0, 0), (R, 0), (R, H), (0, H)], segs=16)
paint(drum, lambda c, n: PURP if n.z > 0.8 else (RED if int((math.atan2(c.y, c.x) + math.pi) / (math.tau / 8)) % 2 else YEL))
parts.append(drum)
for i, z in enumerate((0.04, H - 0.02)):
    parts.append(torus(f"Rim{i}", R + 0.01, 0.04, seg=20, seg2=5, pos=(0, 0, z), color=GOLD))
# big ball on the drum, blue with a yellow band
BZ = H + 0.19
ball = blob("Ball", 0.2, (0.1, -0.08, BZ), BLUE, subdiv=2, jitter=0)
paint(ball, lambda c, n: YEL if abs(c.z - BZ) < 0.06 else BLUE)
parts.append(ball)


def pin(name, pos, rot, s=1.0):
    """Juggling pin: white bottle profile with a red band and red knob."""
    prof = [(0, 0), (0.05, 0.005), (0.075, 0.07), (0.075, 0.16), (0.04, 0.27), (0.028, 0.4), (0.045, 0.44), (0, 0.47)]
    p = lathe(name, [(r * s, z * s) for r, z in prof], segs=8)
    paint(p, lambda c, n: RED if (0.17 * s < c.z < 0.25 * s) or c.z > 0.4 * s else WHITE_)
    return move(p, pos, rot)


parts.append(pin("PinA", (-0.24, 0.1, H), (0, -16, 0), 1.15))
parts.append(pin("PinB", (-0.1, 0.18, H), (0, 12, 0), 1.15))
parts.append(pin("PinC", (0.5, -0.24, 0.0), (0, 24, 0), 1.1))
prop_finish("habitat_prop_jester", parts)
