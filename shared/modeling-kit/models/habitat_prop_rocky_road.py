# habitat_prop_rocky_road: a stack of three nested waffle cones in a little wooden cone stand, topped with a
# chocolate rocky-road scoop (marshmallow and nut bits) for the Rocky Road slime.
import math, random
from lib import *
from models._habitat_prop import *

WAF_LO, WAF_HI = rgb(212, 142, 64), rgb(246, 196, 112)
WAF_DK = rgb(176, 108, 48)
WOOD, WOOD_DK = P["ranch_wood"], P["ranch_wood_dark"]
CHOC_LO, CHOC_HI = rgb(124, 72, 48), rgb(166, 102, 66)
MARSH = rgb(255, 246, 236)
NUT = rgb(226, 178, 108)
R = random.Random(5)

parts = []
# stand: round foot, short post, cup ring that holds the cone tip
parts.append(lathe("Foot", [(0, 0), (0.42, 0), (0.44, 0.04), (0.40, 0.09), (0, 0.09)], segs=14,
                   color_fn=lambda i, k, z: WOOD_DK if i < 2 else WOOD))
parts.append(lathe("Cup", [(0, 0.09), (0.10, 0.09), (0.12, 0.18), (0.20, 0.30), (0.16, 0.30), (0.08, 0.20), (0, 0.20)], segs=12,
                   color_fn=lambda i, k, z: WOOD))

# waffle cones: tip at TZ, nested every DZ
TZ, CONE_H, CONE_R, DZ = 0.12, 0.56, 0.29, 0.10  # r02: shorter stack (H was 1.63)
for n in range(3):
    z0 = TZ + n * DZ
    rows = 6
    prof = [(0, z0)] + [(CONE_R * (j / rows), z0 + CONE_H * (j / rows)) for j in range(1, rows + 1)]
    prof += [(CONE_R + 0.035, z0 + CONE_H + 0.0), (CONE_R + 0.035, z0 + CONE_H + 0.05), (CONE_R - 0.02, z0 + CONE_H + 0.05),
             (0, z0 + CONE_H + 0.05)]

    def wcol(i, k, z, rows=rows):
        if i >= rows:
            return WAF_HI  # rim
        base = mix(WAF_LO, WAF_HI, i / rows)
        return shade(base, 1.0 if (i + k) % 2 else 0.84)  # waffle checker
    parts.append(lathe(f"Cone{n}", prof, segs=12, phase=n * 0.26, color_fn=wcol))

top = TZ + 2 * DZ + CONE_H + 0.05
SR = 0.27
scoop = blob("Scoop", SR, (0, 0, top + SR * 0.55), seed=8, subdiv=2, jitter=0.05, lumps=0.15, squash=(1, 1, 0.9))
for v in scoop.data.vertices:
    v.co.z = max(v.co.z, top - 0.02)
regrad(scoop, CHOC_LO, CHOC_HI)
parts.append(scoop)
# marshmallow cubes and nut bits on the scoop
for j in range(9):
    a = R.uniform(0, math.tau)
    el = R.uniform(0.15, 1.2)
    p = (math.cos(a) * math.cos(el) * SR * 0.98, math.sin(a) * math.cos(el) * SR * 0.98, top + SR * 0.55 + math.sin(el) * SR * 0.88)
    if j % 3 == 2:
        parts.append(blob(f"Nut{j}", 0.05, p, NUT, seed=j, subdiv=1, jitter=0.2))
    else:
        parts.append(box(f"Marsh{j}", (0.09, 0.09, 0.09), p, MARSH, rot=(R.uniform(0, 90), R.uniform(0, 90), R.uniform(0, 90))))

ship("habitat_prop_rocky_road", parts)
