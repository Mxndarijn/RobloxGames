# Mystery Egg, rare tier: icy blue shell, raised zig-zag band and faceted crystal gems.
# Shell + band + decal recipe in models/_mystery_egg.py (shared silhouette: 2.2 tall, 1.7 wide).
import math
from lib import *
from models._mystery_egg import *

SHELL_LO = rgb(90, 166, 228)
SHELL_HI = rgb(150, 214, 248)
BAND_LO = rgb(70, 132, 220)
BAND_HI = rgb(110, 170, 244)
GEM_LO = rgb(160, 232, 250)
GEM_HI = rgb(244, 253, 255)


def shell_col(s, th, t):
    return mix(SHELL_LO, SHELL_HI, min(1.0, s * 1.1))


parts = [shell("Shell", shell_col)]

# Zig-zag band round the waist: 6 teeth, 36 samples (peaks every 3 samples).
ZC, AMP, HW, TEETH, N = 1.02, 0.17, 0.11, 6, 36
samples = []
for j in range(N):
    th = j * math.tau / N
    ph = (j * TEETH * 2 / N) % 2  # 0..2 per tooth
    tri = ph if ph <= 1 else 2 - ph  # 0..1..0
    samples.append((th, ZC + AMP * (tri * 2 - 1), HW))


def band_col(j, i, f):
    return facet_shade(f, BAND_LO, BAND_HI)


parts.append(ribbon("Band", samples, lift=0.07, color_fn=band_col))


def gem_col(kind, k, f):
    return facet_shade(f, GEM_LO, GEM_HI) if kind == "top" else BAND_LO


# Crystal gems in the zig-zag pockets: above the band at the low points, below it at the peaks.
for g in range(TEETH):
    th_low = (g * 2 + 0) * math.tau / (TEETH * 2)   # band low point -> gem above
    th_high = (g * 2 + 1) * math.tau / (TEETH * 2)  # band high point -> gem below
    if g % 2 == 0:
        z, th = ZC + 0.24, th_low
    else:
        z, th = ZC - 0.26, th_high
    parts.append(decal("Gem%d" % g, t_of_z(z), th, circle(0.2, n=6, sx=0.95, sy=1.25),
                       lift=0.05, lift_c=0.19, color_fn=gem_col))
# One crown gem near the tip.
parts.append(decal("GemTop", t_of_z(H - 0.22), 0.0, circle(0.2, n=6), lift=0.04, lift_c=0.18, color_fn=gem_col))

o = ship("mystery_egg_shiny", parts)
