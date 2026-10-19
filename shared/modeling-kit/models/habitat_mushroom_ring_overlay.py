# habitat_mushroom_ring_overlay: fairy-ring dressing for the crate pad: a lumpy moss frame round the mat, big
# red spotted toadstools on the corners, smaller ones on the edge middles, moss tufts between.
import math, random
from lib import *
from models._habitat import lathe, CREAM, P
from models._habitat_overlay import *

MOSS, MOSS_D = P["ranch_field_light"], P["ranch_field_dark"]
CAP, CAP_D = rgb(234, 74, 66), rgb(196, 58, 60)
STEM = mix(CREAM, rgb(255, 244, 200), 0.5)  # warm, lighter than cream: stems sit in the cap shadow
R = random.Random(9)
parts = [frame("Moss", shade(MOSS, 0.96), MOSS_D, seed=9, wobble=0.1)]


def on_deck(o, floor=0.0):
    """Flatten any verts below the deck onto it, so the export's bottom stays the deck (Habitats drop = 0)."""
    for v in o.data.vertices:
        v.co.z = max(v.co.z, floor)
    return o


def toadstool(i, x, y, s):
    """Cream stem + red dome cap with cream spot columns; s = scale (1 = ~1.7 tall)."""
    sh = 0.9 * s + 0.25
    out = [cylinder(f"St{i}", 0.2 * s + 0.06, sh + 0.1, (x, y, 0), STEM, segs=6, r_top=0.15 * s + 0.05)]
    cap = lathe(f"Cap{i}", [(0, 0), (0.62 * s, 0.04), (0.56 * s, 0.3 * s), (0.32 * s, 0.5 * s), (0, 0.55 * s)], segs=8, phase=math.pi / 8,
                pos=(x, y, sh - 0.05),
                color_fn=lambda ii, k, zz: CREAM if ii == 0 else (CREAM if (k + ii) % 3 == 0 and ii >= 2 else (CAP_D if ii == 1 else CAP)))
    out.append(cap)
    return out


for i, (x, y, a) in enumerate(band_spots(4, inset=0.1)):  # corners: one big toadstool on a moss hump
    parts += toadstool(i, x, y, 1.3)
    parts.append(on_deck(blob(f"Hump{i}", 0.62, (x, y, 0.12), shade(MOSS, 0.92), subdiv=1, squash=(1.3, 1.3, 0.45),
                      jitter=0.05, seed=20 + i)))
for i, (x, y, a) in enumerate(band_spots(4, phase=0.5)):  # edge middles: medium
    parts += toadstool(4 + i, x, y, 0.85)
for i, (x, y, a) in enumerate(band_spots(16)):  # small ones either side of each corner
    if i % 4 in (1, 3):
        parts += toadstool(8 + i, x, y, 0.5)
for i, (x, y, a) in enumerate(band_spots(8, phase=0.25)):
    parts.append(on_deck(blob(f"Tuft{i}", 0.46, (x, y, 0.16), shade(MOSS, R.uniform(0.9, 1.05)), subdiv=1,
                      squash=(1.4, 1.0, 0.6), jitter=0.05, seed=i, rot=(0, 0, a + 90))))
overlay_finish("habitat_mushroom_ring_overlay", parts)
