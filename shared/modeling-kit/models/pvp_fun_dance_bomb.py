# pvp_fun_dance_bomb: Dance Bomb (PvP fun item): a round cartoon bomb painted like a disco ball
# (flat-shaded mirror tiles), a butter cap and a curly fuse with a spark. Bottom on z=0.
import math, random
from models._pvp_fun import *

R = 0.75
GRIP = (0, 0, R)
TILES = [mix(WHITE, SKY, 0.25), mix(WHITE, LILAC, 0.5), LILAC, mix(WHITE, SKY, 0.6), mix(WHITE, PINK, 0.55)]


def ball():
    n = 11
    prof = [(R * math.sin(math.pi * j / n), R - R * math.cos(math.pi * j / n)) for j in range(n + 1)]
    r = random.Random(7)
    cache = {}

    def col(i, k, c):
        if (i, k) not in cache:
            cache[(i, k)] = BUTTER if r.random() < 0.07 else r.choice(TILES)
        return cache[(i, k)]
    return lathe("Ball", prof, col, segs=18, smooth=False)


def cap():
    prof = [(0.0, 1.35), (0.3, 1.35), (0.3, 1.58), (0.34, 1.6), (0.34, 1.66), (0.0, 1.68)]
    return lathe("Cap", prof, lambda i, k, c: mix(METAL, BUTTER, 0.5 if c.z > 1.59 else 0.2), segs=12)


def fuse():
    pts = [(0, 0, 1.6), (0.02, 0, 1.82), (0.12, 0.02, 1.98), (0.28, 0.0, 2.04), (0.38, -0.02, 2.16)]
    f = sweep("Fuse", pts, [0.06] * len(pts), mix(WOOD, CREAM, 0.3), segs=6)
    spark = ico("Spark", 0.15, BUTTER, subdiv=1, M=place((0.4, -0.02, 2.24), (20, 10, 0)), smooth=False, spikes=2.0)
    core = ico("SparkCore", 0.12, mix(RED, PINK, 0.3), subdiv=1, M=place((0.4, -0.02, 2.24)), smooth=False)
    return [f, spark, core]


ship("pvp_fun_dance_bomb", [ball(), cap()] + fuse(), GRIP)
