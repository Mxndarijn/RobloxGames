# obby_cannon_b (option B): a slime-mouth cannon (steal-a-slime obby, Aim the Cannon).
# The barrel is a fat orange slime lying on its belly with its huge mouth wide open: a thick rolled red-orange lip,
# a deep plum throat you climb into and a pink tongue on the floor of the mouth. Two big eyes on top look where it
# aims. Its goo foot spreads over a bolted slate swivel turntable (the pivot it sweeps round).
# Fits the old 4 x 3 x 4 cannon box; the swivel axis is x = y = 0, the mouth aims at -Y.
import math
from mathutils import Vector
from lib import *
from lib.goo import Ball, metaball_mesh, paint_goo
from models._obby_cannon_parts import *

ZC = 1.4
TILT = 14.0
D = axis_dir(TILT)
UP = Vector((0.0, math.sin(math.radians(TILT)), math.cos(math.radians(TILT))))
X = Vector((1, 0, 0))
C = Vector((0.0, 0.0, ZC))

SLIME_LO = rgb(255, 136, 52)
SLIME = rgb(255, 150, 54)
SLIME_HI = rgb(255, 196, 110)
LIP_LO = rgb(222, 78, 46)
LIP = rgb(244, 104, 60)
THROAT = rgb(96, 40, 78)
THROAT_HI = rgb(140, 60, 100)
TONGUE = rgb(255, 120, 150)
parts = []

# -- the swivel turntable (slate, bolted rim, dark seam) and the slime's goo foot spreading over it
parts.append(disc("TurnSeat", 1.86, 0.0, 0.22, METAL_LO, METAL_LO, segs=24))
parts.append(disc("Turntable", 1.74, 0.16, 0.3, METAL_LO, METAL, segs=24))
parts += bolts("Bolt", 12, 1.56, 0.46, ORANGE, r=0.12)
foot = [Ball((0, 0.1, 0.5), (1.35, 1.6, 0.32))]
for a, d, s in ((0.6, 1.25, 0.42), (2.0, 1.3, 0.38), (3.3, 1.2, 0.45), (4.4, 1.3, 0.36), (5.6, 1.2, 0.4)):
    foot.append(Ball((d * math.cos(a), d * math.sin(a) + 0.1, 0.46), (s, s, 0.16)))
foot = metaball_mesh("SlimeFoot", foot, resolution=0.14, tris=260, clamp_z=0.42)
parts.append(paint_goo(foot, lambda co, n: mix(SLIME_LO, SLIME, max(0.0, n.z) ** 2)))

# -- the body: a round back, a fat belly, then the mouth: rolled lip and the throat back inside
prof = [
    (0.0, -1.7), (0.55, -1.62), (0.92, -1.36), (1.12, -0.9), (1.18, -0.3),   # round back
    (1.12, 0.45), (1.12, 1.05), (1.22, 1.48),                                # belly widening to the mouth
    (1.26, 1.7), (1.14, 1.9), (0.9, 1.86), (0.8, 1.62),                      # rolled lip
    (0.78, 0.6), (0.62, -0.4), (0.0, -0.6),                                  # throat
]
cols = [SLIME_LO, SLIME, SLIME, SLIME, SLIME, SLIME, mix(SLIME, LIP, 0.4),
        LIP_LO, LIP, LIP, LIP_LO, THROAT_HI, THROAT, THROAT]


def wob(i, a):
    if i > 7 or i == 0:
        return 1.0
    return 1.0 + 0.035 * math.sin(3 * a + i * 0.9) + 0.02 * math.sin(5 * a + 1.3)


parts.append(smooth(lathe("Body", prof, cols, segs=22, pos=C, rot=barrel_rot(TILT), wobble=wob)))

# a gloss spot on the back, where the light catches the slime
gl = C + D * (-0.55) + UP * 1.12 + X * -0.35
parts.append(smooth(blob("Gloss", 0.32, gl, mix(SLIME, SLIME_HI, 0.55), subdiv=2, squash=(0.8, 1.2, 0.22), jitter=0,
                         rot=(-TILT, 0, 0))))

# -- the tongue on the floor of the mouth
tg = C + D * 1.15 - UP * 0.55
parts.append(smooth(blob("Tongue", 0.42, tg, TONGUE, subdiv=2, squash=(1.0, 1.5, 0.35), jitter=0,
                         rot=(-TILT, 0, 0))))

# -- two big eyes on top, looking along the aim
for s in (-1, 1):
    b = math.radians(30) * s
    n = (UP * math.cos(b) + X * math.sin(b)).normalized()
    eye = C + D * 1.05 + n * 1.2
    parts.append(smooth(blob(f"Eye{s}", 0.47, eye, WHITE, subdiv=2, squash=(1, 0.85, 1), jitter=0)))
    pupil = eye + D * 0.34 + n * 0.12 + X * (-0.03 * s)
    parts.append(smooth(blob(f"Pupil{s}", 0.25, pupil, INK, subdiv=2, squash=(1, 0.45, 1.1), jitter=0)))
    shine = pupil + D * 0.1 + n * 0.08 + X * 0.07
    parts.append(smooth(blob(f"Shine{s}", 0.07, shine, WHITE, subdiv=1, jitter=0)))

finish_smooth("obby_cannon_b", parts)
