# fountain_tier_ring: low curb of eight lantern posts round the fountain's foot (32 x 6 x 32 studs, ~1.1k tris).
# Runtime-only (FountainTiers): the client clones it round the fountain at tier 2+ and tints it per tier with
# MeshPart.Color, so the vertex colours are pale stone + near-white glass (copper / silver / gold multiply onto them).
import math
from lib import *

R = 14.6  # post circle radius (plinth is 13.1, trim 12.3)
STONE, STONE_D = rgb(236, 230, 220), rgb(190, 182, 172)
GLASS, GLASS_HI = rgb(255, 250, 235), rgb(255, 255, 255)
parts = []
N = 8
for i in range(N):
    a = i * math.tau / N
    x, y = math.cos(a) * R, math.sin(a) * R
    deg = math.degrees(a)
    parts.append(cylinder(f"Foot{i}", 1.5, 0.7, (x, y, 0), STONE_D, segs=8, r_top=1.25))
    parts.append(cylinder(f"Post{i}", 1.0, 2.6, (x, y, 0.7), STONE, segs=8, r_top=0.75))
    parts.append(cylinder(f"Cap{i}", 1.3, 0.45, (x, y, 3.3), STONE_D, segs=8, r_top=1.05))
    parts.append(blob(f"Gem{i}", 1.05, (x, y, 4.5), GLASS, subdiv=1, squash=(0.85, 0.85, 1.3), jitter=0, rot=(0, 0, deg)))
    parts.append(cone(f"Tip{i}", 0.5, 0.9, (x, y, 5.3), GLASS_HI, segs=6))
    # low curb between this post and the next: a chord box, slightly arched by two stacked stones
    b = (i + 0.5) * math.tau / N
    mx, my = math.cos(b) * (R * math.cos(math.tau / N / 2)), math.sin(b) * (R * math.cos(math.tau / N / 2))
    chord = 2 * R * math.sin(math.tau / N / 2) - 2.2
    parts.append(box(f"Curb{i}", (1.5, chord, 1.0), (mx, my, 0.5), STONE_D, rot=(0, 0, math.degrees(b))))
    parts.append(box(f"Rail{i}", (0.9, chord - 1.2, 0.5), (mx, my, 1.25), STONE, rot=(0, 0, math.degrees(b))))
finish("fountain_tier_ring", parts)
