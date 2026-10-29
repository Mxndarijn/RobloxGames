# Lock stopper style "Carousel": jar 1's door as a fairground carousel canopy seen head-on: lilac and butter wedge
# panels rising to a gold knob, a scalloped valance edge in a gold rim with little bulbs, and a red velvet rope swag
# hung across it on gold clips (the red lock signal: "closed"). Same box as goo_jar_stopper (_lock_stopper).
from models._lock_stopper import *

LILAC = PALETTE["ranch_lilac"]
BUTTER = mix(PALETTE["ranch_butter"], PALETTE["ranch_cream"], 0.5)  # pale, so the gold trim stands out
CREAM = PALETTE["ranch_cream"]
VELVET = mix(RED, PALETTE["ranch_roof_dark"], 0.35)
WEDGES = 12
segs = WEDGES * 3


def panel_col(r, a, i, j):
    if i < 0:
        return GOLD
    w = (j // 3) % 2
    base = LILAC if w == 0 else BUTTER
    if r > 4.05:  # the valance band
        base = mix(base, CREAM, 0.25)
    return shade(base, 0.86 + 0.14 * (1 - r / R))  # lighter toward the raised middle


def scallop(a):
    # one round scallop per wedge on the outer edge
    u = (a / math.tau * WEDGES) % 1.0
    return 0.965 + 0.035 * math.sin(u * math.pi)


parts = [plug("Canopy", [0.6, 1.4, 2.3, 3.2, 3.95, 4.15, R / 1.0], segs,
              lambda r: 0.55 + 0.5 * (1 - r / R), panel_col, rim=scallop, back_y=-0.05, back_col=mix(LILAC, CREAM, 0.2))]
# the gold rim between canopy and valance, with a bulb on every panel seam
parts.append(torus("Rim", 4.05, 0.17, (0, -0.68, CZ), GOLD, segs=30, sides=6))
for k in range(WEDGES):
    a = k / WEDGES * math.tau
    parts.append(blob(f"Bulb{k}", 0.2, (4.05 * math.cos(a), -0.86, CZ + 4.05 * math.sin(a)), rgb(255, 244, 210), subdiv=1, jitter=0))
# the carousel's hub: a low gold cap where the panels meet (flat, so it doesn't read as a nose)
parts.append(painted(cylinder("Hub", 0.75, 0.22, (0, -0.98, CZ), GOLD_D, segs=12, r_top=0.55, rot=(90, 0, 0)), GOLD_D, GOLD))
# the gold door knob on the opening side (where the classic pull is), on a short neck
KX, KZ = 3.0, CZ + 1.35
parts.append(cylinder("KnobNeck", 0.22, 0.5, (KX, -0.75, KZ), GOLD_D, segs=8, rot=(90, 0, 0)))
parts.append(painted(blob("Knob", 0.52, (KX, -1.3, KZ), GOLD, subdiv=2, squash=(1, 0.7, 1), jitter=0), GOLD_D, GOLD))

# the red velvet rope: one nearly taut swag (a deep sag read as a smile under the hub) across the panels between two gold clips, tasselled ends (a fair queue rope)
x0, z0, sag = 3.45, CZ - 1.45, 0.45
pts = []
for m in range(15):
    t = m / 14
    pts.append((-x0 + 2 * x0 * t, -1.12, z0 - sag * (1 - (2 * t - 1) ** 2)))
rope = tube("Rope", pts, [0.32] * len(pts), VELVET, segs=7)
gradient(rope, shade(VELVET, 0.85), mix(RED, RED_HI, 0.3))
parts.append(rope)
for k, x in enumerate((-x0, x0)):
    parts.append(painted(blob(f"Clip{k}", 0.4, (x, -1.1, z0 + 0.05), GOLD, subdiv=2, squash=(1, 0.6, 1), jitter=0), GOLD_D, GOLD))
    parts.append(painted(cylinder(f"Tassel{k}", 0.16, 0.75, (x, -1.12, z0 - 0.9), VELVET, segs=8, r_top=0.32),
                         shade(VELVET, 0.8), VELVET))

parts += hinges(GOLD, t=0.6)
ship("lock_stopper_carousel", fit_to_classic(parts))
