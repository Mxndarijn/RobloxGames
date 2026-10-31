# habitat_prop_robo: a charging dock: steel-blue box, lightning bolt, big green light, cable to a plug.
from models._habitat_prop5 import *

BODY, BODY_HI = rgb(110, 140, 190), rgb(170, 200, 240)
PANEL = rgb(56, 70, 110)
GREEN, GREEN_HI = rgb(60, 240, 100), rgb(180, 255, 190)
BOLT = rgb(255, 220, 60)
CABLE = rgb(60, 60, 80)
PLUG, PIN = rgb(240, 240, 248), rgb(255, 196, 70)
DX = -0.28
parts = [
    gbox("Body", (0.86, 0.6, 0.78), (DX, 0.1, 0.39), BODY, BODY_HI, bev=0.07),
    gbox("Panel", (0.62, 0.05, 0.5), (DX, -0.21, 0.38), PANEL, bev=0.02),
    slab("Bolt", bolt_pts(0.4, 0.28, cx=DX, cz=0.38), 0.05, BOLT, (0, -0.24, 0)),
    gcyl("LightBase", 0.16, 0.06, (DX, 0.1, 0.78), PANEL, segs=10),
    blob("Light", 0.17, (DX, 0.1, 0.86), GREEN_HI, subdiv=2, jitter=0, squash=(1, 1, 0.85)),
    gbox("Foot", (1.0, 0.7, 0.06), (DX, 0.1, 0.03), PANEL, bev=0.02),
]
parts[4] = gradient(parts[4], GREEN, GREEN_HI)
# cable from the right side down to a plug lying in front
pts = [(DX + 0.43, 0.1, 0.3), (DX + 0.6, 0.05, 0.18), (0.42, -0.08, 0.09), (0.55, -0.2, 0.09)]
parts.append(tube("Cable", pts, [0.045] * 4, CABLE, segs=6))
parts.append(gbox("Plug", (0.26, 0.2, 0.16), (0.7, -0.24, 0.09), PLUG, bev=0.03, rot=(0, 0, -30)))
for k, o in enumerate((-0.05, 0.05)):
    parts.append(box(f"Pin{k}", (0.12, 0.025, 0.05), (0.84 + o * 0.5, -0.32 + o * 0.87, 0.09), PIN, rot=(0, 0, -30)))
ship("habitat_prop_robo", parts)
