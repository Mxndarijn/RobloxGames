# habitat_flower_bed_overlay: garden-bed dressing for the crate pad: a dark soil frame round the mat, soil
# tufts and leafy bushes along the rim band, round blooms on stems and a big 5-petal daisy on each corner.
import math, random
from lib import *
from models._habitat import CREAM, BUTTER, PINK, ROOF, WOOD_D, P
from models._habitat_overlay import *

LEAF, LEAF_D = P["ranch_field_light"], P["ranch_field_dark"]
LILAC = mix(P["ranch_lilac"], CREAM, 0.25)
SOIL = rgb(152, 108, 76)  # lifted: 132/92/64 went near-black in the Roblox look
COLS = [PINK, LILAC, BUTTER, CREAM]
R = random.Random(11)
parts = [frame("Soil", shade(SOIL, 1.05), shade(SOIL, 0.85), seed=11, wobble=0.08)]


def on_deck(o, floor=0.0):
    """Flatten any verts below the deck onto it, so the export's bottom stays the deck (Habitats drop = 0)."""
    for v in o.data.vertices:
        v.co.z = max(v.co.z, floor)
    return o


def daisy(i, x, y, h, col, r=0.36, centre=BUTTER):
    """Stem + 5 petal blobs round a centre bead at height h."""
    out = [cylinder(f"Stem{i}", 0.06, h, (x, y, 0), LEAF_D, segs=4)]
    for k in range(5):
        a = k * math.tau / 5 + i
        out.append(blob(f"Pt{i}_{k}", r * 0.55, (x + math.cos(a) * r * 0.6, y + math.sin(a) * r * 0.6, h), col,
                        subdiv=1, squash=(1.0, 0.7, 0.4), jitter=0, rot=(0, 0, math.degrees(a))))
    out.append(blob(f"Ct{i}", r * 0.38, (x, y, h + 0.06), centre, subdiv=1, squash=(1, 1, 0.7), jitter=0))
    return out


def bloom(i, x, y, h, col):
    """Stem + one round squashed bloom head + centre bead (planter lesson: reads at sheet size, cheap)."""
    return [cylinder(f"BSt{i}", 0.06, h, (x, y, 0), LEAF_D, segs=4),
            blob(f"Bl{i}", 0.42, (x, y, h + 0.05), col, subdiv=1, squash=(1, 1, 0.65), jitter=0.04, seed=i),
            blob(f"BC{i}", 0.17, (x, y, h + 0.24), ROOF if col == BUTTER else BUTTER, subdiv=1, jitter=0)]


# leafy bushes all round the band, with small soil tufts poking out on the outer edge between them
for i, (x, y, a) in enumerate(band_spots(16, phase=0.5)):
    parts.append(on_deck(blob(f"Bush{i}", 0.6, (x, y, 0.15), shade(LEAF if i % 2 else mix(LEAF, LEAF_D, 0.25), R.uniform(0.95, 1.05)),
                              subdiv=1, squash=(1.15, 0.95, 0.8), jitter=0.08, seed=40 + i, rot=(0, 0, a + 90))))
for i, (x, y, a) in enumerate(band_spots(16)):
    if i % 4:  # not on the corners (the hero daisies stand there)
        parts.append(on_deck(blob(f"Tuft{i}", 0.3, (x * 1.1, y * 1.1, 0.05), shade(SOIL, R.uniform(1.0, 1.12)), subdiv=1,
                                  squash=(1.3, 1.0, 0.6), jitter=0.06, seed=60 + i, rot=(0, 0, a + 90))))
# corner hero daisies on a leaf pair
for i, (x, y, a) in enumerate(band_spots(4, inset=0.1)):
    parts += daisy(100 + i, x, y, 1.6, [CREAM, PINK, CREAM, LILAC][i], r=0.66, centre=BUTTER)
# round blooms between: three per side, heights stepping down from the corners to the middle
for i, (x, y, a) in enumerate(band_spots(12, phase=0.5, inset=0.05)):
    k = i % 3
    parts += bloom(i, x, y, [1.15, 0.8, 1.15][k] + 0.1 * ((i // 3) % 2), COLS[(i + i // 3) % 4])
overlay_finish("habitat_flower_bed_overlay", parts)
