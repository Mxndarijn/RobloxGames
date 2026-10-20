# pvp_fun_balloon: Goo Balloon, a water balloon filled with green goo (PvP fun item, thrown).
# Teardrop body, tied knot at the bottom (z=0). Held in the palm: grip = body centre.
import math
from models._pvp_fun import *

GOO_D = mix(GOO, P["ranch_field_dark"], 0.2)
GRIP = (0, 0, 0.85)
LIGHT = Vector((-0.45, -0.6, 0.66)).normalized()


def body():
    prof = [(0.0, 0.0), (0.12, 0.0), (0.2, 0.03), (0.17, 0.08), (0.1, 0.1),   # flared tail lips
            (0.16, 0.15), (0.17, 0.22), (0.12, 0.28),                         # knot bead
            (0.09, 0.33), (0.13, 0.4), (0.26, 0.5), (0.44, 0.63), (0.58, 0.8), (0.65, 0.98), (0.65, 1.16),
            (0.58, 1.33), (0.44, 1.46), (0.24, 1.54), (0.0, 1.57)]

    def col(i, k, c):
        if c.z < 0.31:
            return mix(GOO_D, GOO, 0.3)
        d = (c - Vector((0, 0, 0.9)))
        t = min(1, max(0, (c.z - 0.25) / 1.25))
        base = mix(GOO_D, GOO, 0.4 + 0.6 * t)
        h = d.normalized().dot(LIGHT) if d.length > 0 else 0
        if h > 0.93:
            return mix(GOO_HI, WHITE, 0.25)
        if h > 0.8:
            return mix(base, GOO_HI, 0.55)
        return base
    return lathe("Balloon", prof, col, segs=24)


ship("pvp_fun_balloon", [body()], GRIP)
