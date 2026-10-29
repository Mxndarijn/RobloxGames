# slime_hat_party: paid slime hat cosmetic, a striped party cone with a frilly collar and a pom-pom.
# Worn on the slimes on the owner's pads; the game scales it to the slime's width.
# Origin bottom centre, Z up, front -Y, ~2.0 studs wide at the base. The underside is a shallow
# dome-shaped hollow so it sits on a rounded slime top. HAT_PREVIEW=1 adds a stand-in slime (preview only).
import math
import os
from models._pvp_fun import *

BLUE = rgb(120, 196, 246)          # party blue
BLUE_D = mix(BLUE, LILAC, 0.35)
PINK_D = mix(PINK, RED, 0.25)
H = 1.75                            # cone tip height


def cone_body():
    """Twisted lathe: each ring is turned by TWIST * z, so the face columns spiral and the
    stripes (2 columns each) stay crisp instead of stair-stepping across the faces."""
    segs, n, R0, TWIST = 16, 7, 0.88, 1.0
    prof = [(0.5, 0.11), (0.82, 0.04), (R0, 0.0)]      # underside hollow (pole at 0.15)
    for j in range(n + 1):
        t = j / n
        prof.append((R0 * (1 - t) ** 1.08 * 0.94 + 0.06, 0.06 + t * (H - 0.06)))
    rings = [[(r * math.cos(k * math.tau / segs + TWIST * z), r * math.sin(k * math.tau / segs + TWIST * z), z)
              for k in range(segs)] for r, z in prof]

    def col(i, k, c):
        if i <= 3:
            return mix(PINK_D, PINK, 0.2)
        t = min(1, c.z / H)
        if (k // 2) % 2:
            return mix(BLUE_D, BLUE, 0.4 + 0.6 * t)
        return mix(PINK_D, mix(PINK, WHITE, 0.15), 0.4 + 0.6 * t)
    return rings_shell("Cone", rings, col, poles=((0, 0, 0.15), (0, 0, H + 0.02)))


def collar():
    """Wavy frill round the base (scalloped torus)."""
    o = torus("Collar", 0.84, 0.14, lambda i, k, c: mix(mix(WHITE, LILAC, 0.3), WHITE, 0.5 + 0.5 * math.sin(i / 5 * math.tau)),
              segs=30, rsegs=5, M=place((0, 0, 0.12)))
    for v in o.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        w = math.cos(a * 10)
        r = math.hypot(v.co.x, v.co.y)
        k = (r + 0.045 * w) / r
        v.co.x *= k
        v.co.y *= k
        v.co.z += 0.035 * w
    return o


def pompom():
    """Fluffy pom-pom: a round ico with a small random wobble per vertex (spikes read as a gem)."""
    import random
    rnd = random.Random(4)
    lo, hi = mix(PINK, RED, 0.12), mix(PINK, WHITE, 0.3)
    o = ico("Pompom", 0.26, lambda i, k, c: mix(lo, hi, min(1, max(0, (c.z - H + 0.1) / 0.45))),
            subdiv=2, M=place((0, 0, H + 0.14)))
    cz = H + 0.14
    for v in o.data.vertices:
        d = v.co - Vector((0, 0, cz))
        v.co = Vector((0, 0, cz)) + d * (1 + rnd.uniform(-0.07, 0.09))
    return o


parts = [cone_body(), collar(), pompom()]

if os.environ.get("HAT_PREVIEW"):
    SL = mix(GOO, P["ranch_field_dark"], 0.15)
    prof = [(0, -1.6), (0.9, -1.58), (1.15, -1.3), (1.2, -0.8), (1.05, -0.3), (0.7, -0.03), (0.0, 0.06)]
    parts.append(lathe("PreviewSlime", prof, lambda i, k, c: mix(SL, GOO, min(1, (c.z + 1.6) / 1.6)), segs=24))

o = finish("slime_hat_party", parts)
a = o.data.attributes.get("keep_smooth")
if a is not None:
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
o["smooth_normals"] = 1
