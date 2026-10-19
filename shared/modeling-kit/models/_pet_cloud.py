# Shared builder for pet_cloud (and its preview scene): soft cartoon cloud. Round puffs fused into one skin
# (metaballs, like the goo), smooth-shaded, flat top for the pet, a ring of rim puffs that scallop the outline all the
# way round, a rounded belly (it floats), light-blue underside fading to white.
# The game seats the pet on the top of the mesh bbox (PetCloud.seat: anchor.Size.Y / 2), so nothing may rise above TOP.
from lib import *
from lib.goo import Ball, metaball_mesh, paint_goo
import math

WHITE, BLUE, BELLY = rgb(240, 247, 255), rgb(158, 200, 246), rgb(128, 164, 234)
TOP = 1.225  # pet stands here: the bbox top
RX, RY = 1.24, 0.9  # rim puff ring (pre-fit frame)


def _rim(n=8):
    """n rim puffs round an ellipse, big and small alternating, the big ones high (their tops reach the seat edge)."""
    out = []
    for i in range(n):
        a = i * math.tau / n + 0.18
        big = i % 2 == 0
        r = 0.58 if big else 0.46
        k = 1.0 if big else 1.04  # small puffs sit a little further out, so the outline scallops
        out.append((RX * k * math.cos(a), RY * k * math.sin(a), 0.56 if big else 0.48, (r, r, r * 0.92)))
    return out


# (x, y, z, surface semi-axes)
PUFFS = [
    (0.0, 0.0, 0.66, (0.98, 0.62, 0.6)),  # body, becomes the flat top
    (-0.55, 0.0, 0.42, (0.62, 0.5, 0.4)),  # belly: rounds the underside
    (0.55, 0.05, 0.42, (0.6, 0.48, 0.4)),
] + _rim()
FX, FY = 0.93, 0.9  # puff spread (metaballs bulge where they merge)
SIZE = (3.3, 2.4)  # exact footprint (x, y) of every cloud built here
K = 0.26  # soft shoulder of the flat top


def _soft_top(z, top):
    z0 = top - K
    return z if z <= z0 else z0 + K * math.tanh((z - z0) / K)


def cloud_parts(tris=1800, res=0.07, smooth=1, extra=(), colour=None, name="PetCloud", flat_r=None):
    """Variants (pet_mount_*) reuse this builder; the defaults are the shipped pet_cloud.
    extra: more puffs (x, y, z, semi-axes) in the same pre-fit frame, e.g. flame tufts; colour: (co, n) -> colour
    replacing the blue-to-white gradient; flat_r: only flatten the top inside this normalised plan radius (so tufts
    on the rim keep their height), None flattens everywhere. The result stands on z = 0, its top over the centre is
    exactly TOP and its footprint is exactly SIZE."""
    puffs = list(PUFFS) + list(extra)
    o = metaball_mesh(name, [Ball((x * FX, y * FY, z), (s[0] * FX, s[1] * FY, s[2])) for x, y, z, s in puffs], resolution=res, tris=tris, smooth=smooth)
    me = o.data
    z_lo = min(v.co.z for v in me.vertices)
    for v in me.vertices:
        v.co.z -= z_lo
    raw = max(v.co.z for v in me.vertices if math.hypot(v.co.x, v.co.y) < 0.4)  # body top over the centre
    for v in me.vertices:
        z = v.co.z
        if flat_r is None:
            v.co.z = _soft_top(z, raw)
        else:
            w = 1.0 - min(1.0, max(0.0, (math.hypot(v.co.x / 1.2, v.co.y / 0.85) - flat_r) / 0.25))
            v.co.z = z + (_soft_top(z, raw) - z) * w * w * (3 - 2 * w)
    seat = max(v.co.z for v in me.vertices if math.hypot(v.co.x, v.co.y) < 0.4)
    k = TOP / seat
    xs, ys = [v.co.x for v in me.vertices], [v.co.y for v in me.vertices]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    kx, ky = SIZE[0] / (max(xs) - min(xs)), SIZE[1] / (max(ys) - min(ys))
    for v in me.vertices:
        v.co.x, v.co.y, v.co.z = (v.co.x - cx) * kx, (v.co.y - cy) * ky, v.co.z * k
    me.update()

    def col(co, n):  # periwinkle belly, light blue sides fading to white by about 80% height
        t = min(1.0, max(0.0, (co.z - 0.1) / (TOP * 0.7)))
        c = mix(BLUE, WHITE, t * t * (3 - 2 * t))
        return mix(c, BELLY, max(0.0, -n.z) * (1 - t) * 0.9)

    paint_goo(o, colour or col)
    return [o]
