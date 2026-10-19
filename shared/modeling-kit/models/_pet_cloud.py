# Shared builder for pet_cloud (and its preview scene): soft cartoon cloud. Round puffs fused into one skin
# (metaballs, like the goo), smooth-shaded, flat-ish top for the pet, light-blue underside fading to white.
from lib import *
from lib.goo import Ball, metaball_mesh, paint_goo
import math

WHITE, BLUE = rgb(255, 255, 255), rgb(168, 208, 244)
TOP = 1.225  # pet stands here
# (x, y, z, surface semi-axes)
PUFFS = [
    (0.0, 0.0, 0.58, (1.10, 0.74, 0.78)),  # body, becomes the flat top
    (-1.12, 0.10, 0.50, (0.60, 0.62, 0.52)),
    (1.14, -0.08, 0.48, (0.56, 0.58, 0.50)),
    (0.40, -0.82, 0.46, (0.58, 0.46, 0.48)),
    (-0.42, 0.84, 0.48, (0.60, 0.48, 0.50)),
    (-0.80, -0.70, 0.42, (0.42, 0.38, 0.42)),
    (0.86, 0.72, 0.42, (0.44, 0.40, 0.42)),
]
FX, FY = 0.95, 0.92  # footprint fit (metaballs bulge where they merge)
K = 0.30  # soft shoulder of the flat top


def _soft_top(z):
    z0 = TOP - K
    return z if z <= z0 else z0 + K * math.tanh((z - z0) / K)


def cloud_parts(tris=1800, res=0.07, smooth=1):
    o = metaball_mesh("PetCloud", [Ball((x * FX, y * FY, z), (s[0] * FX, s[1] * FY, s[2])) for x, y, z, s in PUFFS], resolution=res, tris=tris, smooth=smooth)
    me = o.data
    for v in me.vertices:
        v.co.z = _soft_top(max(v.co.z, 0.0)) * 1.026
    me.update()

    def col(co, n):  # light blue at the base fading to white by about 60% height
        t = min(1.0, max(0.0, co.z / (TOP * 0.8)))
        return mix(BLUE, WHITE, t * t * (3 - 2 * t))

    paint_goo(o, col)
    return [o]
