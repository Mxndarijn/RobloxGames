# habitat_prop_glitch: an "error window" sign on a post: pixel window panel, blue title bar, big red X,
# a few stray pixel blocks knocked off the corners.
from models._habitat_prop5 import *

POST, POST_HI = rgb(120, 120, 140), rgb(170, 170, 190)
FRAME = rgb(60, 60, 84)
BODY = rgb(236, 236, 246)
BAR, BAR_HI = rgb(60, 110, 240), rgb(110, 160, 255)
RED, WHITE = rgb(240, 50, 60), rgb(255, 255, 255)
MAG, CYAN = rgb(255, 70, 220), rgb(60, 240, 255)
W, Z0, Z1 = 1.3, 0.42, 1.28
ZC = (Z0 + Z1) / 2
parts = [
    gbox("Foot", (0.5, 0.42, 0.08), (0, 0.08, 0.04), POST, POST_HI, bev=0.02),
    gbox("Post", (0.12, 0.12, Z0 + 0.1), (0, 0.08, (Z0 + 0.1) / 2), POST, POST_HI, bev=0.02),
    gbox("Frame", (W, 0.12, Z1 - Z0), (0, 0.08, ZC), FRAME, bev=0.0),
    gbox("Body", (W - 0.1, 0.04, Z1 - Z0 - 0.26), (0, 0.0, ZC - 0.08), BODY, bev=0.0),
    gbox("Title", (W - 0.1, 0.04, 0.14), (0, 0.0, Z1 - 0.12), BAR, BAR_HI, bev=0.0),
]
for k, x in enumerate((0.36, 0.46, 0.56)):   # window buttons
    parts.append(gbox(f"Btn{k}", (0.07, 0.03, 0.07), (x, -0.03, Z1 - 0.12), RED if k == 2 else WHITE, bev=0.0))
# big red X in a red square badge
parts.append(gbox("Badge", (0.38, 0.04, 0.38), (0, -0.03, ZC - 0.08), RED, bev=0.03))
for r in (45, -45):
    parts.append(gbox(f"X{r}", (0.36, 0.03, 0.08), (0, -0.06, ZC - 0.08), WHITE, bev=0.0, rot=(0, r, 0)))
# glitch pixels: missing / shifted squares off the corners
for k, (x, z, c) in enumerate(((-W / 2 - 0.05, Z1 - 0.1, MAG), (-W / 2 + 0.06, Z1 + 0.04, CYAN), (W / 2 + 0.05, Z0 + 0.12, CYAN),
                               (W / 2 - 0.08, Z0 - 0.04, MAG), (-W / 2 - 0.1, Z0 + 0.25, CYAN))):
    parts.append(gbox(f"Px{k}", (0.1, 0.1, 0.1), (x, 0.04, z), c, bev=0.0))
ship("habitat_prop_glitch", parts)
