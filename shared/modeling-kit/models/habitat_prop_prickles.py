# habitat_prop_prickles: a terracotta pot with a chubby two-armed cactus and a pink flower on its head.
import math
from lib import *
from models._habitat_prop2 import *

CACT, CACT_D, CACT_HI = rgb(96, 190, 96), rgb(60, 142, 78), rgb(150, 222, 120)
TER_D = rgb(186, 84, 56)
SOIL = rgb(140, 96, 66)

# pot: tapered body, thick rolled rim
pot = lathe("Pot", [(0.30, 0.0), (0.33, 0.05), (0.40, 0.36), (0.47, 0.37), (0.48, 0.50), (0.42, 0.50), (0.0, 0.47)],
            segs=12, col=lambda c, i, k: TER_D if c.z < 0.2 else (TERRA if c.z < 0.36 else shade(TERRA, 1.08)))
parts = [pot]
parts.append(lathe("Soil", [(0.0, 0.47), (0.43, 0.47), (0.43, 0.49), (0.0, 0.5)], segs=12, col=SOIL))


def ribbed(c, i, k):
    return CACT if k % 2 else CACT_D


# main column: rounded top, 8 ribs (alternating colour per column)
col_prof = [(0.2, 0.46), (0.22, 0.6), (0.22, 1.0), (0.2, 1.1), (0.14, 1.18), (0.0, 1.21)]
parts.append(lathe("Column", col_prof, segs=10, col=lambda c, i, k: (CACT if k % 2 else mix(CACT, CACT_HI, 0.4)) if c.z > 0.8 else ribbed(c, i, k)))
# arms: elbow up, rounded tips
for s, zb, h in ((-1, 0.72, 0.28), (1, 0.84, 0.2)):
    pts = [(s * 0.12, 0, zb), (s * 0.32, 0, zb + 0.02), (s * 0.38, 0, zb + 0.12), (s * 0.38, 0, zb + 0.12 + h)]
    parts.append(tube(f"Arm{s}", pts, [0.11, 0.11, 0.11, 0.1], CACT, segs=8))
    parts.append(blob(f"ArmTip{s}", 0.1, (s * 0.38, 0, zb + 0.12 + h), mix(CACT, CACT_HI, 0.4), subdiv=2, squash=(1, 1, 0.8), jitter=0))
# spine dots
R = __import__("random").Random(3)
for j in range(14):
    a = R.uniform(-2.4, 2.4) - math.pi / 2
    z = R.uniform(0.58, 1.08)
    parts.append(blob(f"Spine{j}", 0.025, (math.cos(a) * 0.225, math.sin(a) * 0.225, z), WHITE, subdiv=1, jitter=0))
# flower on top: five pink petals round a yellow centre
for k in range(5):
    a = k * math.tau / 5 + 0.3
    parts.append(blob(f"Petal{k}", 0.1, (math.cos(a) * 0.1, math.sin(a) * 0.1, 1.22), PINK, subdiv=1,
                      squash=(1.2, 0.8, 0.45), jitter=0, rot=(0, -20, math.degrees(a))))
parts.append(blob("Centre", 0.06, (0, 0, 1.26), YELLOW, subdiv=1, jitter=0))
ship("habitat_prop_prickles", parts)
