# obby_drip_c (option C, "Grumpy Goo"): Climb's drip as a grumpy violet goo blob stuck under a slate ceiling plate.
# One fused metaball blob (lumpy, sagging, two violet drips down its sides) pinches at the bottom into a red neck
# where the drop swells out of it; two angry eyes with heavy brows glare down at the ladder. The face makes the
# warning read from far away: "this thing spits". Old nozzle box 2.6 x 1.4 x 2.6; this is 2.8 wide and 1.9 tall
# (the plate and the blob's top go up, the bottom stays where the old nozzle's bottom was).
# The drop: a taller, sharper teardrop (2.0 x 2.2 x 2.0). The drain: the shared slate tub.
# DRIP_PART=set|nozzle|drop|drain (see models/_obby_drip_parts.py).
import math
from mathutils import Vector
from lib import *
from models._obby_drip_parts import *
import models._obby_drip_parts as P

P.DROP_KW.update(height=2.2, pinch=1.8)

V_DEEP = rgb(142, 106, 208)
V = rgb(172, 136, 240)
V_HI = rgb(216, 192, 255)


def nozzle(z0):
    parts = []
    # the ceiling plate the goo hangs from
    plate = [(0.0, 1.62), (1.3, 1.62), (1.4, 1.7), (1.4, 1.84), (1.3, 1.92), (0.0, 1.92)]
    parts.append(rev("Plate", plate, flat([SLATE_LO, SLATE_LO, SLATE, SLATE_HI, SLATE_HI]), segs=20, smooth=False,
                     pos=(0, 0, z0)))
    for b in bolts("Bolt", 6, 1.1, z0 + 1.6, SLATE_HI, r=0.12, a0=0.3):
        parts.append(b)
    # the blob: a sagging body, a few lumps, a pinched neck at the bottom, two side drips
    balls = [
        Ball((0, 0, z0 + 1.15), (1.2, 1.15, 0.5)),
        Ball((0, 0, z0 + 0.82), (0.95, 0.92, 0.5)),
        Ball((0.62, -0.25, z0 + 1.0), (0.55, 0.5, 0.45)),
        Ball((-0.6, 0.3, z0 + 1.02), (0.55, 0.5, 0.42)),
        Ball((-0.2, -0.6, z0 + 1.05), (0.5, 0.45, 0.4)),
        Ball((0.3, 0.62, z0 + 1.1), (0.5, 0.45, 0.38)),
        Ball((0, 0, z0 + 0.42), (0.48, 0.48, 0.36)),   # the neck
        Ball((0, 0, z0 + 0.16), (0.36, 0.36, 0.22)),
    ]
    for (x, y, ln) in ((-1.0, -0.35, 0.7), (0.92, 0.45, 0.5)):
        for s in range(5):
            t = s / 4
            w = 0.26 * (1 - 0.45 * t)
            balls.append(Ball((x * (1 - 0.08 * t), y, z0 + 0.9 - ln * t), (w, w, w * 1.2)))
        balls.append(Ball((x * 0.92, y, z0 + 0.86 - ln - 0.12), 0.22))
    body = metaball_mesh("GooBlob", balls, resolution=0.1, tris=900)
    nz = z0

    def col(co, n):
        c = mix(V_DEEP, V, min(1.0, max(0.0, 0.45 + 0.55 * n.z + 0.15)))
        if n.dot(GLOSS_DIR) > 0.72:
            c = mix(c, V_HI, min(1.0, (n.dot(GLOSS_DIR) - 0.72) / 0.18))
        r = math.hypot(co.x, co.y)
        red = max(0.0, min(1.0, (nz + 0.62 - co.z) / 0.3)) * (1.0 if r < 0.7 else 0.0)
        return mix(c, mix(HAZ_LO, HAZ, 0.5 + 0.5 * max(0.0, -n.z)), red)

    parts.append(paint_goo(body, col))
    # angry eyes on the front, looking down
    for s in (-1, 1):
        ex, ey, ez = s * 0.43, -0.99, z0 + 0.9
        parts.append(keep_smooth(blob(f"Eye{s}", 0.33, (ex, ey, ez), WHITE, subdiv=2, jitter=0, squash=(1, 0.55, 1.15))))
        parts.append(keep_smooth(blob(f"Pupil{s}", 0.15, (ex - s * 0.05, ey - 0.16, ez - 0.1), INK, subdiv=2, jitter=0,
                                      squash=(1, 0.45, 1.1))))
        brow = box(f"Brow{s}", (0.5, 0.16, 0.14), (0, 0, 0), INK)
        from mathutils import Matrix
        brow.data.transform(Matrix.Translation((ex + s * 0.02, ey - 0.1, ez + 0.32))
                            @ Matrix.Rotation(math.radians(-s * 24), 4, "Y"))
        parts.append(brow)
    return parts


ship("c", nozzle)
