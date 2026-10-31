# habitat_prop_star_emperor: a royal banner on a gold pole: purple swallowtail cloth with a big gold star.
from models._habitat_prop5 import *

GOLD, GOLD_LO = rgb(255, 210, 70), rgb(240, 160, 40)
CLOTH, CLOTH_HI = rgb(120, 60, 200), rgb(170, 100, 245)
TRIM = rgb(255, 236, 150)
PX, TOP = -0.62, 1.12
parts = [
    gcyl("Base", 0.2, 0.12, (PX, 0, 0), GOLD_LO, GOLD, segs=8, r_top=0.15),
    gcyl("Pole", 0.05, TOP, (PX, 0, 0.1), GOLD_LO, GOLD, segs=6),
    blob("Finial", 0.11, (PX, 0, TOP + 0.12), GOLD, subdiv=1, jitter=0),
    rod("Arm", (PX, 0, TOP - 0.03), (0.66, 0, TOP - 0.03), 0.035, GOLD),
    blob("ArmEnd", 0.06, (0.68, 0, TOP - 0.03), GOLD, subdiv=1, jitter=0),
]
X0, X1, Z1, Z0 = -0.5, 0.58, TOP - 0.08, 0.3
cloth = [(X0, Z1), (X1, Z1), (X1, Z0), (0.04 + 0.0, Z0 + 0.22), (X0, Z0)]
parts.append(slab("Cloth", cloth, 0.06, CLOTH, hi=CLOTH_HI))
parts.append(slab("Trim", [(X0 - 0.02, Z1 - 0.04), (X1 + 0.02, Z1 - 0.04), (X1 + 0.02, Z1 + 0.04), (X0 - 0.02, Z1 + 0.04)], 0.09, TRIM))
parts.append(slab("Star", star_pts(5, 0.3, 0.13, cx=0.04, cz=0.74), 0.06, GOLD, (0, -0.05, 0)))
ship("habitat_prop_star_emperor", parts)
