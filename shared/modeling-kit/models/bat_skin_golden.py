# bat_skin_golden: Golden Bat skin (Exclusive Shop, contract §10), ranch_bat's shape in polished gold.
# Same lathe profile as ranch_bat (pommel knob, grip wrap, trim ring, taper to the barrel) but gold, with a
# red velvet grip, a gold collar band round the barrel and a big pink gem set in a gold bezel on the front
# and the back. Frame = ranch_bat (models/_bat_skin.py): z 0..5.09, grip z = 1.2.
from models._bat_skin import *

GOLD_LO, GOLD, GOLD_HI = rgb(246, 188, 56), rgb(252, 208, 72), rgb(255, 242, 176)
GEM, GEM_HI = rgb(238, 92, 150), rgb(255, 196, 222)
RED_LO = mix(RED_D, RED, 0.6)

PROFILE = [
    (0.00, 0.00), (0.34, 0.00), (0.44, 0.16), (0.46, 0.38), (0.34, 0.62),  # pommel knob
    (0.27, 0.80), (0.28, 1.80),                                            # red grip wrap
    (0.33, 1.86), (0.33, 2.02),                                            # gold trim ring
    (0.34, 2.50), (0.43, 3.20), (0.53, 3.80), (0.59, 4.30), (0.58, 4.70),  # taper up to the barrel
    (0.45, 4.98), (0.00, 5.09),                                            # rounded end
]


def body():
    def col(i, k, c):
        z = c.z
        if 0.70 < z < 1.83:
            return mix(RED_LO, RED, (z - 0.7) / 1.1) if k % 4 else mix(RED_LO, RED, 0.3)  # wrap seams
        t = min(1.0, z / 5.0)
        g = mix(GOLD_LO, GOLD, 0.3 + 0.7 * t)
        # polished shine: a soft bright band on the lit side (3 columns), a slightly deeper back
        shine = {1: 0.25, 2: 0.6, 3: 0.6, 4: 0.25}.get(k, 0.0)
        return mix(g, GOLD_HI, shine) if shine else (mix(g, GOLD_LO, 0.2) if k in (10, 11) else g)
    return lathe("Body", PROFILE, col, segs=16, smooth=True)


def collar():
    return torus("Collar", 0.565, 0.075, lambda j, k, c: GOLD_HI if j < 3 else GOLD, segs=16, rsegs=4,
                 M=place((0, 0, 3.62)))


def gem(side):
    y = side * 0.58
    bezel = torus("Bezel%d" % side, 0.28, 0.065, lambda j, k, c: GOLD_HI if c.z > 4.2 else GOLD, segs=12, rsegs=4,
                  M=place((0, y, 4.2), (90, 0, 0)))
    stone = ico("Gem%d" % side, 0.28, lambda i, k, c: GEM_HI if c.z > 4.26 else GEM, subdiv=1,
                M=place((0, y + side * 0.03, 4.2)), squash=(0.95, 0.55, 1.15), smooth=False)
    return [bezel, stone]


parts = [body(), collar()] + gem(-1) + gem(1)
ship_skin("bat_skin_golden", parts)
