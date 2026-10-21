# Concept scene (not an asset): the goo jar tower's floor-to-floor stair, in the options for mobile players.
# STAIR_OPT picks one: "now" (today's steps), "ramp" (a smooth spiral ramp with a brass rail), "wide" (wider steps),
# "climb" (today's steps plus a "Climb" prompt at the foot), "lift" (an owner goo lift in the centre post).
# Game numbers: floors 16 studs apart, post radius 1.5, tread outer radius 5.5, 16 steps a floor, 22.5 deg a step.
# The deck above is cut away on the camera side so the stair shows.
import math
import os

from lib import *
from models._goo_jar import CORK, GOO, GOO_HI, METAL, WOOD, lathe, painted

OPT = os.environ.get("STAIR_OPT", "now")
FLOOR_H, STEPS, STEP_DEG = 16.0, 16, 22.5
POST = 1.5
OUTER = 8.0 if OPT == "wide" else 5.5
HOLE = OUTER + 0.5
parts = []

# floor below and the deck above (a cork ring round the stair hole, cut away on the -Y side)
parts.append(painted(cylinder("Floor", 12, 0.4, (0, 0, -0.4), CORK, segs=48), shade(CORK, 0.85), CORK))
parts.append(painted(lathe("Deck", [(HOLE, FLOOR_H - 1.0), (12, FLOOR_H - 1.0), (12, FLOOR_H), (HOLE, FLOOR_H)], CORK, 20, 250,
                           double=False), shade(CORK, 0.8), CORK))
parts.append(painted(lathe("DeckGoo", [(12, FLOOR_H + 0.02), (HOLE, FLOOR_H + 0.02)], GOO, 20, 250, double=False), shade(GOO, 0.9), GOO_HI))
parts.append(painted(cylinder("Post", POST, FLOOR_H, (0, 0, 0), GOO, segs=20), shade(GOO, 0.85), mix(GOO, GOO_HI, 0.4)))


def at(r, deg, z=0.0):
    a = math.radians(deg)
    return (r * math.cos(a), r * math.sin(a), z)


if OPT == "ramp":
    # a smooth spiral ramp from the floor up to the deck, one turn, with a brass rail on the open side
    n = 96
    bm_pts = []
    for i in range(n + 1):
        t = i / n
        bm_pts.append((t * 360.0 - 90, t * FLOOR_H))
    import bmesh
    from lib.shapes import obj_from_bm
    bm = bmesh.new()
    inner, outer, inner_lo, outer_lo = [], [], [], []
    for deg, z in bm_pts:
        inner.append(bm.verts.new(at(POST, deg, z)))
        outer.append(bm.verts.new(at(OUTER, deg, z)))
        inner_lo.append(bm.verts.new(at(POST, deg, z - 0.5)))
        outer_lo.append(bm.verts.new(at(OUTER, deg, z - 0.5)))
    for k in range(n):
        bm.faces.new((inner[k], outer[k], outer[k + 1], inner[k + 1]))
        bm.faces.new((inner_lo[k + 1], outer_lo[k + 1], outer_lo[k], inner_lo[k]))
        bm.faces.new((outer[k], outer_lo[k], outer_lo[k + 1], outer[k + 1]))
    parts.append(painted(obj_from_bm("Ramp", bm, CORK), shade(CORK, 0.8), CORK))
    rail = [at(OUTER - 0.1, deg, z + 1.4) for deg, z in bm_pts[::4]]
    parts.append(tube("Rail", rail, [0.16] * len(rail), METAL, segs=8))
    for deg, z in bm_pts[::8]:
        parts.append(cylinder(f"Baluster{int(deg)}", 0.09, 1.4, at(OUTER - 0.1, deg, z), METAL, segs=6))
    # goo edge along the inside
    edge = [at(POST + 0.15, deg, z + 0.1) for deg, z in bm_pts[::4]]
    parts.append(painted(tube("GooEdge", edge, [0.18] * len(edge), GOO, segs=6), shade(GOO, 0.9), GOO_HI))
elif OPT == "lift":
    # owner goo lift: a glass tube round the post with a goo platform, and today's steps round it for everyone else
    for k in range(1, STEPS + 1):
        deg = -90 + (k - 1) * STEP_DEG
        mid = (POST + 2.6 + OUTER) / 2
        a = math.radians(deg)
        parts.append(painted(box(f"Tread{k}", (OUTER - POST - 2.6, 2.2, 1.0), (mid * math.cos(a), mid * math.sin(a), k - 0.5), CORK,
                                 rot=(0, 0, deg)), shade(CORK, 0.85), CORK))
    parts.append(lathe("LiftGlass", [(2.6, 0), (2.6, FLOOR_H + 0.5)], rgb(200, 240, 244), segs=32))
    parts.append(painted(cylinder("LiftPlatform", 2.5, 0.4, (0, 0, 6), GOO, segs=24), shade(GOO, 0.9), GOO_HI))
    parts.append(blob("Bubble", 0.5, (1.2, 1.2, 9), GOO_HI, subdiv=2, jitter=0))
    parts.append(blob("Bubble2", 0.35, (-1.0, 1.4, 12), GOO_HI, subdiv=2, jitter=0))
    parts.append(box("OwnerSign", (2.2, 0.2, 1.2), (0, -2.8, 2.2), rgb(240, 200, 60)))
else:
    for k in range(1, STEPS + 1):
        deg = -90 + (k - 1) * STEP_DEG
        mid = (POST + OUTER) / 2
        a = math.radians(deg)
        depth = 2.2 if OPT != "wide" else 2.2 * OUTER / 5.5
        parts.append(painted(box(f"Tread{k}", (OUTER - POST + 0.4, depth, 1.0), (mid * math.cos(a), mid * math.sin(a), k - 0.5), CORK,
                                 rot=(0, 0, deg)), shade(CORK, 0.85), CORK))
    if OPT == "climb":
        # the "Climb" prompt at the foot (a Roblox ProximityPrompt look) and the path it walks you up
        parts.append(box("PromptCard", (3.2, 0.2, 1.4), at(OUTER + 1.6, -100, 3.0), rgb(30, 30, 36), rot=(0, 0, -10)))
        parts.append(box("PromptKey", (0.9, 0.25, 0.9), at(OUTER + 1.6, -112, 3.0), rgb(250, 250, 250), rot=(0, 0, -10)))
        path = [at((POST + OUTER) / 2, -90 + t * 22.5, t + 1.3) for t in range(0, STEPS)]
        parts.append(painted(tube("Path", path, [0.12] * len(path), GOO_HI, segs=6), GOO_HI, GOO_HI))
        for k in range(0, STEPS, 3):
            parts.append(blob(f"Glow{k}", 0.25, at((POST + OUTER) / 2, -90 + k * 22.5, k + 1.3), GOO_HI, subdiv=1, jitter=0))

finish(f"_stair_{OPT}", parts)
