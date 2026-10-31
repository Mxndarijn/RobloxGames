# habitat_prop_kirin: signature prop for Kirin: a cloud lantern: a round gold-framed lantern with warm glowing
# panels and a pagoda cap, sitting on a soft white cloud puff. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

CLOUD, CLOUD_D = rgb(255, 255, 255), rgb(206, 214, 244)
GOLD, GOLD_LO, GOLD_HI = rgb(255, 196, 60), rgb(246, 168, 40), rgb(255, 230, 130)
GLOW, GLOW_HI = rgb(255, 150, 70), rgb(255, 214, 120)
RED = rgb(236, 64, 70)

parts = []
for k, (x, y, z, r) in enumerate([(0, 0, 0.18, 0.32), (-0.34, 0.02, 0.12, 0.22), (0.35, -0.02, 0.12, 0.23),
                                  (0.05, 0.18, 0.14, 0.22)]):
    b = blob(f"Cloud{k}", r, (x, y, z), CLOUD, subdiv=2, jitter=0.03, seed=k, squash=(1.1, 1, 0.8))
    paint(b, lambda c, n: CLOUD if n.z > -0.1 else CLOUD_D)
    parts.append(floor(b))
Z0 = 0.33  # lantern foot on the cloud
parts.append(cylinder("Foot", 0.2, 0.06, (0, 0, Z0), GOLD_LO, segs=8, r_top=0.22))
body = lathe("Body", [(0.17, Z0 + 0.06), (0.27, Z0 + 0.2), (0.29, Z0 + 0.34), (0.26, Z0 + 0.48), (0.17, Z0 + 0.58)], segs=8,
             phase=math.pi / 8)
paint(body, lambda c, n: GLOW_HI if 0.15 < c.z - Z0 < 0.45 else GLOW)
parts.append(body)
for k in range(8):  # gold ribs on the corners
    a = k * math.tau / 8
    pts = [(math.cos(a) * r * 1.03, math.sin(a) * r * 1.03, Z0 + z) for r, z in [(0.17, 0.06), (0.27, 0.2), (0.29, 0.34), (0.26, 0.48), (0.17, 0.58)]]
    parts.append(tube(f"Rib{k}", pts, [0.024] * 5, GOLD, segs=3))
parts.append(torus("Band", 0.295, 0.03, seg=8, seg2=4, pos=(0, 0, Z0 + 0.34), color=GOLD_HI))
# pagoda cap: flared gold roof with upturned corners, knob and red bead
cap = lathe("Cap", [(0, Z0 + 0.58), (0.36, Z0 + 0.6), (0.34, Z0 + 0.66), (0.14, Z0 + 0.74), (0.06, Z0 + 0.84), (0, Z0 + 0.86)],
            segs=8, phase=math.pi / 8)
for v in cap.data.vertices:  # tip the rim corners up
    if math.hypot(v.co.x, v.co.y) > 0.3:
        v.co.z += 0.05
gradient(cap, GOLD_LO, GOLD_HI)
parts.append(cap)
parts.append(torus("Handle", 0.09, 0.025, seg=10, seg2=4, rot=(90, 0, 0), pos=(0, 0, Z0 + 0.94), color=GOLD))
parts.append(blob("Bead", 0.05, (0, 0, Z0 + 0.86), RED, subdiv=1, jitter=0))
prop_finish("habitat_prop_kirin", parts)
