# pvp_fun_confetti: Confetti Popper, a party popper cone (PvP fun item), held upright, opening up.
# Spiral-striped cone, cream lip, a heap of confetti in the mouth, pull string with a ring at the bottom (z=0).
import math, random
from models._pvp_fun import *

GRIP = (0, 0, 0.95)
STRIPES = [PINK, BUTTER, SKY, LILAC]
Z0, Z1 = 0.42, 2.0


def cone_body():
    prof = [(0.0, 0.34), (0.16, 0.34), (0.2, 0.38)]
    n = 10
    for j in range(n + 1):
        z = Z0 + (Z1 - Z0) * j / n
        prof.append((0.2 + 0.44 * (j / n) ** 0.95, z))
    prof += [(0.72, 2.02), (0.72, 2.14), (0.56, 2.14), (0.56, 2.04), (0.0, 2.04)]

    def col(i, k, c):
        if c.z < Z0:
            return RED
        if c.z > Z1 - 0.01:
            return CREAM
        a = (math.atan2(c.y, c.x) / math.tau) % 1.0
        s = int(a * 8 + (c.z - Z0) * 2.4) % 4
        return STRIPES[s] if c.z > 1.0 else mix(STRIPES[s], RED_D, 0.12 * (1.0 - c.z))
    return lathe("Cone", prof, col, segs=16, smooth=False)


def confetti():
    """A tuft bursting out of the mouth: 3 curly paper streamers + paper squares fanning up and out."""
    r = random.Random(4)
    parts = []
    cols = [PINK, BUTTER, SKY, LILAC, GOO, RED]
    for j, (a0, col) in enumerate(((0.3, PINK), (2.4, BUTTER), (4.4, SKY))):
        pts, rad = [], []
        for s in range(10):
            t = s / 9
            a = a0 + t * 1.5 * math.tau
            rr = 0.1 + 0.16 * math.sin(t * math.pi) + 0.18 * t
            d = 0.25 + 0.25 * t
            pts.append((d * math.cos(a0) + rr * math.cos(a), d * math.sin(a0) + rr * math.sin(a), 2.0 + 0.85 * t))
            rad.append(0.065)
        parts.append(sweep("Streamer%d" % j, pts, rad, col, segs=5))
    for j in range(16):
        a = j * math.tau / 16 + r.uniform(-0.2, 0.2)
        t = r.random()
        d = 0.15 + 0.45 * t
        z = 2.12 + 0.2 + 0.55 * t + r.uniform(-0.1, 0.15)
        parts.append(box_part("Bit%d" % j, (0.18, 0.18, 0.04), cols[j % len(cols)],
                              M=place((d * math.cos(a), d * math.sin(a), z),
                                      (r.uniform(-60, 60), r.uniform(-60, 60), r.uniform(0, 90)))))
    return parts


def pull_string():
    s = sweep("String", [(0, 0, 0.36), (0.03, 0, 0.3), (0.08, 0, 0.28)], [0.05, 0.05, 0.05], CREAM, segs=6)
    ring = torus("Pull", 0.15, 0.055, RED, segs=12, rsegs=5, M=place((0.1, 0, 0.17), (90, 0, 0)))
    return [s, ring]


ship("pvp_fun_confetti", [cone_body()] + confetti() + pull_string(), GRIP)
