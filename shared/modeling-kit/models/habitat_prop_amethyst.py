# habitat_prop_amethyst: a geode cracked open: a rough rock half-shell tipped toward the walkway, full of purple
# crystals, with the other half lying beside it.
import math, random
from models._habitat_prop3 import *

PURP, PURP_LO, PURP_HI = rgb(186, 110, 246), rgb(142, 82, 218), rgb(234, 200, 255)
LINE = rgb(236, 226, 250)  # the pale agate band just inside the rock rim
R = random.Random(7)
parts = []


def shell(name, r, depth):
    """Half geode as a bowl, opening toward +Z: rough rock outside, pale agate rim, deep purple inside."""
    prof = [(0, -depth), (r * 0.6, -depth * 0.9), (r * 0.92, -depth * 0.55), (r, -depth * 0.1), (r * 1.0, 0.0),
            (r * 0.84, 0.0), (r * 0.8, -depth * 0.25), (r * 0.6, -depth * 0.6), (0, -depth * 0.68)]
    o = lathe(name, prof, segs=10,
              color_fn=lambda i, k, z: ROCK_LO if i < 2 else (ROCK if i < 4 else (LINE if i == 4 else (PURP if i == 5 else PURP_LO))))
    bm = bmesh.new()
    bm.from_mesh(o.data)
    jitter_bm(bm, 0.07, R.randint(0, 99))
    bm.to_mesh(o.data)
    bm.free()
    return o


# main half: tipped 60 deg toward the front so the inside faces the walkway
cx, cy, cz, tilt = -0.18, 0.12, 0.55, 62
main = shell("Main", 0.55, 0.42)
xf(main, (cx, cy, cz), (tilt, 0, 0))
parts.append(main)
# crystals inside, pointing out of the bowl (along the tilted axis), a big one in the middle
axis = Vector((0, -math.sin(math.radians(tilt)), math.cos(math.radians(tilt))))
for i, (u, v, L, rr) in enumerate([(0, 0, 0.42, 0.1), (0.2, 0.08, 0.3, 0.075), (-0.2, 0.1, 0.32, 0.08), (0.05, -0.22, 0.28, 0.07),
                                    (-0.14, -0.15, 0.24, 0.06), (0.24, -0.12, 0.22, 0.06), (-0.27, -0.05, 0.2, 0.055)]):
    c = prism_crystal(f"Cr{i}", rr, L, lo=PURP_LO, hi=PURP_HI if i == 0 else mix(PURP, PURP_HI, 0.4))
    # base point in the bowl's local frame (x along X, v across the opening), then lean out from the centre
    xf(c, (0, 0, 0), (R.uniform(-12, 12) + v * 70, -u * 70, R.uniform(0, 60)))
    xf(c, (u, v, -0.06), (0, 0, 0))
    xf(c, (cx, cy, cz), (tilt, 0, 0))
    parts.append(c)
# a little rock foot so the tipped shell sits on the deck
parts.append(floor(blob("Foot", 0.3, (cx, cy + 0.12, 0.05), ROCK_LO, subdiv=1, squash=(1.3, 1, 0.6), jitter=0.1, seed=2)))
# the other half lying on its back to the right, open side up, a few small crystals
other = shell("Other", 0.36, 0.28)
xf(other, (0.58, -0.05, 0.27), (-15, 20, 0))
parts.append(other)
for i, (u, v) in enumerate([(0, 0), (0.1, 0.08), (-0.1, 0.05)]):
    c = prism_crystal(f"Sm{i}", 0.055, 0.2, lo=PURP_LO, hi=mix(PURP, PURP_HI, 0.5))
    xf(c, (0, 0, 0), (v * 90, -u * 90, 0))
    xf(c, (u, v, 0.03), (0, 0, 0))
    xf(c, (0.58, -0.05, 0.27), (-15, 20, 0))
    parts.append(c)
# loose shards on the deck
for i, (x, y, a) in enumerate([(0.3, -0.42, 30), (-0.65, -0.3, -40)]):
    c = prism_crystal(f"Sh{i}", 0.05, 0.16, lo=PURP_LO, hi=PURP)
    parts.append(place(c, (x, y, 0.02), 55, a))
parts = [floor(p) for p in parts]
ship("habitat_prop_amethyst", parts)
