# habitat_prop_goomancer: an open spellbook on a wooden lectern, a glowing green rune on its pages.
import math
from models._habitat_prop3 import *

COVER, COVER_LO = rgb(132, 70, 206), rgb(96, 50, 160)
PAGE, PAGE_LO = rgb(255, 246, 222), rgb(232, 214, 180)
RUNE = rgb(110, 255, 160)
parts = []
# lectern: round foot, post, slanted top board
foot = lathe("Foot", [(0, 0), (0.42, 0), (0.42, 0.08), (0.3, 0.14), (0, 0.14)], segs=10,
             color_fn=lambda i, k, z: WOOD_LO if i < 2 else WOOD)
parts.append(foot)
post = cylinder("Post", 0.11, 0.7, (0, 0.05, 0.12), WOOD, segs=6, r_top=0.08)
parts.append(grad(post, WOOD_LO, WOOD))
TILT = 28  # top board slopes down toward the front
top = box("Top", (1.1, 0.7, 0.08), (0, 0, 0), WOOD)
bevel(top, 0.025)
grad(top, WOOD_LO, WOOD)
lip = box("Lip", (1.1, 0.06, 0.1), (0, -0.36, 0.06), WOOD_LO)
board = [top, lip]
# book: cover slab, two page blocks bowed up from the spine (spine runs front to back, along Y)
cover = box("Cover", (1.02, 0.62, 0.05), (0, 0, 0.065), COVER)
board.append(cover)
for s in (-1, 1):
    pg = lathe(f"Pages{s}", [(0, 0), (0.24, 0.0), (0.24, 0.1), (0, 0.13)], segs=4, phase=math.pi / 4)
    xf(pg, (s * 0.25, 0, 0.09), (0, 0, 0), (1.35, 1.6, 1))
    paint_faces(pg, lambda p, n: PAGE if n.z > 0.5 else PAGE_LO)
    board.append(pg)
    # rune on each page: a ring of small glowing slabs and a centre dot
    for j in range(5):
        a = j / 5 * math.tau
        board.append(box(f"Rune{s}{j}", (0.07, 0.07, 0.02), (s * 0.25 + math.cos(a) * 0.12, math.sin(a) * 0.12, 0.215), RUNE))
    board.append(box(f"RuneC{s}", (0.06, 0.06, 0.02), (s * 0.25, 0, 0.215), rgb(200, 255, 220)))
board.append(box("Spine", (0.05, 0.62, 0.1), (0, 0, 0.17), PAGE_LO))
board.append(box("Ribbon", (0.04, 0.02, 0.3), (0.06, -0.3, 0.0), rgb(240, 70, 90)))
for o in board:
    xf(o, (0, 0.05, 0.86), (TILT, 0, 0))
parts += board
ship("habitat_prop_goomancer", parts)
