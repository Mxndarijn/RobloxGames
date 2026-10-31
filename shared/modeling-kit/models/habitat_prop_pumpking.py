# habitat_prop_pumpking: three ribbed jack-o'-lanterns with glowing carved faces and a little candle.
import math
from models._habitat_prop5 import *

ORANGE, ORANGE_HI = rgb(236, 110, 30), rgb(255, 160, 56)
STEM = rgb(96, 140, 56)
GLOW = rgb(255, 226, 90)
WAX, FLAME = rgb(250, 244, 226), rgb(255, 170, 40)


def pumpkin(name, r, h, pos, ribs=8):
    rows = 7
    prof = [(0, 0)] + [(r * math.sin(math.pi * i / rows), h / 2 * (1 - math.cos(math.pi * i / rows))) for i in range(1, rows)] + [(0, h)]
    prof[1] = (prof[1][0], 0.0)   # flat-ish bottom so it sits on the ground
    o = lathe(name, prof, segs=ribs * 2, color_fn=lambda i, k, z: shade(mix(ORANGE, ORANGE_HI, z / h), 1.0 if k % 2 else 0.9))
    for v in o.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        k = 1 - 0.09 * (0.5 - 0.5 * math.cos(ribs * a))
        v.co.x *= k
        v.co.y *= k
        v.co.z -= 0.05 * h * (1 - (v.co.z / h)) if v.co.z > h * 0.9 else 0   # dimple stays near the top
    o.data.update()
    return xf(o, pos)


def face(prefix, r, h, cx, cy, s=1.0, grin=True):
    """Glowing carved face on the -Y side of a pumpkin of radius r at (cx, cy)."""
    zc, y = h * 0.52, cy - r * 0.86
    out = []
    for sx in (-1, 1):
        out.append(slab(f"{prefix}Eye{sx}", [(cx + sx * 0.08 * s - 0.06 * s, zc + 0.04 * s), (cx + sx * 0.08 * s + 0.06 * s, zc + 0.04 * s),
                                             (cx + sx * 0.08 * s + sx * 0.02 * s, zc + 0.15 * s)], 0.2 * s, GLOW, (0, y, 0)))
    m = [(-0.16, 0.0), (-0.1, -0.04), (-0.06, 0.0), (0, -0.05), (0.06, 0.0), (0.1, -0.04), (0.16, 0.0), (0.1, -0.11), (-0.1, -0.11)]
    out.append(slab(f"{prefix}Mouth", [(cx + u * s, zc - 0.03 * s + v * s) for u, v in m], 0.2 * s, GLOW, (0, y + 0.015, 0)))
    return out


parts = []
# big pumpkin centre back, two smaller in front at the sides
for name, r, h, x, y, s in (("Big", 0.44, 0.62, 0.0, 0.12, 1.25), ("L", 0.3, 0.42, -0.56, -0.12, 0.85), ("R", 0.27, 0.38, 0.58, -0.16, 0.78)):
    parts.append(pumpkin(name, r, h, (x, y, 0)))
    parts.append(tube(name + "Stem", [(x, y, h - 0.06), (x + 0.02, y, h + 0.08 * s), (x + 0.07 * s, y, h + 0.13 * s)], [0.05 * s, 0.04 * s, 0.035 * s], STEM, segs=5))
    parts += face(name, r, h, x, y, s)
# a candle on the ground between the front two
parts.append(gcyl("Candle", 0.06, 0.2, (-0.2, -0.36, 0), shade(WAX, 0.9), WAX, segs=8))
parts.append(blob("Flame", 0.05, (-0.2, -0.36, 0.27), FLAME, subdiv=1, jitter=0, squash=(1, 1, 1.7)))
ship("habitat_prop_pumpking", parts)
