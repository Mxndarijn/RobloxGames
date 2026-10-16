# fountain_tier_crest: floating halo crown for the top of the fountain (13 x 6.4 x 13 studs, ~1k tris).
# Runtime-only (FountainTiers): hovers over the goo crown from tier 3, spins slowly. Pale base colours so
# MeshPart.Color (silver / gold) tints it; the gems stay near-white so they glow brightest.
import math
from lib import *

R = 6.2
BAND, BAND_D = rgb(240, 232, 214), rgb(196, 186, 168)
GLASS, GLASS_HI = rgb(255, 250, 235), rgb(255, 255, 255)
parts = []
N = 8
for i in range(N):
    a = i * math.tau / N
    x, y = math.cos(a) * R, math.sin(a) * R
    deg = math.degrees(a)
    # band segment (chord box) + tall spike on every vertex + a small gem on the band between spikes
    b = a + math.tau / N / 2
    mx, my = math.cos(b) * R * math.cos(math.tau / N / 2), math.sin(b) * R * math.cos(math.tau / N / 2)
    chord = 2 * R * math.sin(math.tau / N / 2) + 0.1
    parts.append(box(f"Band{i}", (0.8, chord, 1.0), (mx, my, 0.5), BAND, rot=(0, 0, math.degrees(b))))
    parts.append(box(f"Under{i}", (0.7, chord - 0.4, 0.22), (mx, my, 0.1), BAND_D, rot=(0, 0, math.degrees(b))))
    parts.append(cylinder(f"Spike{i}", 0.75, 3.6 if i % 2 == 0 else 2.6, (x, y, 0.6), BAND, segs=6, r_top=0.0))
    parts.append(blob(f"Ball{i}", 0.5, (x, y, 0.65), BAND_D, subdiv=1, jitter=0))
    parts.append(blob(f"Gem{i}", 0.42, (mx, my, 1.25), GLASS, subdiv=1, squash=(0.9, 0.9, 1.3), jitter=0, rot=(0, 0, math.degrees(b))))
    parts.append(blob(f"Star{i}", 0.3, (x, y, 0.6 + (3.6 if i % 2 == 0 else 2.6) + 0.25), GLASS_HI, subdiv=1, jitter=0))
# centre pendant gem hanging in the middle on four thin chains of beads
parts.append(blob("Core", 1.15, (0, 0, 0.1), GLASS, subdiv=2, squash=(0.9, 0.9, 1.35), jitter=0))
parts.append(cone("CoreTip", 0.6, 1.2, (0, 0, 1.2), GLASS_HI, segs=6))
for k in range(4):
    a = k * math.tau / 4 + math.tau / 8
    parts.append(tube(f"Stay{k}", [(math.cos(a) * R * 0.97, math.sin(a) * R * 0.97, 0.45), (math.cos(a) * 1.0, math.sin(a) * 1.0, 0.1)], [0.14, 0.14], BAND_D, segs=4))
finish("fountain_tier_crest", parts)
