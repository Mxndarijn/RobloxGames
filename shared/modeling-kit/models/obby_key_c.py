# obby_key_c (option C): the star badge key (steal-a-slime obby, Key Run).
# A thick flat cut-out like a toy or a sticker: a five-point star bow with a purple gem (the gate's colour, so key and
# gate read as a pair) on a chunky blade with two square teeth, all gold on a darker orange outline that shows from
# the front and the back. The boldest silhouette of the three; flat, so it wants a slow spin in game. Upright, faces
# -Y. Fits the old 1.5-stud key box (height ~1.6).
import math
from mathutils import Vector
from lib import *
from models._obby_key_parts import *

parts = []
STAR_Z, STAR_R, STAR_IN = 1.0, 0.45, 0.25
RIM_OUT = 0.07     # how far the orange outline sticks out past the gold

BLADE = [(-0.15, 0.0), (0.42, 0.0), (0.42, 0.15), (0.25, 0.15), (0.25, 0.33), (0.38, 0.33), (0.38, 0.47),
         (0.15, 0.47), (0.15, 0.8), (-0.15, 0.8)]  # the notch is taller than 2 x RIM_OUT so the outline never folds
STAR = star_pts(5, STAR_R, STAR_IN, 0.0, STAR_Z)


def rim_col(co, n):
    return metal(co, n, lo=RIM, mid=mix(RIM, GOLD, 0.2), hi=mix(RIM, GOLD, 0.45), shine=mix(RIM, GOLD_HI, 0.5))


# -- the orange outline behind (a little bigger and thinner than the gold faces)
parts.append(paint(slab("BladeRim", offset_pts(BLADE, RIM_OUT), 0.24, bev=0.03), rim_col, False))
parts.append(paint(slab("StarRim", offset_pts(STAR, RIM_OUT), 0.26, bev=0.03), rim_col, False))

# -- the gold faces (the star a touch thicker so its face sits proud of the blade's: no z-fight)
parts.append(paint(slab("Blade", BLADE, 0.34, bev=0.04), metal, False))
parts.append(paint(slab("Star", STAR, 0.4, bev=0.05), metal, False))


# -- a sticker shine: a short pale streak on the star's upper-left, front and back
for k, y in enumerate((-0.2, 0.2)):
    sh = [(-0.13, STAR_Z + 0.18), (-0.08, STAR_Z + 0.18), (-0.015, STAR_Z + 0.33), (-0.045, STAR_Z + 0.36)]
    if y > 0:
        sh = [(-u, v) for u, v in reversed(sh)]
    parts.append(paint(slab(f"Shine{k}", sh, 0.03, pos=(0, y, 0)), lambda co, n: mix(GOLD_HI, GOLD_SHINE, 0.6), False))

# -- the gem: a faceted purple stone through the star, showing on both faces
def gem_col(co, n):
    d = n.dot(LIGHT)
    c = mix(GATE_LO, GATE, min(1.0, 0.5 + n.z * 0.5))
    if d > 0.3:
        c = mix(c, GATE_HI, min(1.0, (d - 0.3) / 0.5))
    return c


parts.append(paint(blob("Gem", 0.22, (0, 0, STAR_Z), subdiv=1, jitter=0, squash=(1, 1.6, 1)), gem_col, False))

finish_smooth("obby_key_c", parts)
