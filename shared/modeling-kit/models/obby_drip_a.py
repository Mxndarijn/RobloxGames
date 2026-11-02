# obby_drip_a (option A, "Goo Tap"): Climb's drip as a chunky slate tap screwed under a round plate.
# The nozzle: a bolted mount plate, a lime collar, a short tapering spout ending in a rolled lip with a dark mouth;
# red goo rolls round the lip with two short drips, and the waiting drop's tip sits up inside the mouth, so the drop
# reads as coming out of the tap. Fits the old 2.6 x 1.4 x 2.6 nozzle box (2.6 x 1.5 x 2.6).
# The drop: a red teardrop over the 2-stud ball (gloss spot front-left). The drain: the shared slate tub.
# The tap's handle: a lime wheel on a stem out of the left side.
# DRIP_PART=set|nozzle|drop|drain (see models/_obby_drip_parts.py).
from lib import *
from models._obby_drip_parts import *


def nozzle(z0):
    parts = []
    # mount plate (top) -> collar -> spout -> rolled lip -> dark mouth -> red goo up inside
    prof = [
        (0.0, 1.5), (1.18, 1.5), (1.3, 1.4), (1.3, 1.24), (1.16, 1.16),   # plate
        (0.8, 1.14), (0.8, 0.98),                                          # neck under the plate
        (0.74, 0.5), (0.86, 0.26), (0.96, 0.12), (0.9, 0.0),               # spout flaring into the lip
        (0.72, 0.02), (0.62, 0.2), (0.58, 0.42),                           # mouth wall going up inside
        (0.0, 0.44),                                                       # goo inside the mouth
    ]
    cols = [SLATE_HI, SLATE_HI, SLATE, SLATE_LO, SLATE_LO, SLATE_LO,
            SLATE, SLATE_HI, SLATE, SLATE_LO, BORE_HI, BORE, BORE, HAZ_LO]
    parts.append(rev("Tap", prof, flat(cols), segs=20, pos=(0, 0, z0), smooth=False))
    # lime collar ring under the plate
    collar = [(0.78, 0.9), (0.98, 0.94), (1.02, 1.04), (0.98, 1.12), (0.78, 1.14)]
    parts.append(rev("Collar", collar, flat([LIME_LO, LIME, LIME_HI, LIME, LIME_LO]), segs=20, pos=(0, 0, z0), smooth=False,
                     loop=True))
    for b in bolts("Bolt", 6, 1.05, z0 + 1.13, SLATE_HI, r=0.13, a0=0.5):
        parts.append(b)
    # a thin roll of red goo on the outer lip, two short drips (left front, right back); kept thin so the dark lip
    # still rings the drop's top
    parts.append(lip_goo("LipGoo", z0 + 0.1, 0.92, [(-125, 0.3), (25, 0.45)], seed=2, thick=0.12, n=28))
    # the tap's handle: a stem out of the neck to the left (the lit side), a lime wheel with a round hub on its end
    parts.append(cylinder("Stem", 0.12, 0.5, (-0.95, 0, z0 + 0.72), SLATE_LO, segs=8, rot=(0, 90, 0)))
    wheel = [(0.18, 1.2), (0.42, 1.2), (0.46, 1.27), (0.42, 1.34), (0.18, 1.34)]
    w = rev("Wheel", wheel, flat([LIME_LO, LIME, LIME_HI, LIME, LIME_LO]), segs=16, smooth=False, loop=True,
            rot=(0, -90, 0), pos=(0, 0, z0 + 0.72))
    parts.append(w)
    parts.append(keep_smooth(blob("Hub", 0.22, (-1.28, 0, z0 + 0.72), LIME_HI, subdiv=2, jitter=0,
                                  squash=(0.6, 1, 1)), False))
    return parts


ship("a", nozzle)
